FLAKE ?= $(HOME)/.config/my-setup
FLAKE_REF ?= path:$(FLAKE)
NIX_INSTALLER_URL ?= https://install.determinate.systems/nix
NIX_PROFILE ?= /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
NIX_CMD = nix --extra-experimental-features 'nix-command flakes'
NIX_FORMATTER ?= nixpkgs\#nixfmt
NIX_FILES = \
	$(FLAKE)/flake.nix \
	$(wildcard $(FLAKE)/modules/*.nix)
PIN_UPDATE_PACKAGES = \
	nixpkgs\#go \
	nixpkgs\#nodejs \
	nixpkgs\#p7zip \
	nixpkgs\#xar
RELEASE_UPDATE_PACKAGES = \
	nixpkgs\#git \
	nixpkgs\#go

.PHONY: help bootstrap install-clt install-nix fmt check check-nix switch system-switch home-switch update update-pins update-all audit

help:
	@printf '%s\n' \
		'Available targets:' \
		'  make bootstrap      Install pre-Nix prerequisites, then apply the flake' \
		'  make install-clt    Install Apple Command Line Tools if missing' \
		'  make install-nix    Install Nix if missing' \
		'  make fmt            Format Nix files' \
		'  make check          Validate the flake' \
		'  make switch         Apply system and Home Manager config' \
		'  make system-switch  Apply nix-darwin system config' \
		'  make home-switch    Apply Home Manager through nix-darwin' \
		'  make update         Update release branch and flake inputs' \
		'  make update-pins    Update manual package pins and hashes' \
		'  make update-all     Update flake inputs, pins, and run audit' \
		'  make audit          Run local Nix/OpenCode hygiene checks'

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

fmt:
	@if [ -f '$(NIX_PROFILE)' ]; then . '$(NIX_PROFILE)'; fi; \
	$(NIX_CMD) run '$(NIX_FORMATTER)' -- $(NIX_FILES)

check: check-nix

check-nix:
	@if [ -f '$(NIX_PROFILE)' ]; then . '$(NIX_PROFILE)'; fi; \
	$(NIX_CMD) flake check $(FLAKE_REF); \
	$(NIX_CMD) eval $(FLAKE_REF)#darwinConfigurations.Andys-Mac-mini.config.system.build.toplevel.drvPath --raw >/dev/null

switch: system-switch

system-switch:
	@if command -v darwin-rebuild >/dev/null 2>&1; then \
		darwin-rebuild switch --flake $(FLAKE_REF); \
	else \
		if [ -f '$(NIX_PROFILE)' ]; then . '$(NIX_PROFILE)'; fi; \
		$(NIX_CMD) run github:nix-darwin/nix-darwin/master#darwin-rebuild -- switch --flake $(FLAKE_REF); \
	fi

home-switch: system-switch

update:
	@if [ -f '$(NIX_PROFILE)' ]; then . '$(NIX_PROFILE)'; fi; \
	$(NIX_CMD) shell $(RELEASE_UPDATE_PACKAGES) -c go -C $(FLAKE)/tools/setupctl run . update-release --repo $(FLAKE); \
	$(NIX_CMD) flake update --flake $(FLAKE_REF)

update-pins:
	@if [ -f '$(NIX_PROFILE)' ]; then . '$(NIX_PROFILE)'; fi; \
	$(NIX_CMD) shell $(PIN_UPDATE_PACKAGES) -c go -C $(FLAKE)/tools/setupctl run . update-pins --repo $(FLAKE)

update-all: update update-pins audit

audit:
	@if [ -f '$(NIX_PROFILE)' ]; then . '$(NIX_PROFILE)'; fi; \
	set -e; \
	printf '%s\n' '== nix parse =='; \
	for file in $(NIX_FILES); do nix-instantiate --parse "$$file" >/dev/null; done; \
	printf '%s\n' '== nix eval =='; \
	$(NIX_CMD) eval $(FLAKE_REF)#darwinConfigurations.Andys-Mac-mini.config.system.build.toplevel.drvPath --raw >/dev/null; \
	printf '%s\n' '== opencode startup =='; \
	opencode debug startup --print-logs --log-level DEBUG >/dev/null; \
	printf '%s\n' '== opencode plugin state =='; \
	test ! -e $(HOME)/.config/opencode/plugins/openviking-memory.log; \
	test ! -e $(HOME)/.config/opencode/plugins/openviking-session-map.json; \
	test -e $(HOME)/.local/state/opencode/openviking/openviking-memory.log; \
	printf '%s\n' '== git status =='; \
	git -C $(FLAKE) status --short --branch
