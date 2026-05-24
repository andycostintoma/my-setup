# Repository Guidelines

## Scope

These instructions apply to this entire `nix-darwin` configuration repository.

## Source Of Truth

- Nix and Home Manager are the only source of truth for packages, user configuration, system configuration, dotfiles, shell aliases, and agent harness assets.
- Make durable machine configuration changes through this flake, not by editing generated files or installing tools out of band.
- Keep stable shared agent policy in `harness/shared/AGENTS.md`.
- Put assets shared across active agent harnesses under `harness/shared/`; keep only harness-specific assets under each `harness/<name>/` directory.
- Do not edit generated targets such as `~/.config/opencode/` directly when the source exists under `harness/`.
- Do not use Homebrew, global npm installs, global Go installs, Cargo installs, pip, pipx, uv tool installs, or ad-hoc curl installers unless the user explicitly approves an exception.
- OpenViking is the current explicit shim exception: Nix provides `uv`/`uvx`, and `flake.nix` pins the OpenViking version invoked by the wrapper.
- Keep secrets out of this repository. Local OpenViking secrets belong in `~/.openviking/ov.conf`.

## Common Commands

- Bootstrap a new machine: `make bootstrap`
- Apply the config: `make switch`
- Run local health checks: `make audit`
- Validate the flake: `nix flake check`
- Apply system and Home Manager changes: `darwin-rebuild switch --flake ~/.config/nix-darwin`
- Update inputs: `nix flake update`

## Editing Rules

- Prefer small, direct changes in `flake.nix` over adding new files or abstractions.
- Put globally useful CLI tools in `userPackagesFromNixpkgs`; put GUI/system apps in `systemPackagesFromNixpkgs`.
- Put project-specific runtimes, linters, code generators, and test tools in project/workspace flakes or dev shells instead of global packages.
- Add custom package derivations near the existing local package definitions, then include them through `userPackages` or `systemPackages`.
- When changing published harness files, update the source in `harness/`, not the linked or rsynced destination.
- Do not manually edit `flake.lock` unless updating inputs intentionally.

## Git Rules

- Do not commit, push, or create PRs unless the user explicitly asks.
- Do not revert or discard user changes unless explicitly requested.
- Use Conventional Commits when asked to commit: `<type>[scope]: <description>`.
