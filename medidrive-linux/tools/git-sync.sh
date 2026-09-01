#!/usr/bin/env bash

# Git Sync
# Syncs the local repos directory with the GitHub org: clones missing repos,
# fast-forwards existing ones, prunes repos no longer in the org.
# Usage: git-sync               (optionally PARALLEL_JOBS=16 ..., MEDIDRIVE_ROOT=...)

set -euo pipefail

# Require bash 4+ for associative arrays. On macOS, /bin/bash is 3.2; users
# should install bash via Homebrew (or any recent bash). `env bash` above
# finds whichever comes first on PATH.
if (( BASH_VERSINFO[0] < 4 )); then
    echo "This script requires bash 4 or newer (found ${BASH_VERSION})." >&2
    echo "On macOS: brew install bash" >&2
    exit 1
fi

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Absolute path to this script; workers are re-invoked through it, so $0 is not
# reliable (it may be a relative path resolved against a different cwd).
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# Directory holding the local clones.
DEFAULT_REPOS_DIR="${MEDIDRIVE_ROOT:-$HOME/medidrive}/repos"

# Repositories to exclude from processing
# Add repository names here (directory names, not paths)
EXCLUDED_REPOS=(
    # "nemt-standing-order-service"
    "nemt-mcp-service"
    "vendor-syncs"    
    "interview-task"
    "task-01"
    "task-02"
    "task-03"
)

# Repository name prefixes to exclude from processing.
# Matched against the repo/directory name only, so names that merely contain a
# prefix (e.g. "nemt-ip-atms-service") are not excluded.
EXCLUDED_REPO_PREFIXES=(
    "tms-"
)

# Branch priority order for updates
# The first existing branch in this list will be used
BRANCH_PRIORITY=(
   # "sandbox"
    "staging"
    "master"
    "main"
)

# GitHub organization to sync against
DEFAULT_GITHUB_ORG="MediDrive-Tech"

# Preferred GitHub CLI account for MediDrive org access
DEFAULT_MEDIDRIVE_GH_USER="andytomamedi"

# Max concurrent repo operations (clones, fetches).
# Override with PARALLEL_JOBS=16 ./git-sync.sh
PARALLEL_JOBS="${PARALLEL_JOBS:-8}"

# Lock file used to prevent two concurrent runs from fighting over the
# same working directories. We use mkdir (atomic on macOS + Linux) instead of
# flock because flock isn't installed on stock macOS.
SYNC_LOCK_DIR="${TMPDIR:-/tmp}/git-sync.lock"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

is_excluded_repo() {
    local repo_name="$1"

    for excluded in "${EXCLUDED_REPOS[@]-}"; do
        if [[ "$repo_name" == "$excluded" ]]; then
            return 0
        fi
    done

    for prefix in "${EXCLUDED_REPO_PREFIXES[@]-}"; do
        [[ -z "$prefix" ]] && continue
        if [[ "$repo_name" == "$prefix"* ]]; then
            return 0
        fi
    done

    return 1
}

origin_belongs_to_org() {
    local repo_dir="$1"
    local org="$2"
    local remote_url

    remote_url=$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)
    [[ "$remote_url" =~ [:/]${org}/[^/]+(\.git)?$ ]]
}

repo_has_local_changes() {
    local repo_dir="$1"
    [[ -n $(git -C "$repo_dir" status --porcelain 2>/dev/null) ]]
}

repo_has_unpushed_commits() {
    local repo_dir="$1"
    local upstream

    upstream=$(git -C "$repo_dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
    if [[ -z "$upstream" ]]; then
        return 0
    fi

    [[ -n $(git -C "$repo_dir" log --oneline "${upstream}..HEAD" 2>/dev/null) ]]
}

list_repo_dirs() {
    local search_dir="$1"

    [[ -d "$search_dir" ]] || return 0
    find "$search_dir" -mindepth 1 -maxdepth 1 -type d ! -name ".*"
}

# ============================================================================
# PER-REPO WORKERS (used both directly and via xargs -P for parallel sync)
# ============================================================================
# Each worker writes human-readable progress to a per-repo log file so parallel
# output doesn't interleave. It prints a single-line RESULT tag to stdout that
# the parent counts. Exit code is always 0 so xargs keeps processing siblings;
# failures are carried in the RESULT tag.

# Pick the highest-priority branch that exists in the repo (local or remote).
# Falls back to the repo's remote HEAD (default branch) if none of BRANCH_PRIORITY
# match — handles repos with unconventional defaults like `docs` or `agent`.
pick_target_branch() {
    local repo_dir="$1"
    # Build a set of existing refs in one subshell (was: one grep per priority
    # entry). Strips "origin/" prefix so "dev" and "origin/dev" both count as
    # "dev" membership.
    declare -A ref_set
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        ref_set["${line#origin/}"]=1
    done < <(git -C "$repo_dir" for-each-ref --format='%(refname:short)' refs/heads refs/remotes/origin 2>/dev/null || true)

    for branch in "${BRANCH_PRIORITY[@]}"; do
        if [[ -n "${ref_set[$branch]:-}" ]]; then
            printf '%s' "$branch"
            return 0
        fi
    done

    # Fallback: use origin's HEAD branch. `git remote show origin` requires a
    # network call; use `symbolic-ref refs/remotes/origin/HEAD` which reads
    # local git state set by `git clone` / `git remote set-head`.
    local head_ref
    head_ref=$(git -C "$repo_dir" symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null || true)
    if [[ -n "$head_ref" ]]; then
        local stripped="${head_ref#origin/}"
        # Validate: if the recorded HEAD branch no longer has a tracking ref,
        # the org probably changed its default branch. Refresh it (one network
        # call) and re-read. This is rare — only hits repos with unusual
        # default branches we already fell through to.
        if [[ -z "${ref_set[$stripped]:-}" ]]; then
            git -C "$repo_dir" remote set-head origin --auto >/dev/null 2>&1 || true
            head_ref=$(git -C "$repo_dir" symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null || true)
            stripped="${head_ref#origin/}"
        fi
        if [[ -n "$stripped" ]]; then
            printf '%s' "$stripped"
            return 0
        fi
    fi

    return 1
}

# Clone a single repo then run update on it. Writes a single RESULT line for
# the combined operation so the parent can count it once.
# $1=org, $2=repo_name, $3=search_dir, $4=log_dir
clone_repo_worker() {
    local org="$1"
    local repo_name="$2"
    local search_dir="$3"
    local log_dir="$4"
    local dest="$search_dir/$repo_name"
    local log="$log_dir/clone-$repo_name.log"

    (
        echo "== clone $org/$repo_name -> $dest"
        # Full clone (no partial/blobless). Partial clones (--filter=blob:none)
        # save bandwidth on initial fetch but leave repos in a fragile state
        # if interrupted: blobs are fetched lazily on first checkout, and an
        # aborted checkout can leave the working tree and index empty while
        # the object DB is intact, requiring a full reset --hard to recover.
        if gh repo clone "$org/$repo_name" "$dest"; then
            echo "OK"
        else
            echo "FAIL"
        fi
    ) >"$log" 2>&1

    local last
    last=$(tail -n 1 "$log" 2>/dev/null || echo "")
    if [[ "$last" != "OK" ]]; then
        printf 'CLONE_FAIL\t%s\n' "$repo_name"
        return 0
    fi

    # Freshly cloned — run update to switch to the priority branch (gh clones
    # land on the default branch, which may be `main` instead of `dev`).
    # update_repo_worker writes its own log and emits an UPDATE_ tag; we
    # translate that into a CLONE result for reporting.
    local update_result
    update_result=$(update_repo_worker "$dest" "$log_dir")
    # A freshly cloned repo can legitimately report SKIP (gh clone already
    # landed it on the default branch and the SHA matched). Either OK or SKIP
    # means the clone succeeded.
    if [[ "$update_result" == UPDATE_OK* || "$update_result" == UPDATE_SKIP* ]]; then
        printf 'CLONE_OK\t%s\n' "$repo_name"
    else
        printf 'CLONE_FAIL\t%s\n' "$repo_name"
    fi
}

# Remove stale `.lock` files from a repo's refs tree. Git writes a `.lock`
# alongside a ref when atomically updating it; if a previous git invocation
# crashed (Ctrl+C, OOM) the lock is never cleaned and poisons every future
# fetch/prune. We only clear locks older than 60s to avoid stomping on a live
# concurrent git process. Also cleans index.lock and packed-refs.lock.
cleanup_stale_locks() {
    local repo_dir="$1"
    local git_dir="$repo_dir/.git"
    [[ -d "$git_dir" ]] || return 0

    # -mmin +1 => older than 60s. Quiet if nothing matches.
    find "$git_dir" \
        \( -name '*.lock' \) \
        -type f -mmin +1 \
        -print -delete 2>/dev/null || true
}

# Update a single repo. $1=repo_dir, $2=log_dir
# Emits one of: UPDATE_OK, UPDATE_SKIP (remote unchanged), UPDATE_FAIL
update_repo_worker() {
    local repo_dir="$1"
    local log_dir="$2"
    local repo_name
    repo_name=$(basename "$repo_dir")
    local log="$log_dir/update-$repo_name.log"

    (
        echo "== update $repo_name"

        cleanup_stale_locks "$repo_dir"

        if repo_has_local_changes "$repo_dir"; then
            echo "warn: uncommitted changes"
        fi

        # Pick the target branch before deciding whether to fetch. We prefer
        # the highest-priority remote branch if one exists so a newly created
        # `staging` wins immediately over a stale local/default-branch choice.
        local target_branch=""
        local target_remote_sha=""
        local remote_refs=""
        if remote_refs=$(git -C "$repo_dir" ls-remote --heads --quiet origin \
                "${BRANCH_PRIORITY[@]}" 2>/dev/null); then
            if [[ -n "$remote_refs" ]]; then
                declare -A remote_sha_by_branch=()
                while IFS=$'\t' read -r remote_sha remote_ref; do
                    [[ -z "$remote_sha" ]] && continue
                    branch="${remote_ref#refs/heads/}"
                    remote_sha_by_branch["$branch"]="$remote_sha"
                done <<< "$remote_refs"

                for branch in "${BRANCH_PRIORITY[@]}"; do
                    if [[ -n "${remote_sha_by_branch[$branch]:-}" ]]; then
                        target_branch="$branch"
                        target_remote_sha="${remote_sha_by_branch[$branch]}"
                        break
                    fi
                done
            fi
        fi

        if [[ -z "$target_branch" ]]; then
            if ! target_branch=$(pick_target_branch "$repo_dir"); then
                echo "fail: no suitable branch from ${BRANCH_PRIORITY[*]}"
                echo "FAIL"
                exit 0
            fi
        fi

        # Fast path: compare the selected branch's remote SHA to the local
        # tracking ref. Only skip fetch if the branch we are about to merge is
        # already current.
        skip_fetch=false
        if [[ -n "$target_remote_sha" ]]; then
            local_sha=$(git -C "$repo_dir" rev-parse --verify --quiet \
                "refs/remotes/origin/$target_branch" 2>/dev/null || true)
            if [[ -n "$local_sha" && "$local_sha" == "$target_remote_sha" ]]; then
                skip_fetch=true
                echo "skip-fetch: $target_branch already at $target_remote_sha"
            fi
        fi

        if [[ "$skip_fetch" != true ]]; then
            # Try a narrow fetch (just branches we care about) for speed. If
            # the remote is missing any of those refs, git aborts, so fall
            # back to a full fetch. This keeps the bandwidth win on the
            # common case and stays correct for repos that only have master
            # or only main.
            if ! git -C "$repo_dir" fetch --prune --no-tags --quiet origin \
                    "${BRANCH_PRIORITY[@]}" 2>/dev/null; then
                if ! git -C "$repo_dir" fetch --prune --no-tags --quiet origin; then
                    echo "fail: fetch"
                    echo "FAIL"
                    exit 0
                fi
            fi
        fi

        # Empty repo (no branches anywhere)? Nothing to sync; count as OK.
        if [[ -z "$(git -C "$repo_dir" for-each-ref --format='%(refname)' refs/heads refs/remotes/origin 2>/dev/null)" ]]; then
            echo "ok: empty repo (no branches)"
            echo "OK"
            exit 0
        fi

        # Create local branch tracking origin/<target_branch> if missing.
        if ! git -C "$repo_dir" rev-parse --verify --quiet "refs/heads/$target_branch" >/dev/null; then
            git -C "$repo_dir" branch "$target_branch" "origin/$target_branch" || true
        fi

        # Only checkout if we're not already on the target branch.
        current_branch=$(git -C "$repo_dir" symbolic-ref --short -q HEAD || echo "")
        if [[ "$current_branch" != "$target_branch" ]]; then
            if ! git -C "$repo_dir" checkout --quiet "$target_branch"; then
                echo "fail: checkout $target_branch"
                echo "FAIL"
                exit 0
            fi
        fi

        # If we skipped the fetch AND we're already at origin/<target_branch>,
        # there's literally nothing to do. Report SKIP so the summary can
        # distinguish no-op runs from actual updates.
        if [[ "$skip_fetch" == true ]]; then
            local_head=$(git -C "$repo_dir" rev-parse --verify --quiet HEAD 2>/dev/null || true)
            remote_head=$(git -C "$repo_dir" rev-parse --verify --quiet "refs/remotes/origin/$target_branch" 2>/dev/null || true)
            if [[ -n "$local_head" && "$local_head" == "$remote_head" ]]; then
                echo "ok: $target_branch (unchanged)"
                echo "SKIP"
                exit 0
            fi
        fi

        # Fast-forward merge only (no second fetch like `git pull` does).
        if ! git -C "$repo_dir" merge --ff-only --quiet "origin/$target_branch"; then
            echo "fail: ff-merge $target_branch (diverged?)"
            echo "FAIL"
            exit 0
        fi

        echo "ok: $target_branch"
        echo "OK"
    ) >"$log" 2>&1

    local last
    last=$(tail -n 1 "$log" 2>/dev/null || echo "")
    case "$last" in
        OK)   printf 'UPDATE_OK\t%s\n'   "$repo_name" ;;
        SKIP) printf 'UPDATE_SKIP\t%s\n' "$repo_name" ;;
        *)    printf 'UPDATE_FAIL\t%s\n' "$repo_name" ;;
    esac
}

# Unified sync worker. Dispatches to clone_repo_worker or update_repo_worker
# based on mode. Invoked by `sync` via xargs -P on a job list.
# Args: <org> <search_dir> <log_dir> <mode> <arg>
#   mode=clone   -> arg is the remote repo name
#   mode=update  -> arg is the absolute repo path
sync_one_worker() {
    local org="$1"
    local search_dir="$2"
    local log_dir="$3"
    local mode="$4"
    local arg="$5"

    case "$mode" in
        clone)
            clone_repo_worker "$org" "$arg" "$search_dir" "$log_dir"
            ;;
        update)
            update_repo_worker "$arg" "$log_dir"
            ;;
        *)
            printf 'SYNC_FAIL\t%s\n' "unknown mode: $mode"
            ;;
    esac
}

# ============================================================================
# SYNC ORG REPOS
# ============================================================================
sync_repos() {
    # Acquire lock. If another sync is already running, fail fast.
    # `mkdir` is atomic, so only one process wins the race.
    if ! mkdir "$SYNC_LOCK_DIR" 2>/dev/null; then
        local holder_pid
        holder_pid=$(cat "$SYNC_LOCK_DIR/pid" 2>/dev/null || echo "unknown")
        # If the PID is stale (process gone), steal the lock.
        if [[ "$holder_pid" != "unknown" ]] && ! kill -0 "$holder_pid" 2>/dev/null; then
            echo -e "${YELLOW}Stale lock from dead PID $holder_pid — stealing.${NC}"
            rm -rf "$SYNC_LOCK_DIR"
            mkdir "$SYNC_LOCK_DIR"
        else
            echo -e "${RED}Another sync is running (PID $holder_pid). Aborting.${NC}"
            exit 1
        fi
    fi
    echo $$ > "$SYNC_LOCK_DIR/pid"
    trap 'rm -rf "$SYNC_LOCK_DIR"' EXIT INT TERM

    local search_dir="$DEFAULT_REPOS_DIR"
    local org="$DEFAULT_GITHUB_ORG"

    if ! command -v gh >/dev/null 2>&1; then
        echo -e "${RED}Error: gh CLI is required for sync${NC}"
        exit 1
    fi

    echo "Switching gh to: $DEFAULT_MEDIDRIVE_GH_USER"
    if ! gh auth switch -u "$DEFAULT_MEDIDRIVE_GH_USER"; then
        echo -e "${RED}Error: failed to switch gh to '$DEFAULT_MEDIDRIVE_GH_USER'.${NC}"
        echo "Check available accounts with: gh auth status"
        exit 1
    fi

    mkdir -p "$search_dir"
    search_dir=$(cd "$search_dir" && pwd)

    echo "Syncing repos in: $search_dir"
    echo "GitHub org: $org"
    echo "----------------------------------------"

    local repo_json
    repo_json=$(gh repo list "$org" --limit 1000 --json name,sshUrl,isArchived,isEmpty)

    local remote_names=()
    while IFS=$'\t' read -r name _ssh_url is_archived is_empty; do
        [[ -z "$name" ]] && continue
        # Skip archived and empty repos; there's nothing useful to sync and
        # empty repos can't be updated (no branches exist). Already-cloned
        # empty repos will be removed by the prune phase.
        if [[ "$is_archived" == "true" || "$is_empty" == "true" ]]; then
            continue
        fi
        if is_excluded_repo "$name"; then
            continue
        fi
        remote_names+=("$name")
    done < <(printf '%s' "$repo_json" | jq -r '.[] | [.name, .sshUrl, .isArchived, .isEmpty] | @tsv')

    if [[ ${#remote_names[@]} -eq 0 ]]; then
        echo -e "${RED}Error: gh returned no visible repositories for org '$org'.${NC}"
        echo "This usually means the active GitHub CLI account does not have access to that org."
        echo "Check with: gh auth status"
        exit 1
    fi

    local local_org_repo_names=()
    local local_org_repo_paths=()
    while IFS= read -r repo_dir; do
        local repo_name
        repo_name=$(basename "$repo_dir")

        if [[ ! -d "$repo_dir/.git" ]]; then
            continue
        fi

        if is_excluded_repo "$repo_name"; then
            continue
        fi

        if ! origin_belongs_to_org "$repo_dir" "$org"; then
            continue
        fi

        local_org_repo_names+=("$repo_name")
        local_org_repo_paths+=("$repo_dir")
    done < <(list_repo_dirs "$search_dir")

    # Per-run log dir for parallel worker output. Kept on failure so the user
    # can inspect; cleaned at the end if everything succeeded.
    local log_dir
    log_dir=$(mktemp -d "${TMPDIR:-/tmp}/git-sync.XXXXXX")

    # ---------- Phase 1: unified parallel sync (clone missing + update existing) ----------
    # Both operations are independent and network-bound. Running them in one
    # worker pool keeps all `$PARALLEL_JOBS` slots busy even in the common
    # case where there are only a handful of missing repos.
    local cloned=0
    local clone_failed=0
    local updated=0
    local update_skipped=0
    local update_failed=0
    # Names of repos that failed on the first pass — we'll retry them once.
    local failed_clones=()
    local failed_updates=()
    local failed_update_paths=()

    # Build job list: one line per job. Format: <mode>\t<arg>   (mode ∈ {clone,update})
    local job_file="$log_dir/jobs.tsv"
    : >"$job_file"
    local total_to_update=0
    local total_to_clone=0
    for repo_path in "${local_org_repo_paths[@]-}"; do
        [[ -z "$repo_path" ]] && continue
        printf 'update\t%s\n' "$repo_path" >>"$job_file"
        total_to_update=$((total_to_update + 1))
    done
    for repo_name in "${remote_names[@]}"; do
        local exists=false
        for local_repo_name in "${local_org_repo_names[@]-}"; do
            if [[ "$local_repo_name" == "$repo_name" ]]; then
                exists=true
                break
            fi
        done
        if [[ "$exists" == false ]]; then
            printf 'clone\t%s\n' "$repo_name" >>"$job_file"
            total_to_clone=$((total_to_clone + 1))
        fi
    done

    local total_jobs=$((total_to_clone + total_to_update))

    echo ""
    echo -e "${BLUE}[1/2] Syncing: $total_to_clone to clone, $total_to_update to update (up to $PARALLEL_JOBS in parallel)${NC}"

    # Runs `$0 _sync-one` over the given job file and updates counters/arrays
    # in the caller's scope. Declared inline (not as a separate function) so
    # it has closure over all the counters; we just invoke it twice — once
    # for the main pass, once for retries.
    run_sync_pass() {
        local pass_job_file="$1"
        local pass_total="$2"
        local pass_label="$3"
        local progress=0

        if [[ ! -s "$pass_job_file" ]]; then
            [[ "$pass_label" == "retry" ]] || echo "  none"
            return 0
        fi

        # Stream results live as workers complete. Process substitution keeps
        # the loop in the main shell so counters/arrays persist.
        while IFS=$'\t' read -r status repo_name; do
            [[ -z "$status" ]] && continue
            progress=$((progress + 1))
            local prefix
            printf -v prefix '[%d/%d]' "$progress" "$pass_total"

            case "$status" in
                CLONE_OK)
                    echo -e "  $prefix ${GREEN}+${NC} $repo_name"
                    cloned=$((cloned + 1))
                    local_org_repo_names+=("$repo_name")
                    local_org_repo_paths+=("$search_dir/$repo_name")
                    ;;
                CLONE_FAIL)
                    echo -e "  $prefix ${RED}✗${NC} $repo_name (clone failed)"
                    failed_clones+=("$repo_name")
                    ;;
                UPDATE_OK)
                    echo -e "  $prefix ${GREEN}✓${NC} $repo_name"
                    updated=$((updated + 1))
                    ;;
                UPDATE_SKIP)
                    echo -e "  $prefix ${GREEN}·${NC} $repo_name (unchanged)"
                    update_skipped=$((update_skipped + 1))
                    ;;
                UPDATE_FAIL)
                    echo -e "  $prefix ${RED}✗${NC} $repo_name  (see $log_dir/update-$repo_name.log)"
                    failed_updates+=("$repo_name")
                    failed_update_paths+=("$search_dir/$repo_name")
                    ;;
            esac
        done < <(
            xargs -P "$PARALLEL_JOBS" -L 1 \
                "$SELF" _sync-one "$org" "$search_dir" "$log_dir" <"$pass_job_file"
        )
    }

    run_sync_pass "$job_file" "$total_jobs" "main"

    # ---------- Retry pass ----------
    # Transient issues (network blips, gh rate limits, brief git locks held
    # by a concurrent process) often clear on a second attempt. Rebuild a
    # job file from first-pass failures and run once more.
    # Smart filter: diverged branches (fail: ff-merge) are not transient —
    # retrying won't help, so skip them and leave the first-pass failure in
    # the final count.
    local retryable_updates=()
    local retryable_update_paths=()
    local skipped_retries_ffmerge=()
    local idx
    for ((idx=0; idx<${#failed_updates[@]}; idx++)); do
        local fname="${failed_updates[$idx]}"
        local fpath="${failed_update_paths[$idx]}"
        local flog="$log_dir/update-$fname.log"
        if [[ -f "$flog" ]] && grep -q '^fail: ff-merge' "$flog"; then
            skipped_retries_ffmerge+=("$fname")
            continue
        fi
        retryable_updates+=("$fname")
        retryable_update_paths+=("$fpath")
    done

    local retry_total=$((${#failed_clones[@]} + ${#retryable_updates[@]}))
    if [[ $retry_total -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}Retrying $retry_total failed repo(s)...${NC}"
        if [[ ${#skipped_retries_ffmerge[@]} -gt 0 ]]; then
            echo -e "${YELLOW}Skipping retry for ${#skipped_retries_ffmerge[@]} diverged repo(s): ${skipped_retries_ffmerge[*]}${NC}"
        fi
        local retry_job_file="$log_dir/jobs.retry.tsv"
        : >"$retry_job_file"
        for name in "${failed_clones[@]-}"; do
            [[ -z "$name" ]] && continue
            printf 'clone\t%s\n' "$name" >>"$retry_job_file"
        done
        for path in "${retryable_update_paths[@]-}"; do
            [[ -z "$path" ]] && continue
            printf 'update\t%s\n' "$path" >>"$retry_job_file"
        done
        # Preserve non-retryable failures; the retry pass will only repopulate
        # with any that still fail out of the retryable subset.
        failed_clones=()
        failed_updates=("${skipped_retries_ffmerge[@]}")
        failed_update_paths=()
        # Rebuild paths array in lockstep with names we kept.
        for ((idx=0; idx<${#failed_updates[@]}; idx++)); do
            failed_update_paths+=("$search_dir/${failed_updates[$idx]}")
        done
        run_sync_pass "$retry_job_file" "$retry_total" "retry"
    fi

    clone_failed=${#failed_clones[@]}
    update_failed=${#failed_updates[@]}

    # ---------- Phase 2: prune local repos missing from org ----------
    echo ""
    echo -e "${BLUE}[2/2] Pruning local repos not in org${NC}"
    local pruned=0
    local prune_skipped=0
    local prune_listed=0
    # Build an O(1) lookup of remote names so prune is linear in local repos
    # instead of quadratic.
    declare -A remote_name_set
    for remote_repo_name in "${remote_names[@]-}"; do
        remote_name_set["$remote_repo_name"]=1
    done
    for ((i=0; i<${#local_org_repo_names[@]}; i++)); do
        local repo_name="${local_org_repo_names[$i]}"
        local repo_path="${local_org_repo_paths[$i]}"

        if [[ -z "${remote_name_set[$repo_name]:-}" ]]; then
            prune_listed=$((prune_listed + 1))

            if repo_has_local_changes "$repo_path"; then
                prune_skipped=$((prune_skipped + 1))
                echo "  ! $repo_name (skipped: uncommitted changes)"
                continue
            fi

            if repo_has_unpushed_commits "$repo_path"; then
                prune_skipped=$((prune_skipped + 1))
                echo "  ! $repo_name (skipped: unpushed commits or no upstream)"
                continue
            fi

            echo "  - $repo_name"
            rm -rf "$repo_path"
            pruned=$((pruned + 1))
        fi
    done
    [[ $prune_listed -eq 0 ]] && echo "  none"

    echo ""
    echo "========================================"
    echo "Sync Summary:"
    echo "  Repos in org:        ${#remote_names[@]}"
    echo "  Cloned:              $cloned"
    [[ $clone_failed -gt 0 ]] && echo -e "  ${RED}Clone failed:        $clone_failed${NC}"
    echo -e "  ${GREEN}Updated:             $updated${NC}"
    [[ $update_skipped -gt 0 ]] && echo "  Unchanged:           $update_skipped"
    [[ $update_failed -gt 0 ]] && echo -e "  ${RED}Update failed:       $update_failed${NC}"
    echo "  Pruned:              $pruned"
    [[ $prune_skipped -gt 0 ]] && echo -e "  ${YELLOW}Prune skipped:       $prune_skipped${NC}"
    echo "========================================"

    # Failure breakdown — categorize each UPDATE_FAIL by inspecting the tail
    # of its per-repo log. Helps the user see at a glance whether failures
    # are all the same kind (e.g. diverged branches) vs scattered causes.
    if [[ $update_failed -gt 0 ]]; then
        local fail_fetch=0 fail_checkout=0 fail_ffmerge=0 fail_nobranch=0 fail_other=0
        local diverged_repos=()
        for name in "${failed_updates[@]}"; do
            local log="$log_dir/update-$name.log"
            [[ -f "$log" ]] || { fail_other=$((fail_other + 1)); continue; }
            # Grep for the classifying phrase in the worker's log.
            if grep -q '^fail: fetch' "$log"; then
                fail_fetch=$((fail_fetch + 1))
            elif grep -q '^fail: checkout' "$log"; then
                fail_checkout=$((fail_checkout + 1))
            elif grep -q '^fail: ff-merge' "$log"; then
                fail_ffmerge=$((fail_ffmerge + 1))
                diverged_repos+=("$name")
            elif grep -q '^fail: no suitable branch' "$log"; then
                fail_nobranch=$((fail_nobranch + 1))
            else
                fail_other=$((fail_other + 1))
            fi
        done

        echo ""
        echo -e "${RED}Update failure breakdown:${NC}"
        [[ $fail_fetch    -gt 0 ]] && echo "  fetch failed:           $fail_fetch"
        [[ $fail_checkout -gt 0 ]] && echo "  checkout failed:        $fail_checkout"
        [[ $fail_ffmerge  -gt 0 ]] && echo "  diverged (non-ff):      $fail_ffmerge  (${diverged_repos[*]})"
        [[ $fail_nobranch -gt 0 ]] && echo "  no matching branch:     $fail_nobranch"
        [[ $fail_other    -gt 0 ]] && echo "  other:                  $fail_other"
    fi

    if [[ $clone_failed -eq 0 && $update_failed -eq 0 ]]; then
        rm -rf "$log_dir"
    else
        echo ""
        echo "Worker logs kept at: $log_dir"
    fi
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================
main() {
    # Hidden worker entry point used by the parallel sync pool via xargs -P.
    if [[ "${1:-}" == "_sync-one" ]]; then
        shift
        sync_one_worker "$@"
        return
    fi

    if [[ $# -gt 0 ]]; then
        echo -e "${RED}Error: this script takes no arguments${NC}"
        echo "Usage: $0            (override parallelism: PARALLEL_JOBS=16 $0)"
        exit 1
    fi

    sync_repos
}

main "$@"
