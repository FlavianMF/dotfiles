# Alvos mínimos do T1. O T6 completa o Makefile (flow-serve, flow-run).
PYTHON ?= python3
FLOW ?= flows/ecc-dev.yaml
SLUG ?= example

.PHONY: flow-validate flow-test

flow-validate:
	@$(PYTHON) -m engine.validate $(FLOW) --slug $(SLUG)

flow-test:
	@$(PYTHON) -m pytest -q
