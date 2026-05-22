---
description: Reconstruct working state after compaction or in a new session
---
Reconstruct the current working state by gathering context from multiple sources. Do this efficiently — use summaries, not full file reads.

1. **Search memories** for recent context (run in parallel with steps 2-3):
   - Use the `memory-recall` skill with query "current project state and recent decisions" to recall cross-session context
   - Use the `memory-recall` skill with query "blockers and open questions" for any persisted blockers

2. **Read PLAN.md** (if it exists) — focus on:
   - Any "In Progress" or "Remaining" sections
   - "Decisions Taken" or similar decision records
   - "Open Questions" or blockers
   - Current execution order / priorities

3. **Check git state:**
   - `git branch --show-current` — what branch are we on?
   - `git status` — any uncommitted changes?
   - `git log --oneline -10` — recent commits
   - `git diff --stat` — what files are modified?

4. **If there are modified files**, briefly scan them to understand what was being worked on.

5. **Summarize** in this format:
   - **Current branch:** ...
   - **Last thing worked on:** ...
   - **Next step:** ...
   - **Key decisions to respect:** (top 3-5)
   - **Uncommitted changes:** (if any)
   - **Blockers/open questions:** (if any)
   - **Relevant memories:** (any cross-session context from memory-recall)

Keep it concise. Use indexing/search tools for cross-repo context if available — do NOT read files in other repos directly.
