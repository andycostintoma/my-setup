# opencode shared setup

Portable OpenCode wiring shared by consuming setup repos. Machine-specific OpenCode docs, plugins, skills, launchd/systemd services, paths, and secrets belong in the consuming setup repo overlay.

For the harness-agnostic local stack, see `../LOCAL-STACK.md`.

## Key Paths

- Global config: `~/.config/opencode/opencode.json`
- Global policy: `~/.config/opencode/AGENTS.md`
- Docs: `~/.config/opencode/docs/`
- Services: `~/.config/opencode/services/`
- Plugins: `~/.config/opencode/plugins/` copied by Home Manager from `harness/opencode/plugins/` plus optional machine overlays
- Skills: `~/.config/opencode/skills/` merged by Home Manager from `harness/shared/skills/` plus optional machine overlays
- Commands: `~/.config/opencode/commands/` managed by Home Manager from `harness/shared/commands/`
- Agents: `~/.config/opencode/agents/` merged by Home Manager from optional shared agents and OpenCode-specific agents

## Plugins

Enabled plugins are configured in `opencode.json` under `plugin`. TypeScript plugin implementations are activation-copied into `~/.config/opencode/plugins/` instead of per-file symlinked because opencode resolves plugins by real path, and symlinks break relative imports and `node_modules` lookup.

| Plugin | Purpose |
|---|---|
| `openrtk` | wraps bash tool execution to run `rtk rewrite` |
| `@tarquinen/opencode-dcp@latest` | provides the `compress` tool |
| `./plugins/openviking/memory.ts` | captures opencode sessions, exposes OpenViking memory tools, and auto-commits extracted memories |
| `./plugins/automation/context-broker.ts` | performs compact high-confidence OpenViking/graphify retrieval and graphify maintenance without prompt-routing noise |
| `opencode-claude-auth@latest` | Claude subscription OAuth provider; reads tokens from macOS Keychain on macOS or `~/.claude/.credentials.json` on Linux |

## Services

`harness/opencode/services/ollama-proxy.ts` is a portable OpenAI-compatible proxy implementation. Consuming setup repos decide whether to run it through launchd, systemd, or another supervisor.

## Plugin Notes

### openviking-memory

- Source: `~/.config/opencode/plugins/openviking/memory.ts`
- Enabled by default in `opencode.json`.
- Captures opencode session messages, exposes `memread`, `membrowse`, `memsearch`, and `memcommit`, and auto-commits extracted memories every 10 minutes by default.
- State/logs: `~/.local/state/opencode/openviking/`
- Config: `~/.config/opencode/plugins/openviking/config.json`
- Override state location with `OPENCODE_OPENVIKING_DATA_DIR` if needed.

### context-broker

- Source: `~/.config/opencode/plugins/automation/context-broker.ts`
- Config: `~/.config/opencode/context-broker.json`
- Logs/state: `~/.local/state/opencode/context-broker/`
- Shared defaults are conservative: OpenViking reads are high-threshold, graphify updates existing graphs, and graphify auto-init is disabled unless a consuming setup repo configures trusted roots.
- Injects only compact turn-scoped results under `## Retrieved Context`; never injects indexed repo lists, generic routing instructions, or failed status reports.

## Quick Checklist

- Config valid: `opencode --version` errors if `opencode.json` is malformed.
- Playwright MCP: `npx` must be on PATH. On Nix-managed machines this comes from Nix-managed `nodejs`, not a global npm install.
- Regenerate auto-router agents after editing `scripts/agent-ladder.config.json` or `scripts/generate-agent-ladder.ts`: `node --experimental-strip-types scripts/generate-agent-ladder.ts`

For shared stack health checks such as OpenViking and rtk, see `../LOCAL-STACK.md`.
