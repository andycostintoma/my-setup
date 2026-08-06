# opencode shared setup

Portable OpenCode wiring shared by consuming setup repos. Machine-specific OpenCode docs, plugins, skills, launchd/systemd services, paths, and secrets belong in the consuming setup repo overlay.

## Key Paths

- Global config: `~/.config/opencode/opencode.json`
- Global policy: `~/.config/opencode/AGENTS.md`
- Docs: `~/.config/opencode/docs/`
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
| `opencode-claude-auth@latest` | Claude subscription OAuth provider; reads tokens from macOS Keychain on macOS or `~/.claude/.credentials.json` on Linux |
| `./plugins/sound-notify.ts` | audible cue on permission/question events and when a busy session goes idle |

### sound-notify

Plays `afplay /System/Library/Sounds/Glass.aiff` on macOS by default; elsewhere it falls back to the terminal bell. Override with `OPENCODE_NOTIFY_SOUND_COMMAND` (the MediDrive VM points it at a curl through the SSH reverse tunnel so the Mac plays the sound).

## rtk

CLI proxy that strips noise, deduplicates, and summarizes shell output before it reaches LLM context. Wired in via the `openrtk` plugin, which wraps bash tool execution. Source of truth for rewrite rules: `rtk rewrite` (Rust binary).

- `rtk test` is silent on success; output only on failure.
- Calling `rtk` directly: each subcommand has its own flags. Run `rtk <subcommand> --help` — don't pass native tool flags blindly.
- If a command fails through `rtk`, run the native command directly.
- Don't retry the same command hoping for different output — the rewrite is deterministic.

## DCP (Dynamic Context Pruning)

`@tarquinen/opencode-dcp` exposes the `compress` tool the model invokes to surgically compress *closed* sections of the conversation mid-session (plus deduplication of repeated tool calls and error-input purging). Session history is never destroyed — pruned content is replaced with placeholders before being sent to the LLM.

Not redundant with opencode's built-in `compaction`: built-in compaction is coarse, automatic, whole-session (fires when the context window fills — a safety net); DCP is fine-grained, model-driven, surgical (compresses specific stale spans early — finer control and earlier token savings). They coexist. Pruning slightly lowers prompt-cache hit rate (~5%), usually a net win on long sessions. Config lives in `dcp.jsonc` at the opencode config root (currently all defaults).

## Quick Checklist

- Config valid: `opencode --version` errors if `opencode.json` is malformed.
- rtk available: `rtk --version` (need >= 0.23.0)
- Playwright MCP: `npx` must be on PATH. On Nix-managed machines this comes from Nix-managed `nodejs`, not a global npm install.
- Regenerate auto-router agents after editing `scripts/agent-ladder.config.json` or `scripts/generate-agent-ladder.ts`: `node --experimental-strip-types scripts/generate-agent-ladder.ts`
