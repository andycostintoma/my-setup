# Repository Guidelines

Applies to the `medidrive-linux/` VM subtree. The root `my-setup/AGENTS.md` rules apply here too;
only the VM-specific deltas are listed below.

## Common Commands

Run from this directory: `make fmt`, `make check`, `make switch`, `make audit`.

## Editing Rules

- Keep only VM/MediDrive-specific agent overlays in this subtree, for example `harness/medidrive/`.
- Put VM-only Home Manager config in `modules/home.nix`; shared agentic packages belong in `shared/modules/packages.nix`.
