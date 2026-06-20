---
description: Prune PLAN.md, slim AGENTS.md, review skills and commands
---
Run a documentation cleanup.

Step 1: Reflect on the current session
- What new patterns, conventions, or gotchas were discovered?
- Any architectural decisions not yet in AGENTS.md?
- Add genuinely new permanent knowledge to AGENTS.md. Skip if nothing new.

Step 2: Check AGENTS.md for stale guidance AND slim it down
- Skim for anything now wrong or outdated (removed files, changed commands, deprecated patterns)
- Delete or correct stale entries
- If execution details crept back in, move them to the appropriate skill or command
- Look for opportunities to reduce verbosity without losing information:
  - Collapse repetitive examples into one example per pattern
  - Remove "Why it's wrong" explanations when the contrast is self-evident
  - Merge sections that cover the same concept
  - Replace prose with tables or bullet lists where denser format works
  - If a section's only purpose is "see X for details", inline the one-liner or delete it
- Check for duplication with the global AGENTS.md — anything already covered globally should NOT be in the project file

Step 3: Clean up PLAN.md (only if the project uses one — skip if absent)
- Delete completed work — move to git history, not "Current Status"
- Remove resolved open questions — just delete, don't keep as "RESOLVED"
  - Exception: if a resolved question's decision informs future implementation, keep as concise "Decision Taken"
- Delete implementation narratives
- Keep only: blockers, open questions, incomplete work, relevant "Decisions Taken"

Step 4: Review README.md (if the project has one)
- Verify build/run/test commands still match Makefile targets
- Update project structure if directories changed
- Check env vars and defaults are current

Step 5: Review test guidelines (if the project has them)
- Update if new test patterns emerged

Step 6: Review skills
- Check each skill against current codebase reality (file paths, function names, patterns)
- Update stale references
- Add new skills if recurring workflows emerged that aren't covered
- Remove skills that no longer apply

Step 7: Review commands
- Check each command still matches how audits are actually run
- Update stale file paths or tool references
- Ensure commands are self-contained

Target: PLAN.md (if used) < 300 lines. AGENTS.md as slim as possible without losing context. All docs, skills, and commands reflect current state.

This command is **inward-looking**: it prunes drift and staleness in what already
exists. For **outward-looking** improvement — researching new agent-tooling
trends and proposing adoptions — use `/power-setup`.
