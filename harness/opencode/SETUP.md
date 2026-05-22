# opencode local setup

opencode-specific wiring on this machine. For the harness-agnostic stack (OpenViking, rtk), see `LOCAL-STACK.md`.

## Key paths

- Global config: `~/.config/opencode/opencode.json`
- Plugins: `~/.config/opencode/plugins/`
- Skills: `~/.config/opencode/skills/` (managed by Home Manager from `~/.config/nix-darwin/harness/opencode/skills/`)
- Commands: `~/.config/opencode/commands/` (managed by Home Manager from `~/.config/nix-darwin/harness/shared/commands/`)
- Agents: `~/.config/opencode/agents/` (managed by Home Manager from `~/.config/nix-darwin/harness/opencode/agents/`)

## Plugins

Configured in `opencode.json` under `plugin`. Implementations in `~/.config/opencode/plugins/`.

| Plugin | Purpose |
|---|---|
| `openviking-opencode` | OpenViking integration |
| `openrtk` | wraps bash tool execution to run `rtk rewrite` |
| `@tarquinen/opencode-dcp@latest` | provides the `compress` tool |
| `./plugins/auto-recall.ts` | injects relevant OpenViking memories into the system prompt |
| `./plugins/auto-explore.ts` | auto-spawns the `explore` subagent on search/discovery prompts |
| `./plugins/sound-notify.ts` | Glass.aiff on permission/question events |
| `./plugins/claude-auth.ts` | Claude subscription OAuth provider (vendored) |

### auto-explore

- Source: `~/.config/opencode/plugins/auto-explore.ts`
- Enabled by default. Disable: `export OPENCODE_AUTO_EXPLORE=0`
- Triggers via regex on the user prompt (search/discovery intent).

### auto-recall

- Scopes to `preferences` + `entities` only (see LOCAL-STACK.md). Skips `events/`.
- Score threshold 0.55, max 3 hits, decision cached per session.

## Quick checklist (opencode-specific)

- Config valid: `opencode --version` (errors if `opencode.json` is malformed)
- Playwright MCP: `npx` must be on PATH. On Nix-managed machines this comes from Nix-managed `nodejs`, not a global npm install.
- Regenerate auto-router agents after editing `agent-ladder.config.json` or `scripts/generate-agent-ladder.mjs`: `node scripts/generate-agent-ladder.mjs`

For shared stack health checks (OpenViking, rtk), see LOCAL-STACK.md.
