---
description: Research AI agent best practices and propose improvements to repo setup
---
Research current best practices for AI coding agent configuration, then audit and improve this repo's setup.

Step 1: Research current landscape
- Check docs for the current agent tool (skills, commands, permissions, config, custom tools, MCP servers, agents, plugins)
- Search for emerging patterns beyond what we're using (hooks, formatters, LSP config, etc.)

Step 2: Audit current setup
- Read AGENTS.md — is it focused on stable policy? Any execution details that should be in skills?
- Read each skill — are they self-contained? Do they match current codebase reality?
- Read each command — are they self-contained? Do they have stale references?
- Read agent config — are permissions aligned? Any new config options worth adding?
- Check for content drift between AGENTS.md and skills/commands

Step 3: Propose improvements
- New skills or commands for recurring workflows not yet covered
- Stale content to remove or update
- Better permission rules based on latest docs
- Structural improvements
- Any new agent features worth adopting

Rules:
- Do NOT make changes — only propose. Present findings and wait for approval.
- Be specific: exact file, exact line, exact change proposed.
