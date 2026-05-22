---
description: Refresh OpenViking indexes for workspace repos
---
Refresh OpenViking indexes for the current workspace and its related repos.

Arguments: `$ARGUMENTS`

Rules:
- If no arguments provided, reindex the current workspace repo only.
- If arguments are bare repo names (e.g., `nemt-proto`), look for them as siblings of the workspace root.
- If arguments are absolute paths, use them directly.
- Multiple repos may be provided, space-separated.
- If the argument is `--watch`, set up auto-resync instead of one-shot reindex.

For each target repo:
1. Verify the local path exists. Skip if not found.
2. Remove existing index: `ov rm viking://resources/<repo-name> --recursive`
3. Re-add with context:
   ```
   ov add-resource <local-path> --to viking://resources/<repo-name> \
     --exclude "go.mod,go.sum,buf.lock,go.work,go.work.sum,*.pb.go" \
     --reason "<brief description of what this repo is>" \
     --timeout 300 --wait
   ```
4. If `--watch` was specified, add `--watch-interval 30` to auto-resync every 30 minutes.
5. Report success or failure.

Use `--reason` to improve search relevance — describe the repo's role briefly (e.g., "proto definitions for all NEMT services").

Do not delete unrelated resources outside the target set.
Do not commit.
