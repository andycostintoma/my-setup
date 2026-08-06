# Shared Make plumbing for the machine flakes.
# Include from a machine Makefile after defining EVAL_ATTR:
#   EVAL_ATTR = darwinConfigurations.<host>.config.system.build.toplevel.drvPath
#   include ../shared/make/common.mk
#
# FLAKE_ARGS and SHARED_REF must stay in lockstep across machines, or
# --override-input shared silently diverges. That is why they live here.

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
	$(wildcard $(FLAKE)/modules/*.nix) \
	$(REPO_ROOT)/shared/flake.nix \
	$(wildcard $(REPO_ROOT)/shared/modules/*.nix)

.PHONY: fmt check audit

fmt:
	@if [ -f '$(NIX_PROFILE)' ]; then . '$(NIX_PROFILE)'; fi; \
	$(NIX_CMD) run '$(NIX_FORMATTER)' -- $(NIX_FILES)

check:
	@if [ -f '$(NIX_PROFILE)' ]; then . '$(NIX_PROFILE)'; fi; \
	$(NIX_CMD) flake check $(FLAKE_REF) $(FLAKE_ARGS); \
	$(NIX_CMD) eval $(FLAKE_REF)#$(EVAL_ATTR) $(FLAKE_ARGS) --raw >/dev/null

audit:
	@if [ -f '$(NIX_PROFILE)' ]; then . '$(NIX_PROFILE)'; fi; \
	set -e; \
	printf '%s\n' '== nix parse =='; \
	for file in $(NIX_FILES); do nix-instantiate --parse "$$file" >/dev/null; done; \
	printf '%s\n' '== nix eval =='; \
	$(NIX_CMD) eval $(FLAKE_REF)#$(EVAL_ATTR) $(FLAKE_ARGS) --raw >/dev/null; \
	printf '%s\n' '== opencode startup =='; \
	opencode debug startup --print-logs --log-level DEBUG >/dev/null; \
	printf '%s\n' '== git status =='; \
	git -C $(REPO_ROOT) status --short --branch
