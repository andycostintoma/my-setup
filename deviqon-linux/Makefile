SHELL := /bin/bash
.DEFAULT_GOAL := help

NIX_CMD = nix --extra-experimental-features 'nix-command flakes'
NIX_PROFILE ?= /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

include ../shared/make/bootstrap.mk

.PHONY: help bootstrap fmt check switch

help:
	@printf '%s\n' \
		'Available targets:' \
		'  make bootstrap  Install Nix if missing, then apply the flake' \
		'  make fmt     Format Nix files' \
		'  make check   Validate the Deviqon Home Manager output' \
		'  make switch  Apply the Deviqon Home Manager config'

bootstrap: install-nix switch

fmt:
	$(NIX_CMD) run nixpkgs#nixfmt -- flake.nix

check:
	$(NIX_CMD) flake check path:$(CURDIR) --no-write-lock-file
	$(NIX_CMD) eval path:$(CURDIR)#homeConfigurations.deviqon.activationPackage.drvPath --raw >/dev/null

switch:
	@if [ -f '$(NIX_PROFILE)' ]; then . '$(NIX_PROFILE)'; fi; \
	$(NIX_CMD) run path:$(CURDIR)#home-manager -- switch --flake path:$(CURDIR)#deviqon
