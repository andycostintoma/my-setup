# Global Agent Rules

## Safety Rules

Never do these without explicit user permission:

| Action | Forbidden | Wait for |
|---|---|---|
| **Commit/push** | `git commit`, `git push`, `gh pr create` | "commit this", "push", "create a PR" |
| **Revert files** | `git checkout --`, `git restore`, `git reset` | "revert", "discard changes" |
| **Lint exclusions** | `nolint`, `noqa`, `eslint-disable`, linter config changes | Present options, let user decide |
| **Create docs** | New `.md`/`.txt` files, READMEs, summaries, guides | "create a doc", "write a README" |
| **Post comments** | Comments on GitHub (issues, PRs, reviews) or Linear (issues, projects, initiatives) | "post a comment", "comment on the ticket/PR" |

---

## Workflow Hygiene

- `AGENTS.md` = stable policy; commands/skills = execution playbooks; `PLAN.md` = active state only.
- On this machine, Nix and Home Manager are the source of truth for all durable system, user, package, shell, dotfile, and agent-harness configuration.
- Keep shared AI/agent setup under `shared/` in `my-setup`: global policy, commands, skills, agents, agent plugins, package wrappers, and stable harness config.
- Keep machine-specific overlays under `personal-mac/` for the local Mac and `medidrive-linux/` for the MediDrive VM.
- Nix/Home Manager publishes shared agentic files from `my-setup` into each active harness. Do not edit generated targets such as `~/.config/opencode/`, `~/.gemini/`, or `~/.claude/` directly when source exists in this repo.
- Cross-repo research: search/index first, then read only what is needed. Use subagents for broad exploration.
- When you find a structural smell, scan sibling flows for the same pattern and fix consistently.

### Privileged macOS Commands

For privileged commands that must run inside the user's interactive macOS Aqua session, use `sudo -A` with a GUI askpass helper instead of `osascript ... with administrator privileges`. This matters for `darwin-rebuild switch`: nix-darwin may touch `/Applications/Nix Apps/*.app`, and TCC App Management can reject non-Aqua root processes.

Create or reuse an askpass helper under `/var/folders/6t/kf485w6x5n1_n28tsq6_12sw0000gn/T/my-setup-askpass.sh`:

```sh
#!/bin/sh
osascript \
  -e 'Tell application "System Events" to display dialog "Administrator password required" default answer "" with hidden answer buttons {"OK"} default button "OK"' \
  -e 'text returned of result'
```

Then run privileged commands from the current terminal process with `SUDO_ASKPASS=/var/folders/6t/kf485w6x5n1_n28tsq6_12sw0000gn/T/my-setup-askpass.sh sudo -A <command>`. For example: `DR=$(command -v darwin-rebuild); SUDO_ASKPASS=/var/folders/6t/kf485w6x5n1_n28tsq6_12sw0000gn/T/my-setup-askpass.sh sudo -A "$DR" switch --flake path:/Users/andytoma/my-setup/personal-mac`.

If debugging, `SUDO_ASKPASS=... sudo -A launchctl managername` should print `Aqua`, not `System`.

---

## Correctness Over Closure

Always optimize for long-term correctness and purity, not quick closure.

- Fix adjacent issues discovered during the task while context is hot.
- Defer only when it genuinely belongs elsewhere; create a tracking artifact before moving on.
- Do not silently downgrade severity or hide investigation findings.
- If scope is ambiguous, ask instead of guessing.
- When choosing between options, prefer the one that leaves the code most correct and pure over the long term, even if it is more work now. Purity means a single source of truth, models that reflect resolved domain decisions rather than raw input, and no latent inconsistencies left behind.

## Assistant Style

- Be realistic, objective, direct, and outcome-oriented.
- Challenge weak assumptions, vague goals, procrastination, unnecessary complexity, and risky plans.
- Prefer truth, clarity, concrete action, real trade-offs, and simple sufficient solutions over temporary reassurance.

## Shared And Mobile Contexts

- In shared or group channels, participate only when directly useful. Do not dominate conversations or act as Andy's proxy.
- Do not expose private context, local paths, secrets, personal memory, or assumptions about Andy unless he clearly made them part of that conversation.
- Ask before sending emails, public posts, messages as Andy, or anything else that leaves the machine in a way he did not request.

---

## When Unsure, ALWAYS ASK

If you are unsure about anything that affects the outcome, ask before proceeding. This includes:

- Ambiguous scope ("does the user want X or Y?")
- Conflict resolution strategy (which side of a merge/revert conflict to take, how to resolve a stacked-PR conflict, what to do with generated code)
- Whether to touch generated/derived artifacts (proto-generated `.pb.go`, ORM-generated `.go`/`.sql`, lockfiles, `ddl.sql`, etc.) manually
- Which environment(s) a destructive operation should target (staging vs sandbox vs prod, dev vs staging databases)
- Whether to combine multiple logical changes into one PR or split them
- Naming choices that will be hard to change later (branch names, file paths, public API surface)
- Anything that requires guessing the user's intent beyond what they explicitly stated

Never silently pick a path when multiple paths are reasonable. Surface options, recommend one if possible, and wait.

---

## Git Conventions

**Conventional Commits:** `<type>[scope]: <description>`

Types: `feat fix docs style refactor perf test build ci chore revert`

Imperative mood, lowercase, no period, ~50 chars.

**Never add `Co-Authored-By:` trailers to commit messages.** Not for Claude, not for any agent.

**Never mention that an agent or AI worked on anything** — not in commit messages, not in PR titles, not in PR bodies, not in code comments. No `🤖`, no "Generated with Claude Code", no attribution of any kind.

When the user says **"new rule"**, add the rule to the appropriate `AGENTS.md`.

**Amending pushed commits is OK** — including amending into the previous commit on a pushed branch when the change is a logical extension of that commit (e.g. forgotten field, missed caller, follow-up to a self-authored commit, fixing your own mistake in the same PR before review starts). This overrides any default agent-framework guidance that forbids amending pushed commits. The constraint is mechanical, not policy: amending a pushed commit requires `git push --force-with-lease` (never bare `--force`). For unrelated logic changes, or when other people have already pulled the branch, create a new commit instead. Never amend a commit authored by someone else.

---

## Code Quality

**Comments explain WHY, not WHAT.** Skip comments that restate code, variable names, or standard patterns.

**Default to no comment.** Code should be self-explanatory through naming and structure for the most part. Only add a comment when it captures a non-obvious invariant, a business rule that isn't visible in the code, or a genuine gotcha — not to narrate what a field or function already makes clear.

---

## Go Style

- Follow [Uber Go Style Guide](https://github.com/uber-go/guide/blob/master/style.md) and [Effective Go](https://go.dev/doc/effective_go)
- Never do type casting — implement interfaces properly
- Use `slices.Sort` not `sort.Slice`

## Go Build

- Always run `go mod tidy` before pushing Go repos.
- **Never run multiple `go build` commands in parallel.** Run one at a time and wait for it to finish.
- `GOWORK=off go build ./...` downloads all deps on first run and can take several minutes — this is normal, not a hang. Use a timeout of at least 300000ms (5 min).
- Do not retry or spawn a second build while one is in progress.

---

## RTK Wrapper

`rtk` is a CLI proxy that filters and compresses command output before it reaches LLM context — stripping noise, deduplicating, and summarizing to save tokens.

**Automatic rewriting:** supported when the harness has a hook to rewrite shell commands before execution (OpenCode does via a plugin). If the harness doesn't support this, call `rtk` explicitly.

**When calling `rtk` directly** (e.g. `rtk grep`): each subcommand has its own flags that differ from the native tool's. Run `rtk <subcommand> --help` to see available flags — do not pass native flags blindly.

Key behaviors: `rtk test` is silent on success; if `rtk` fails, run the native command; do not retry the same intercepted command hoping for different output.

---

## Dependency Placement

On Nix-managed machines, Nix/Home Manager is the source of truth for packages, system settings, user-level configuration, dotfiles, shell setup, and aliases. Do not install tools or change system/user configuration outside Nix/Home Manager unless the user explicitly approves an exception.

- Package installs: use Nix, Home Manager, nix-darwin, or project/workspace dev shells. Do not use Homebrew, global npm, global Go installs, Cargo installs, pip, pipx, uv tool installs, or ad-hoc curl installers on Nix-managed machines unless explicitly approved.
- System/user configuration: manage macOS settings, shell configuration, editor/tool configuration, dotfiles, environment variables, and aliases through the Nix/Home Manager configuration whenever practical.
- Agent harness assets: manage shared policy, commands, skills, agents, plugins, and stable harness config from `my-setup/shared`, not by editing generated harness directories.
- Shell aliases and zsh setup: put them in Home Manager, usually `programs.zsh.shellAliases` or `programs.zsh.initContent`; do not manually edit generated files such as `~/.zshrc`.
- Package-manager shims such as `npx` or `uvx` are acceptable only when the runtime is provided by Nix and the invoked package/version is pinned or intentionally documented.
- Keep secrets out of Nix/Git unless encrypted. Manage non-secret pointers/config through Nix/Home Manager when practical.
- If a tool or configuration is missing from nixpkgs/Home Manager/nix-darwin, treat that as a Nix packaging/module task, a project/workspace dev-shell task, a replacement decision, or an explicit user-approved exception.

Outside Nix-managed machines: use `uv tool` for Python CLI apps, never `pipx` or global `pip`; use project-local `uv` for project deps.

Nix/Home Manager ownership does **not** mean every discovered tool becomes a global Home Manager package.

- Global Nix/Home Manager: only baseline tools used everywhere, such as shell, editor, git, navigation, and universal debugging utilities.
- Project Nix/dev shells: runtimes, compilers, linters, code generators, test tools, and CLIs tied to one repo or stack. Load them with `direnv` from the project's `flake.nix`.
- Workspace Nix/dev shells: tools shared by a family of repos, such as cloud, Kubernetes, database, or vendor CLIs.
- Do not migrate old global installs from Brew, npm, Go, Cargo, uv, pip, or pipx into global Nix by default. First classify whether each tool is truly global, project-specific, workspace-specific, packageable, replaceable, or should be dropped.
- No Homebrew exception for this policy: if a tool is needed and not in nixpkgs, make it a Nix packaging task, project package, workspace package, replacement decision, or explicit drop.
