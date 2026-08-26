SHELL := /bin/bash
.DEFAULT_GOAL := help

EVAL_ATTR = homeConfigurations.deviqon.activationPackage.drvPath

include ../shared/make/common.mk
include ../shared/make/bootstrap.mk

.PHONY: help bootstrap switch

help:
	@printf '%s\n' \
		'Available targets:' \
		'  make bootstrap  Install Nix if missing, then apply the flake' \
		'  make fmt     Format Nix files' \
		'  make check   Validate the Deviqon Home Manager output' \
		'  make switch  Apply the Deviqon Home Manager config' \
		'  make audit   Run local Deviqon setup hygiene checks'

bootstrap: install-nix switch

switch:
	@if [ -f '$(NIX_PROFILE)' ]; then . '$(NIX_PROFILE)'; fi; \
	$(NIX_CMD) run $(FLAKE_REF)#home-manager $(FLAKE_ARGS) -- switch --flake $(FLAKE_REF)#deviqon $(FLAKE_ARGS)
