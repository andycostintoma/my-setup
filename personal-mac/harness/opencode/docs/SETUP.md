# opencode local setup

This file documents macOS-only OpenCode wiring for `my-setup`. Shared OpenCode, OpenViking, Graphify, and rtk setup lives under `shared/` in this repo.

## Key Paths

- Global config: `~/.config/opencode/opencode.json`
- Docs: `~/.config/opencode/docs/`
- Services: `~/.config/opencode/services/`
- Plugins: `~/.config/opencode/plugins/`
- Local-only plugin source: `~/my-setup/personal-mac/harness/opencode/plugins/`
- Local-only skill source: `~/my-setup/personal-mac/harness/shared/skills/`
- Mobile web password: `~/.secrets/opencode/web-password` generated locally by Home Manager if missing
- Mobile web logs: `~/Library/Logs/opencode-web.log`, `~/Library/Logs/opencode-web.error.log`

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

## Local Plugins

`my-setup` overlays the following local-only OpenCode plugin:

| Plugin | Purpose |
|---|---|
| `./plugins/automation/sound-notify.ts` | plays the macOS Glass sound on permission/question events and when a busy session becomes idle |

### sound-notify

- Source: `~/my-setup/personal-mac/harness/opencode/plugins/automation/sound-notify.ts`
- Runtime copy: `~/.config/opencode/plugins/automation/sound-notify.ts`
- Disabled by default in `modules/opencode.local.json`.
- `opencode` is routed through `~/.local/bin/opencode`, which applies the persisted toggle before launching the packaged binary.
- Use `opencode-sound-notify-enable` to enable the plugin for future `opencode` sessions.
- Use `opencode-sound-notify-disable` to disable it again for future `opencode` sessions.
- Override the command with `OPENCODE_NOTIFY_SOUND_COMMAND`.
