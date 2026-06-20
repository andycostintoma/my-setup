---
description: Refresh OpenCode models, pick top free models, and update favorites
---

Invoke the `update-models` skill before doing anything else.

If arguments were provided after `/update-models`, pass them through (e.g. a
specific provider to focus on, or a request to only re-rank without writing).
If no arguments were provided, run the full refresh-research-validate-write
workflow and set OpenCode favorites to exactly 7 entries.
