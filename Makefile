SHELL := /bin/bash

FLAKE ?= $(HOME)/.config/nix-darwin
NIX_INSTALLER_URL ?= https://install.determinate.systems/nix
NIX_PROFILE ?= /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
NIX_CMD = nix --extra-experimental-features 'nix-command flakes'

.PHONY: help bootstrap install-clt install-nix check check-nix switch system-switch home-switch update

help:
	@printf '%s\n' \
		'Available targets:' \
		'  make bootstrap      Install pre-Nix prerequisites, then apply the flake' \
		'  make install-clt    Install Apple Command Line Tools if missing' \
		'  make install-nix    Install Nix if missing' \
		'  make check          Validate the flake' \
		'  make switch         Apply system and Home Manager config' \
		'  make system-switch  Apply nix-darwin system config' \
		'  make home-switch    Apply Home Manager through nix-darwin' \
		'  make update         Update flake inputs'

bootstrap: install-clt install-nix system-switch

install-clt:
	@if xcode-select -p >/dev/null 2>&1; then \
		printf '%s\n' 'Apple Command Line Tools already installed.'; \
	else \
		printf '%s\n' 'Installing Apple Command Line Tools. Complete the macOS prompt, then rerun make bootstrap.'; \
		xcode-select --install; \
	fi

install-nix:
	@if command -v nix >/dev/null 2>&1; then \
		printf '%s\n' 'Nix already installed.'; \
	else \
		printf '%s\n' 'Installing Nix with the Determinate Systems installer.'; \
		curl --proto '=https' --tlsv1.2 -sSf -L $(NIX_INSTALLER_URL) | sh -s -- install; \
	fi

check: check-nix

check-nix:
	@if [ -f '$(NIX_PROFILE)' ]; then . '$(NIX_PROFILE)'; fi; \
	$(NIX_CMD) flake check $(FLAKE)

switch: system-switch

system-switch:
	@if command -v darwin-rebuild >/dev/null 2>&1; then \
		darwin-rebuild switch --flake $(FLAKE); \
	else \
		if [ -f '$(NIX_PROFILE)' ]; then . '$(NIX_PROFILE)'; fi; \
		$(NIX_CMD) run github:nix-darwin/nix-darwin/master#darwin-rebuild -- switch --flake $(FLAKE); \
	fi

home-switch: system-switch

update:
	@if [ -f '$(NIX_PROFILE)' ]; then . '$(NIX_PROFILE)'; fi; \
	$(NIX_CMD) flake update --flake $(FLAKE)
