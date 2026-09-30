.PHONY: install help clean update backup harness harness-dry-run plugins-freeze plugins-update codex-drift audit lint

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
	@echo "  make codex-drift      - Diferença entre ~/.codex/config.toml e codex/config.base.toml"
	@echo "  make audit            - AgentShield (ecc-agentshield@$(AGENTSHIELD_VERSION)) no repo"
	@echo "  make lint             - bash -n + shellcheck + validação de JSON/TOML"

install:
	sudo chmod +x install.sh
	sudo ./install.sh

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
	@jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key' claude/settings.json | \
		while read -r id; do echo "claude plugin update $$id"; claude plugin update "$$id" < /dev/null || true; done
	@./claude/plugins-freeze.sh
	@echo "Revise: git diff claude/plugins.lock.json (reinicie o Claude Code para aplicar)"

codex-drift:
	@python3 codex/render_config.py codex/config.base.toml $(HOME)/.codex/config.toml --drift

# Sem instalar global: npx baixa a versão fixada sob demanda.
audit:
	npx -y ecc-agentshield@$(AGENTSHIELD_VERSION) scan --path $(AUDIT_PATH)

lint:
	@for f in install.sh claude/statusline.sh claude/plugins-freeze.sh claude/hooks/*.sh; do bash -n "$$f" || exit 1; done
	@if command -v shellcheck >/dev/null; then shellcheck -S warning install.sh claude/statusline.sh claude/plugins-freeze.sh claude/hooks/*.sh; else echo "shellcheck não instalado (componente shellcheck do install.sh)"; fi
	@for f in claude/settings.json claude/plugins.lock.json opencode/opencode.json; do jq empty "$$f" || exit 1; done
	@python3 -c 'import sys, tomllib; [tomllib.load(open(f, "rb")) for f in sys.argv[1:]]' codex/config.base.toml codex/yolo.config.toml
	@python3 -m py_compile codex/render_config.py opencode/render_agents.py
	@python3 opencode/render_agents.py vendor/ecc/agents .cache/lint-agents --dry-run > /dev/null
	@echo "lint ok"
