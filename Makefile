.PHONY: help mac-help mac-fmt mac-check mac-switch mac-audit vm-help vm-fmt vm-check vm-switch vm-audit

help:
	@printf '%s\n' \
		'This repo has no top-level flake entrypoint; root targets delegate only.' \
		'' \
		'Mac:' \
		'  make mac-help' \
		'  make mac-fmt' \
		'  make mac-check' \
		'  make mac-switch' \
		'  make mac-audit' \
		'' \
		'MediDrive VM:' \
		'  make vm-help' \
		'  make vm-fmt' \
		'  make vm-check' \
		'  make vm-switch' \
		'  make vm-audit'

mac-help:
	$(MAKE) -C personal-mac help

mac-fmt:
	$(MAKE) -C personal-mac fmt

mac-check:
	$(MAKE) -C personal-mac check

mac-switch:
	$(MAKE) -C personal-mac switch

mac-audit:
	$(MAKE) -C personal-mac audit

vm-help:
	$(MAKE) -C medidrive-linux help

vm-fmt:
	$(MAKE) -C medidrive-linux fmt

vm-check:
	$(MAKE) -C medidrive-linux check

vm-switch:
	$(MAKE) -C medidrive-linux switch

vm-audit:
	$(MAKE) -C medidrive-linux audit
