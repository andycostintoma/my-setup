NIX_INSTALLER_URL ?= https://install.determinate.systems/nix
NIX_PROFILE ?= /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

.PHONY: install-nix

install-nix:
	@if [ -f '$(NIX_PROFILE)' ]; then . '$(NIX_PROFILE)'; fi; \
	if command -v nix >/dev/null 2>&1; then \
		nix store info >/dev/null; \
		printf '%s\n' 'Nix is installed and its daemon is available.'; \
	elif command -v curl >/dev/null 2>&1; then \
		printf '%s\n' 'Installing Nix with the Determinate Systems installer.'; \
		curl --proto '=https' --tlsv1.2 -sSf -L '$(NIX_INSTALLER_URL)' | sh -s -- install --no-confirm; \
	elif command -v wget >/dev/null 2>&1; then \
		printf '%s\n' 'Installing Nix with the Determinate Systems installer.'; \
		wget -qO- '$(NIX_INSTALLER_URL)' | sh -s -- install --no-confirm; \
	else \
		printf '%s\n' 'A fresh machine must provide curl or wget to install Nix.' >&2; \
		exit 1; \
	fi; \
	if [ -f '$(NIX_PROFILE)' ]; then . '$(NIX_PROFILE)'; fi; \
	command -v nix >/dev/null 2>&1 && nix store info >/dev/null
