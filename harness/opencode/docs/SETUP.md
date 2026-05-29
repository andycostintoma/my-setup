# opencode local setup

opencode-specific wiring on this machine. For the harness-agnostic stack (OpenViking, rtk), see `../LOCAL-STACK.md`.

## Key paths

- Global config: `~/.config/opencode/opencode.json`
- Docs: `~/.config/opencode/docs/`
- Services: `~/.config/opencode/services/`
- Plugins: `~/.config/opencode/plugins/` (activation-copied by Home Manager from `harness/opencode/plugins/`)
- Skills: `~/.config/opencode/skills/` (managed by Home Manager from shared skills in `~/.config/my-setup/harness/shared/skills/`)
- Commands: `~/.config/opencode/commands/` (managed by Home Manager from `~/.config/my-setup/harness/shared/commands/`)
- Agents: `~/.config/opencode/agents/` (managed by Home Manager from shared agents in `harness/shared/agents/` plus opencode-specific agents in `harness/opencode/agents/`)
- Mobile web password: `~/.secrets/opencode/web-password` (generated locally by Home Manager if missing)
- Mobile web logs: `~/Library/Logs/opencode-web.log`, `~/Library/Logs/opencode-web.error.log`
- Kimaki data: `~/.kimaki/` (`discord-sessions.db` plus Kimaki's own `kimaki.log`)
- Kimaki launchd logs: `~/Library/Logs/kimaki.log`, `~/Library/Logs/kimaki.error.log`

## Mobile web access

Home Manager installs a `launchd` user agent named `opencode-web` that runs:

```sh
opencode web --port 4096 --hostname 0.0.0.0 --mdns --mdns-domain opencode.local
```

The service is protected by HTTP basic auth:

- Username: `opencode`
- Password: contents of `~/.secrets/opencode/web-password`

Recommended iPhone access is through Tailscale, then open:

```text
http://<mac-tailscale-ip>:4096
```

Do not expose this port directly to the public internet.

## Native-ish iPhone access with Kimaki

Kimaki is the primary mobile interface for OpenCode on this machine. It lets the Discord iOS app control OpenCode sessions: projects are Discord channels and sessions are Discord threads.

Nix installs a pinned `kimaki` wrapper. It uses Nix-provided Node/npm/Bun tooling and does not install Kimaki globally with npm.

First-time setup is interactive:

```sh
kimaki --data-dir ~/.kimaki
```

Recommended setup choices:

- Use a self-hosted Discord bot for this machine. Gateway mode was blocked by Discord's unverified bot limit during setup.
- Create a dedicated Discord server for coding agents.
- Add the `Kimaki` role only to trusted users.
- Add this my-setup repository as one project so it gets its own Discord channel.

Home Manager also installs a `launchd` user agent named `kimaki`. The agent runs `~/.local/bin/kimaki-server` at login, but exits cleanly until `~/.kimaki/discord-sessions.db` exists. After the interactive setup creates that database, reload the service or log out/in:

```sh
launchctl kickstart -k gui/$(id -u)/org.nix-community.home.kimaki
```

Useful commands:

```sh
kimaki project add ~/.config/my-setup
kimaki send --channel <discord-channel-id> --prompt 'Review current git status and summarize risks'
```

## Plugins

Enabled plugins are configured in `opencode.json` under `plugin`. Local implementations are activation-copied files in `~/.config/opencode/plugins/`; OpenViking plugin state lives in `~/.local/state/opencode/openviking/`. These are copied instead of per-file symlinked because opencode resolves TypeScript plugins by real path, and symlinks break relative imports and `node_modules` lookup.

| Plugin | Purpose |
|---|---|
| `./plugins/openviking/context.ts` | injects indexed OpenViking repositories into the system prompt |
| `openrtk` | wraps bash tool execution to run `rtk rewrite` |
| `@tarquinen/opencode-dcp@latest` | provides the `compress` tool |
| `./plugins/openviking/memory.ts` | captures opencode sessions, exposes OpenViking memory tools, and auto-commits extracted memories |
| `./plugins/automation/auto-recall.ts` | injects relevant OpenViking memories into the system prompt |
| `./plugins/automation/auto-explore.ts` | auto-spawns the `explore` subagent on search/discovery prompts |
| `./plugins/automation/sound-notify.ts` | plays Glass.aiff on permission/question events |
| `./plugins/claude-auth/plugin.ts` | Claude subscription OAuth provider; reads tokens from macOS Keychain (Mac) or `~/.claude/.credentials.json` (Linux) so Anthropic requests use Claude Max OAuth instead of the static API key in `auth.json`. Required for Opus access on MediDrive accounts where the workspace API key has no Opus quota. |

## Services

Home Manager installs a `launchd` user agent named `ollama-opencode-proxy` that runs:

```sh
node --experimental-strip-types ~/.config/opencode/services/ollama-proxy.ts
```

It serves an OpenAI-compatible proxy on `127.0.0.1:11435` and forwards to Ollama at `127.0.0.1:11434`.

### auto-explore

- Source: `~/.config/opencode/plugins/automation/auto-explore.ts`
- Enabled by default. Disable: `export OPENCODE_AUTO_EXPLORE=0`
- Triggers via regex on the user prompt (search/discovery intent).

### auto-recall

- Scopes to `preferences` + `entities` only (see `../LOCAL-STACK.md`). Skips `events/`.
- Score threshold 0.55, max 3 hits, decision cached per session.

### openviking-memory

- Source: `~/.config/opencode/plugins/openviking/memory.ts`
- Enabled by default in `opencode.json`.
- Captures opencode session messages, exposes `memread`/`membrowse`/`memsearch`/`memcommit`, and auto-commits extracted memories every 10 minutes by default.
- State/logs: `~/.local/state/opencode/openviking/`
- Config: `~/.config/opencode/plugins/openviking/config.json`
- Override state location with `OPENCODE_OPENVIKING_DATA_DIR` if needed.

### sound-notify

- Source: `~/.config/opencode/plugins/automation/sound-notify.ts`
- Enabled by default.
- Plays the macOS Glass sound when opencode asks a question or permission prompt.

## Quick checklist (opencode-specific)

- Config valid: `opencode --version` (errors if `opencode.json` is malformed)
- Playwright MCP: `npx` must be on PATH. On Nix-managed machines this comes from Nix-managed `nodejs`, not a global npm install.
- Regenerate auto-router agents after editing `agent-ladder.config.json` or `scripts/generate-agent-ladder.ts`: `node --experimental-strip-types scripts/generate-agent-ladder.ts`

For shared stack health checks (OpenViking, rtk), see `../LOCAL-STACK.md`.
