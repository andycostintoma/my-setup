.DEFAULT_GOAL := help

EVAL_ATTR = darwinConfigurations.Andys-Mac-mini.config.system.build.toplevel.drvPath

include ../shared/make/common.mk
include ../shared/make/bootstrap.mk

FLAKE_UPDATE_INPUTS = nixpkgs nix-darwin home-manager antigravity-nix nix-homebrew
PIN_UPDATE_PACKAGES = \
	nixpkgs\#go \
	nixpkgs\#nodejs \
	nixpkgs\#p7zip \
	nixpkgs\#xar

.PHONY: help bootstrap install-clt install-nix switch update update-inputs update-pins

help:
	@printf '%s\n' \
		'Available targets:' \
		'  make bootstrap      Install pre-Nix prerequisites, then apply the flake' \
		'  make install-clt    Install Apple Command Line Tools if missing' \
		'  make install-nix    Install Nix if missing' \
		'  make fmt            Format Nix files' \
		'  make check          Validate the Mac flake' \
		'  make switch         Apply system and Home Manager config' \
		'  make update         Update flake inputs, pins, and run audit' \
		'  make update-pins    Update manual package pins and hashes' \
		'  make audit          Run local Nix/OpenCode hygiene checks'

bootstrap: install-clt install-nix switch

install-clt:
	@if xcode-select -p >/dev/null 2>&1; then \
		printf '%s\n' 'Apple Command Line Tools already installed.'; \
	else \
		printf '%s\n' 'Installing Apple Command Line Tools. Complete the macOS prompt, then rerun make bootstrap.'; \
		xcode-select --install; \
		exit 1; \
	fi

switch:
	@if command -v darwin-rebuild >/dev/null 2>&1; then \
		darwin-rebuild switch --flake $(FLAKE_REF) $(FLAKE_ARGS); \
	else \
		if [ -f '$(NIX_PROFILE)' ]; then . '$(NIX_PROFILE)'; fi; \
		$(NIX_CMD) run github:nix-darwin/nix-darwin/master#darwin-rebuild -- switch --flake $(FLAKE_REF) $(FLAKE_ARGS); \
	fi

update: update-inputs update-pins audit

update-inputs:
	@if [ -f '$(NIX_PROFILE)' ]; then . '$(NIX_PROFILE)'; fi; \
	$(NIX_CMD) flake update $(FLAKE_UPDATE_INPUTS) --flake $(FLAKE_REF)

update-pins:
	@if [ -f '$(NIX_PROFILE)' ]; then . '$(NIX_PROFILE)'; fi; \
	$(NIX_CMD) shell $(PIN_UPDATE_PACKAGES) -c go -C $(REPO_ROOT)/shared/tools/setupctl run . update-pins --repo $(FLAKE)
