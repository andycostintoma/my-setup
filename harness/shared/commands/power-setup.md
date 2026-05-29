---
description: Research the latest AI-agent tooling trends and propose adoptions for this harness
---
Keep this agent harness current with the evolving AI-coding-agent ecosystem.
This command is **outward-looking**: research what's new and good in the wider
landscape, then propose concrete adoptions for this repo. For inward-looking
drift cleanup (pruning PLAN.md, destaling AGENTS.md, fixing stale references),
use `/update-docs` instead.

Step 1: Research the current landscape (the main job)
- Read the docs/changelog for the current agent tool (OpenCode and any other
  active harness): new skills/commands/permissions/config options, custom tools,
  MCP servers, agents, plugins, hooks, formatters, LSP integration.
- Look beyond what we already use: emerging patterns, new community plugins/MCP
  servers, prompting/agent techniques, and capabilities released since the last
  run. Prefer official docs, release notes, and reputable recent sources.
- Note version-gated features (what requires upgrading the tool).

Step 2: Map findings against our current setup
- Briefly check what we already have (skills, commands, agents, plugins, MCP,
  permissions) so proposals are net-new, not duplicates.
- Identify gaps where a new capability would clearly help our workflows.

Step 3: Propose adoptions
- New skills/commands/agents/plugins/MCP servers worth adopting, each with a
  concrete reason tied to how we actually work.
- Config or permission options newly available that we should turn on.
- Anything we use that is now superseded by a better built-in or community option.
- For each proposal: what to add/change, where (exact file), and the expected
  benefit. Flag anything that requires upgrading the tool.

Rules:
- Do NOT make changes — only propose. Present findings and wait for approval.
- Be specific: exact file, exact change proposed, exact source for each trend.
- Hand off pure staleness/drift fixes to `/update-docs` rather than doing them here.
