SHELL := /bin/bash

FLAKE ?= $(CURDIR)
FLAKE_REF ?= path:$(FLAKE)
REPO_ROOT ?= $(abspath $(FLAKE)/..)
SHARED_REF ?= path:$(REPO_ROOT)/shared
FLAKE_ARGS = --override-input shared $(SHARED_REF) --no-write-lock-file
NIX_PROFILE ?= /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
NIX_CMD = nix --extra-experimental-features 'nix-command flakes'
NIX_FORMATTER ?= nixpkgs\#nixfmt
NIX_FILES = \
	$(FLAKE)/flake.nix \
	$(REPO_ROOT)/shared/flake.nix \
	$(wildcard $(REPO_ROOT)/shared/modules/*.nix) \
	$(wildcard $(FLAKE)/modules/*.nix)

.PHONY: help fmt check switch audit

help:
	@printf '%s\n' \
		'Available targets:' \
		'  make fmt     Format Nix files' \
		'  make check   Validate the Medidrive Home Manager output' \
		'  make switch  Apply the Medidrive Home Manager config' \
		'  make audit   Run local Medidrive setup hygiene checks'

fmt:
	@if [ -f '$(NIX_PROFILE)' ]; then . '$(NIX_PROFILE)'; fi; \
	$(NIX_CMD) run '$(NIX_FORMATTER)' -- $(NIX_FILES)

check:
	@if [ -f '$(NIX_PROFILE)' ]; then . '$(NIX_PROFILE)'; fi; \
	$(NIX_CMD) flake check $(FLAKE_REF) $(FLAKE_ARGS); \
	$(NIX_CMD) eval $(FLAKE_REF)#homeConfigurations.medidrive.activationPackage.drvPath $(FLAKE_ARGS) --raw >/dev/null

switch:
	home-manager switch --flake $(FLAKE_REF)#medidrive $(FLAKE_ARGS)

audit:
	@if [ -f '$(NIX_PROFILE)' ]; then . '$(NIX_PROFILE)'; fi; \
	set -e; \
	printf '%s\n' '== nix parse =='; \
	for file in $(NIX_FILES); do nix-instantiate --parse "$$file" >/dev/null; done; \
	printf '%s\n' '== nix eval =='; \
	$(NIX_CMD) eval $(FLAKE_REF)#homeConfigurations.medidrive.activationPackage.drvPath $(FLAKE_ARGS) --raw >/dev/null; \
	printf '%s\n' '== tools =='; \
	command -v opencode >/dev/null; \
	printf '%s\n' '== git status =='; \
	git -C $(REPO_ROOT) status --short --branch
