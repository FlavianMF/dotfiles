# Alvos dos fluxos. O Makefile da raiz repassa para cá (make -C agents/flows).
PYTHON ?= python3
FLOW ?= flows/ecc-dev.yaml
SLUG ?= example
REPO ?= $(CURDIR)
PORT ?= 8765

.PHONY: flow-validate flow-test flow-serve flow-run

flow-validate:
	@$(PYTHON) -m engine.validate $(FLOW) --slug $(SLUG)

flow-test:
	@$(PYTHON) -m pytest -q

flow-serve:
	@$(PYTHON) -m server.app --flow $(FLOW) --repo "$(REPO)" --port $(PORT)

flow-run:
	@test -n "$(INPUT)" || { echo "uso: make flow-run INPUT=\"ideia\" [NAME=ecc-dev] [REPO=..]"; exit 2; }
	@$(PYTHON) -m engine.cli run $(or $(NAME),ecc-dev) --input "$(INPUT)" --repo "$(REPO)"
