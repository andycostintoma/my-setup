# TOOLS.md - Local Notes

Skills define how tools work. This file is for stable local conventions that should be managed from Nix.

## Nix Rule

Durable tool, skill, command, package, or assistant configuration changes go through `/Users/andytoma/.config/nix-darwin`.

Do not install global tools with Homebrew, npm, Go, Cargo, pip, pipx, uv tools, or curl installers unless Andy explicitly approves an exception.

## OpenClaw

- Config source: `harness/openclaw/openclaw.json`
- Workspace source: `harness/openclaw/workspace/`
- Shared skills source: `harness/shared/skills/`
- Runtime config target: `~/.openclaw/openclaw.json`
- Runtime managed skills target: `~/.openclaw/skills`

## Runtime State

These are intentionally not Nix-managed because they must remain writable or secret:

- `~/.openclaw/MEMORY.md` and `~/.openclaw/workspace/MEMORY.md`
- `~/.openclaw/workspace/memory/`
- `~/.openclaw/credentials/`
- `~/.openclaw/devices/`
- `~/.openclaw/logs/`
- `~/.openclaw/tasks/`
- `~/.openclaw/telegram/`
- `~/.secrets/openclaw/`
