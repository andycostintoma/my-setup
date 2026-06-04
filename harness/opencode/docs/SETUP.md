# opencode local setup

This file documents macOS-only OpenCode wiring for `my-setup`. Shared OpenCode, OpenViking, Graphify, and rtk setup lives in `~/.config/agentic-setup`.

## Key Paths

- Global config: `~/.config/opencode/opencode.json`
- Docs: `~/.config/opencode/docs/`
- Services: `~/.config/opencode/services/`
- Plugins: `~/.config/opencode/plugins/`
- Local-only plugin source: `~/.config/my-setup/harness/opencode/plugins/`
- Local-only skill source: `~/.config/my-setup/harness/shared/skills/`
- Mobile web password: `~/.secrets/opencode/web-password` generated locally by Home Manager if missing
- Mobile web logs: `~/Library/Logs/opencode-web.log`, `~/Library/Logs/opencode-web.error.log`
- Kimaki data: `~/.kimaki/`
- Kimaki launchd logs: `~/Library/Logs/kimaki.log`, `~/Library/Logs/kimaki.error.log`

## Mobile Web Access

Home Manager installs a disabled-by-default `launchd` user agent named `opencode-web` that runs:

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

## Native-ish iPhone Access With Kimaki

Kimaki is local-only to this Mac. It lets the Discord iOS app control OpenCode sessions: projects are Discord channels and sessions are Discord threads.

Nix installs a pinned `kimaki` wrapper. It uses Nix-provided Node/npm/Bun tooling and does not install Kimaki globally with npm.

First-time setup is interactive:

```sh
kimaki --data-dir ~/.kimaki
```

Recommended setup choices:

- Use a self-hosted Discord bot for this machine.
- Create a dedicated Discord server for coding agents.
- Add the `Kimaki` role only to trusted users.
- Add this `my-setup` repository as one project so it gets its own Discord channel.

Home Manager installs a `launchd` user agent named `kimaki`. The agent runs `~/.local/bin/kimaki-server` at login, but exits cleanly until `~/.kimaki/discord-sessions.db` exists. After interactive setup creates that database, reload the service or log out/in:

```sh
launchctl kickstart -k gui/$(id -u)/org.nix-community.home.kimaki
```

Useful commands:

```sh
kimaki project add ~/.config/my-setup
kimaki send --channel <discord-channel-id> --prompt 'Review current git status and summarize risks'
```

## Local Plugins

`my-setup` overlays the following local-only OpenCode plugin:

| Plugin | Purpose |
|---|---|
| `./plugins/automation/sound-notify.ts` | plays the macOS Glass sound on permission/question events and when a busy session becomes idle |

### sound-notify

- Source: `~/.config/my-setup/harness/opencode/plugins/automation/sound-notify.ts`
- Runtime copy: `~/.config/opencode/plugins/automation/sound-notify.ts`
- Enabled from `modules/opencode.local.json`.
- Override the command with `OPENCODE_NOTIFY_SOUND_COMMAND`.

## Local Services

Home Manager installs a `launchd` user agent named `ollama-opencode-proxy` that runs:

```sh
node --experimental-strip-types ~/.config/opencode/services/ollama-proxy.ts
```

It serves an OpenAI-compatible proxy on `127.0.0.1:11435` and forwards to Ollama at `127.0.0.1:11434`.
