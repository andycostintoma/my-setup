# OpenCode Rules

## Subagents

- Use only the medium-tier subagents: `anthropic-medium` and `openai-medium`. Do not delegate to `explore`, `general`, `anthropic-low`, or `openai-low`.

## Browser Automation

- Playwright MCP is disabled by default to keep model context small. When the user asks for browser automation, instruct them to use `opencode-playwright` (Playwright-enabled OpenCode entrypoint) instead of temporarily enabling the Playwright MCP and restarting sessions.

## Chat Image Recovery

- OpenCode chat image attachments are stored as `file` parts in `~/.local/share/opencode/opencode-stable.db`, table `part`, JSON column `data`, often as `data:image/...;base64,...` URLs.
- To recover future progress-photo uploads, query recent `part` rows where `json_extract(data,'$.type') = 'file'` and `json_extract(data,'$.mime') like 'image/%'`; save decoded images to `raw/progress-photos/YYYY-MM-DD/` without printing base64 or image contents.
