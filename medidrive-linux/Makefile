SHELL := /bin/bash
.DEFAULT_GOAL := help

EVAL_ATTR = homeConfigurations.medidrive.activationPackage.drvPath

include ../shared/make/common.mk

.PHONY: help switch

help:
	@printf '%s\n' \
		'Available targets:' \
		'  make fmt     Format Nix files' \
		'  make check   Validate the Medidrive Home Manager output' \
		'  make switch  Apply the Medidrive Home Manager config' \
		'  make audit   Run local Medidrive setup hygiene checks'

switch:
	home-manager switch --flake $(FLAKE_REF)#medidrive $(FLAKE_ARGS)
