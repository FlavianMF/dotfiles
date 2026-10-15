.PHONY: install help clean update backup harness harness-dry-run plugins-freeze plugins-update ecc-on ecc-off ecc-status ecc-auto ecc-observer-config ecc-rules test codex-drift audit lint

AGENTSHIELD_VERSION := 1.6.0
AUDIT_PATH ?= $(CURDIR)

help:
	@echo "Dev Environment Setup - Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  make install      - Instala tudo (requer sudo)"
	@echo "  make update       - Atualiza configurações"
	@echo "  make backup       - Faz backup das configs atuais"
	@echo "  make clean        - Remove links simbólicos"
	@echo "  make help         - Mostra esta mensagem"
	@echo ""
	@echo "AI harnesses (Claude Code / Codex / OpenCode):"
	@echo "  make harness          - Só links + harnesses (./install.sh --harness-only)"
	@echo "  make harness-dry-run  - Mostra o que o install faria nos harnesses, sem mudar nada"
	@echo "  make plugins-freeze   - Grava claude/plugins.lock.json (versões instaladas)"
	@echo "  make plugins-update   - Atualiza marketplaces e plugins declarados, depois freeze"
	@echo "  make ecc-on DIR=..    - Liga o plugin ECC num projeto (NO_COMMON=1 sem rules/common, PACKS=a,b só esses packs, NO_RULES=1 só o plugin)"
	@echo "  make ecc-off DIR=..   - Desliga o plugin ECC no projeto e cria .claude/ecc.off (o auto não religa)"
	@echo "  make ecc-auto DIR=..  - Liga o ECC só se o projeto for web, C ou backend Node (claude/ecc-auto.conf)"
	@echo "  make ecc-observer-config - Liga o observer do continuous-learning-v2 (link para claude/ecc-clv2-config.json)"
	@echo "  make test             - Roda os testes bash de tests/"
	@echo "  make ecc-status DIR=. - Mostra se o ECC está ligado no projeto"
	@echo "  make ecc-rules        - Reespelha vendor/ecc/upstream/rules no pin do SOURCE.md"
	@echo "  make codex-drift      - Diferença entre ~/.codex/config.toml e codex/config.base.toml"
	@echo "  make audit            - AgentShield (ecc-agentshield@$(AGENTSHIELD_VERSION)) no repo"
	@echo "  make lint             - bash -n + shellcheck + validação de JSON/TOML"

install:
	chmod +x install.sh
	./install.sh

update:
	@echo "Atualizando configurações..."
	cp ~/.zshrc config/zsh/.zshrc
	cp ~/.tmux.conf config/tmux/.tmux.conf
	cp -r ~/.config/nvim/* config/nvim/
	@echo "✓ Configurações atualizadas"

backup:
	@echo "Fazendo backup das configurações atuais..."
	@mkdir -p backups
	@cp -r ~/.zshrc backups/.zshrc.bak.$(shell date +%Y%m%d-%H%M%S) 2>/dev/null || true
	@cp -r ~/.tmux.conf backups/.tmux.conf.bak.$(shell date +%Y%m%d-%H%M%S) 2>/dev/null || true
	@cp -r ~/.config/nvim backups/nvim.bak.$(shell date +%Y%m%d-%H%M%S) 2>/dev/null || true
	@echo "✓ Backup concluído em ./backups/"

clean:
	@echo "Limpando..."
	@rm -f ~/.zshrc ~/.tmux.conf
	@rm -rf ~/.config/nvim
	@echo "✓ Links removidos"

harness:
	./install.sh --harness-only

harness-dry-run:
	./install.sh --dry-run

plugins-freeze:
	@./claude/plugins-freeze.sh

plugins-update:
	claude plugin marketplace update
	@jq -r '.enabledPlugins // {} | keys[]' claude/settings.json | \
		while read -r id; do echo "claude plugin update $$id"; claude plugin update "$$id" < /dev/null || true; done
	@./claude/plugins-freeze.sh
	@echo "Revise: git diff claude/plugins.lock.json (reinicie o Claude Code para aplicar)"
	@echo "Se ecc@ecc mudou de versão: atualize o SHA em vendor/ecc/SOURCE.md e rode make ecc-rules"

# ECC: plugin instalado e desligado globalmente; liga por projeto.
DIR ?= .
ecc-on:
	@./claude/ecc-project.sh on "$(DIR)" $(if $(NO_COMMON),--no-common) $(if $(PACKS),--packs "$(PACKS)") $(if $(NO_RULES),--no-rules)

ecc-off:
	@./claude/ecc-project.sh off "$(DIR)"

ecc-auto:
	@./claude/ecc-project.sh auto "$(DIR)"

ecc-observer-config:
	@d="$${CLV2_HOMUNCULUS_DIR:-$${XDG_DATA_HOME:-$$HOME/.local/share}/ecc-homunculus}"; \
	mkdir -p "$$d" && chmod 700 "$$d" && \
	if [ -e "$$d/config.json" ] && [ ! -L "$$d/config.json" ]; then echo "$$d/config.json existe e não é link; não mexi"; \
	else ln -sfn "$(CURDIR)/claude/ecc-clv2-config.json" "$$d/config.json" && echo "observer: $$d/config.json -> claude/ecc-clv2-config.json"; fi

ecc-status:
	@./claude/ecc-project.sh status "$(DIR)"

ecc-rules:
	@./vendor/ecc/fetch-upstream.sh

codex-drift:
	@python3 codex/render_config.py codex/config.base.toml $(HOME)/.codex/config.toml --drift

# Sem instalar global: npx baixa a versão fixada sob demanda.
audit:
	npx -y ecc-agentshield@$(AGENTSHIELD_VERSION) scan --path $(AUDIT_PATH)

lint:
	@for f in install.sh claude/statusline.sh claude/plugins-freeze.sh claude/ecc-project.sh claude/ecc-detect.sh vendor/ecc/fetch-upstream.sh claude/hooks/*.sh tests/*.sh; do bash -n "$$f" || exit 1; done
	@if command -v zsh >/dev/null; then zsh -n zsh/ecc-auto.zsh || exit 1; fi
	@if command -v shellcheck >/dev/null; then shellcheck -S warning install.sh claude/statusline.sh claude/plugins-freeze.sh claude/ecc-project.sh claude/ecc-detect.sh vendor/ecc/fetch-upstream.sh claude/hooks/*.sh tests/*.sh; else echo "shellcheck não instalado (componente shellcheck do install.sh)"; fi
	@for f in claude/settings.json claude/plugins.lock.json opencode/opencode.json; do jq empty "$$f" || exit 1; done
	@python3 -c 'import sys, tomllib; [tomllib.load(open(f, "rb")) for f in sys.argv[1:]]' codex/config.base.toml codex/yolo.config.toml
	@python3 -m py_compile codex/render_config.py opencode/render_agents.py
	@python3 opencode/render_agents.py vendor/ecc/agents .cache/lint-agents --dry-run > /dev/null
	@echo "lint ok"

test:
	@for t in tests/*_test.sh; do echo "== $$t"; bash "$$t" || exit 1; done
