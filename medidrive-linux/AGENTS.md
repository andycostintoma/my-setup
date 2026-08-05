# Repository Guidelines

## Scope

These instructions apply to the `medidrive-linux/` VM configuration subtree in `my-setup`.

## Source Of Truth

- Nix and Home Manager are the source of truth for VM packages, shell config, dotfiles, and dev CLI tools.
- Make durable VM changes through this flake, not by editing generated files under `~/.config/opencode/` or installing tools globally.
- Shared agentic harness assets live under `../shared/` in this repo.
- Keep only VM/MediDrive-specific agent overlays in this subtree, for example `harness/medidrive/`.

## Common Commands

- Format Nix files: `make fmt`
- Validate the flake: `make check`
- Apply VM config: `make switch`
- Run local health checks: `make audit`

## Editing Rules

- Prefer small, direct changes in `medidrive-linux/flake.nix` or existing modules.
- Put VM packages in existing package modules; shared agentic packages belong in `shared/modules/packages.nix`.
- Put MediDrive-only Home Manager config in `modules/home.nix` or VM-specific modules.
- When changing shared OpenCode files, update `shared/harness/`; when changing VM-only OpenCode overlays, update `medidrive-linux/harness/medidrive/`.
- Do not manually edit `flake.lock` unless updating inputs intentionally.

## Git Rules

- Do not commit, push, or create PRs unless explicitly requested.
- Do not revert or discard user changes unless explicitly requested.
- Use Conventional Commits when asked to commit: `<type>[scope]: <description>`.
