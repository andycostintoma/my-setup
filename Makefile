.PHONY: help mac-help mac-fmt mac-check mac-switch mac-audit medidrive-help medidrive-fmt medidrive-check medidrive-switch medidrive-audit deviqon-help deviqon-fmt deviqon-check deviqon-switch

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
		'  make medidrive-help' \
		'  make medidrive-fmt' \
		'  make medidrive-check' \
		'  make medidrive-switch' \
		'  make medidrive-audit' \
		'' \
		'Deviqon Linux:' \
		'  make deviqon-help' \
		'  make deviqon-fmt' \
		'  make deviqon-check' \
		'  make deviqon-switch'

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

medidrive-help:
	$(MAKE) -C medidrive-linux help

medidrive-fmt:
	$(MAKE) -C medidrive-linux fmt

medidrive-check:
	$(MAKE) -C medidrive-linux check

medidrive-switch:
	$(MAKE) -C medidrive-linux switch

medidrive-audit:
	$(MAKE) -C medidrive-linux audit

deviqon-help:
	$(MAKE) -C deviqon-linux help

deviqon-fmt:
	$(MAKE) -C deviqon-linux fmt

deviqon-check:
	$(MAKE) -C deviqon-linux check

deviqon-switch:
	$(MAKE) -C deviqon-linux switch
