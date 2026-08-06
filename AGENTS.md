# Repository Guidelines

## Scope

These instructions apply to this entire `my-setup` configuration repository.

## Source Of Truth

- Nix and Home Manager are the only source of truth for packages, user configuration, system configuration, dotfiles, shell aliases, and machine-specific config.
- Make durable machine configuration changes through the relevant machine flake, not by editing generated files or installing tools out of band.
- Shared agentic harness assets live under `shared/` in this repo.
- Mac-specific agent overlays live under `personal-mac/`; MediDrive Linux overlays live under `medidrive-linux/`.
- Do not edit generated targets such as `~/.config/opencode/` directly when the source exists in this repo.
- Keep secrets out of this repository.

## Common Commands

- Bootstrap the Mac: `make -C personal-mac bootstrap`
- Apply the Mac config: `make -C personal-mac switch`
- Apply the MediDrive VM config: `make -C medidrive-linux switch`
- Run Mac health checks: `make -C personal-mac audit`
- Run MediDrive health checks: `make -C medidrive-linux audit`
- Validate a machine flake: `make -C personal-mac check` or `make -C medidrive-linux check`
- Apply Mac system and Home Manager changes: `darwin-rebuild switch --flake ~/my-setup/personal-mac`
- Update inputs: `nix flake update --flake personal-mac` or `nix flake update --flake medidrive-linux`

## Privileged Commands

- Do not run privileged repo commands, including `make switch`, plainly first and then retry with sudo/root after they fail.
- For `darwin-rebuild switch` or `make switch`, do not use `osascript ... with administrator privileges`; that can run outside the user's Aqua session and hit macOS TCC/App Management errors while updating `/Applications/Nix Apps/*.app`.
- Use `sudo -A` with the managed GUI askpass helper from the current terminal process:
  `DR=$(command -v darwin-rebuild); SUDO_ASKPASS=/Users/andytoma/.local/bin/opencode-askpass sudo -A "$DR" switch --flake path:/Users/andytoma/my-setup/personal-mac`
- If the managed helper is not available yet, create `/var/folders/6t/kf485w6x5n1_n28tsq6_12sw0000gn/T/my-setup-askpass.sh` with a `System Events` hidden-password dialog as a bootstrap helper, then `chmod +x` it and use that path for the first switch.
- To verify the privileged command is still in the Aqua session, run `SUDO_ASKPASS=... sudo -A launchctl managername`; it should print `Aqua`, not `System`.

## Editing Rules

- Prefer small, direct changes in `personal-mac/flake.nix` or `medidrive-linux/flake.nix` over adding new files or abstractions.
- Put globally useful CLI tools in `userPackagesFromNixpkgs`; put GUI/system apps in `systemPackagesFromNixpkgs`.
- Put project-specific runtimes, linters, code generators, and test tools in project/workspace flakes or dev shells instead of global packages.
- Add custom package derivations near the existing local package definitions, then include them through `userPackages` or `systemPackages`.
- When changing published harness files, update the source under `shared/`, `personal-mac/`, or `medidrive-linux/`, not the linked or rsynced destination.
- Do not manually edit `flake.lock` unless updating inputs intentionally.


