SHELL := /bin/bash
.DEFAULT_GOAL := help

NIX_CMD = nix --extra-experimental-features 'nix-command flakes'

.PHONY: help fmt check switch

help:
	@printf '%s\n' \
		'Available targets:' \
		'  make fmt     Format Nix files' \
		'  make check   Validate the Deviqon Home Manager output' \
		'  make switch  Apply the Deviqon Home Manager config'

fmt:
	$(NIX_CMD) run nixpkgs#nixfmt -- flake.nix

check:
	$(NIX_CMD) flake check path:$(CURDIR) --no-write-lock-file
	$(NIX_CMD) eval path:$(CURDIR)#homeConfigurations.deviqon.activationPackage.drvPath --raw >/dev/null

switch:
	home-manager switch --flake path:$(CURDIR)#deviqon
