.PHONY: flow-validate flow-test flow-serve flow-run install help clean sb-install sb-projects-timer sb-web-token sb-web-install pc-ctl-install pc-ctl-test ha-vps-pack ha-vps-deploy tailscale-install tailscale-status update backup harness harness-dry-run plugins-freeze plugins-update ecc-on ecc-off ecc-status ecc-auto plugins-auto plugins-status ecc-observer-config ecc-rules test ccr-install ccr-update traycer-install traycer-update obsidian-install obsidian-update antigravity-install antigravity-config codex-drift audit lint version

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
	@echo "AI harnesses (Claude Code / Codex / OpenCode / Antigravity CLI):"
	@echo "  make harness          - Só links + harnesses (./install.sh --harness-only)"
	@echo "  make harness-dry-run  - Mostra o que o install faria nos harnesses, sem mudar nada"
	@echo "  make plugins-freeze   - Grava claude/plugins.lock.json (versões instaladas)"
	@echo "  make plugins-update   - Atualiza marketplaces e plugins declarados, depois freeze"
	@echo "  make flow-serve       - Servidor local dos fluxos em 127.0.0.1 (PORT, REPO, FLOW)"
	@echo "  make flow-run INPUT=.. - Inicia um run do fluxo pelo motor, sem servidor (NAME, REPO)"
	@echo "  make flow-validate    - Valida flows/ecc-dev.yaml; flow-test roda os testes"
	@echo "  make ecc-on DIR=..    - Liga o plugin ECC num projeto (NO_COMMON=1 sem rules/common, PACKS=a,b só esses packs, NO_RULES=1 só o plugin)"
	@echo "  make ecc-off DIR=..   - Desliga o plugin ECC no projeto e cria .claude/ecc.off (o auto não religa)"
	@echo "  make ecc-auto DIR=..  - Liga o ECC só se o projeto for web, C ou backend Node (claude/ecc-auto.conf)"
	@echo "  make plugins-auto DIR=.. - Desliga no projeto os plugins que o tipo dele não usa (claude/plugins-auto.conf)"
	@echo "  make plugins-status DIR=. - Mostra o que o plugins-auto gerencia no projeto"
	@echo "  make ecc-observer-config - Liga o observer do continuous-learning-v2 (link para claude/ecc-clv2-config.json)"
	@echo "  make test             - Roda os testes bash de tests/"
	@echo "  make version          - Mostra a versão (tag semver) do dotfiles e avisa se estiver atrás da master"
	@echo "  make ecc-status DIR=. - Mostra se o ECC está ligado no projeto"
	@echo "  make ecc-rules        - Reespelha vendor/ecc/upstream/rules no pin do SOURCE.md"
	@echo "  make ccr-install      - Instala o Claude Code Router na versão de ccr/VERSION"
	@echo "  make ccr-update VERSION=x.y.z - Troca o pin em ccr/VERSION e instala"
	@echo "  make traycer-install  - Instala o Traycer (AppImage conferido por traycer/SHA256)"
	@echo "  make traycer-update   - Baixa o build atual e regrava traycer/SHA256 (revise o diff antes de instalar)"
	@echo "  make obsidian-install - Instala o Obsidian (AppImage conferido por obsidian/SHA256) e registra ~/obsidian_vault"
	@echo "  make obsidian-update [VERSION=x.y.z] - Fixa a release (padrão: latest) em obsidian/VERSION + SHA256 (revise o diff antes de instalar)"
	@echo "  make antigravity-install - Instala o Antigravity CLI (agy) em ~/.local/bin, sha512 do manifesto conferido"
	@echo "  make antigravity-config  - Reaplica MCPs, permissões, skills e hooks do agy em ~/.gemini (merge, não link)"
	@echo "  make codex-drift      - Diferença entre ~/.codex/config.toml e codex/config.base.toml"
	@echo "  make audit            - AgentShield (ecc-agentshield@$(AGENTSHIELD_VERSION)) no repo"
	@echo "  make lint             - bash -n + shellcheck + validação de JSON/TOML"
	@echo ""
	@echo "Remote Control & Home Assistant:"
	@echo "  make pc-ctl-install   - Cria links de bin/pc-ctl em ~/.local/bin e de lib/pc-ctl-log.sh em ~/.local/lib"
	@echo "  make pc-ctl-test      - Executa os testes unitarios TDD de bin/pc-ctl"
	@echo "  make ha-vps-pack      - Gera tarball da stack Home Assistant para envio a VPS"
	@echo "  make ha-vps-deploy [VPS=user@ip] - Deploy automatizado via SSH para a VPS"
	@echo "  make ha-mcp-check     - Testa conectividade com o Home Assistant e disponibilidade do uvx"
	@echo "  make ha-mcp-config [DRY_RUN=1] - Configura ha-mcp nas CLIs de IA locais (Claude, Gemini, OpenCode, Cursor)"
	@echo "  make tailscale-install - Instala o cliente Tailscale no Linux/WSL2"
	@echo "  make tailscale-status  - Exibe o status e IP da rede Tailscale"

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

plugins-auto:
	@./claude/plugins-project.sh auto "$(DIR)"

plugins-status:
	@./claude/plugins-project.sh status "$(DIR)"

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
	@for f in install.sh claude/statusline.sh claude/plugins-freeze.sh claude/ecc-project.sh claude/ecc-detect.sh claude/plugins-project.sh vendor/ecc/fetch-upstream.sh claude/hooks/*.sh ccr/install.sh traycer/install.sh traycer/install_guide.sh traycer/install_agy_wrapper.sh obsidian/install.sh bin/llm-serve bin/llm-ask bin/llm-batch bin/sb bin/pc-ctl bin/dotfiles-version .github/scripts/next-version.sh bin/ha-deploy homeassistant/setup-mcp.sh tailscale/install.sh antigravity/install.sh antigravity/render_config.sh antigravity/hooks/*.sh harness2/install.sh lib/*.sh tests/*.sh; do bash -n "$$f" || exit 1; done
	@if command -v zsh >/dev/null; then zsh -n zsh/ecc-auto.zsh || exit 1; zsh -n zsh/ccr.zsh || exit 1; zsh -n zsh/harness2.zsh || exit 1; fi
	@if command -v shellcheck >/dev/null; then shellcheck -S warning install.sh claude/statusline.sh claude/plugins-freeze.sh claude/ecc-project.sh claude/ecc-detect.sh claude/plugins-project.sh vendor/ecc/fetch-upstream.sh claude/hooks/*.sh ccr/install.sh traycer/install.sh traycer/install_guide.sh traycer/install_agy_wrapper.sh obsidian/install.sh bin/llm-serve bin/llm-ask bin/llm-batch bin/sb bin/pc-ctl bin/dotfiles-version .github/scripts/next-version.sh bin/ha-deploy homeassistant/setup-mcp.sh tailscale/install.sh antigravity/install.sh antigravity/render_config.sh antigravity/hooks/*.sh harness2/install.sh lib/*.sh tests/*.sh; else echo "shellcheck não instalado (componente shellcheck do install.sh)"; fi
	@for f in claude/settings.json claude/plugins.lock.json opencode/opencode.json antigravity/*.json; do jq empty "$$f" || exit 1; done
	@python3 -c 'import sys, tomllib; [tomllib.load(open(f, "rb")) for f in sys.argv[1:]]' codex/config.base.toml codex/yolo.config.toml
	@python3 -m py_compile codex/render_config.py opencode/render_agents.py
	@python3 opencode/render_agents.py vendor/ecc/agents .cache/lint-agents --dry-run > /dev/null
	@echo "lint ok"

ccr-install:
	./ccr/install.sh

ccr-update:
	@test -n "$(VERSION)" || { echo "uso: make ccr-update VERSION=x.y.z"; exit 2; }
	./ccr/install.sh --update $(VERSION)

traycer-install:
	./traycer/install.sh

traycer-update:
	./traycer/install.sh --update

obsidian-install:
	./obsidian/install.sh

obsidian-update:
	./obsidian/install.sh --update $(VERSION)

antigravity-install:
	./antigravity/install.sh

antigravity-config:
	./antigravity/render_config.sh

harness2-install:
	./harness2/install.sh

harness2-update:
	./harness2/install.sh --update

BENCH ?= jb
harness2-check:
	@if command -v harness2-check >/dev/null 2>&1; then harness2-check --bench $(BENCH); elif [[ -x "$$HOME/projetos_harness/harness2/.venv/bin/harness2-check" ]]; then "$$HOME/projetos_harness/harness2/.venv/bin/harness2-check" --bench $(BENCH); else echo "harness2-check não encontrado. Execute 'make harness2-install' primeiro."; exit 1; fi

test:
	@for t in tests/*_test.sh; do echo "== $$t"; bash "$$t" </dev/null || exit 1; done


version:
	@./bin/dotfiles-version

pc-ctl-install:
	@mkdir -p $(HOME)/.local/bin $(HOME)/.local/lib
	ln -sfn $(CURDIR)/bin/pc-ctl $(HOME)/.local/bin/pc-ctl
	ln -sfn $(CURDIR)/lib/pc-ctl-log.sh $(HOME)/.local/lib/pc-ctl-log.sh
	@echo "✓ bin/pc-ctl e lib/pc-ctl-log.sh instalados em $(HOME)/.local/"

pc-ctl-test:
	@bash tests/pc_ctl_test.sh

sb-install:
	@mkdir -p $(HOME)/.local/bin
	ln -sfn $(CURDIR)/bin/sb $(HOME)/.local/bin/sb
	@echo "✓ bin/sb instalado em $(HOME)/.local/bin/sb"

sb-projects-timer: sb-install
	@mkdir -p $(HOME)/.config/systemd/user
	ln -sfn $(CURDIR)/systemd/user/sb-projects-scan.service $(HOME)/.config/systemd/user/sb-projects-scan.service
	ln -sfn $(CURDIR)/systemd/user/sb-projects-scan.timer $(HOME)/.config/systemd/user/sb-projects-scan.timer
	ln -sfn $(CURDIR)/systemd/user/sb-projects-scan-tests.service $(HOME)/.config/systemd/user/sb-projects-scan-tests.service
	ln -sfn $(CURDIR)/systemd/user/sb-projects-scan-tests.timer $(HOME)/.config/systemd/user/sb-projects-scan-tests.timer
	systemctl --user daemon-reload
	systemctl --user enable --now sb-projects-scan.timer sb-projects-scan-tests.timer
	@echo "✓ Timers sb-projects-scan instalados e ativados"

SECRETS_DIR ?= $(CURDIR)/secrets

sb-web-token:
	@mkdir -p -m 700 $(SECRETS_DIR)
	@python3 -c 'import os, secrets, sys; p = os.path.join(sys.argv[1], "sb-web.env"); tok = secrets.token_urlsafe(32); fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600); os.fchmod(fd, 0o600); os.write(fd, f"SB_WEB_TOKEN={tok}\n".encode("utf-8")); os.close(fd); print(f"Token gerado em {p}:\n{tok}")' $(SECRETS_DIR)

sb-web-install: sb-install
	@if [ ! -f $(SECRETS_DIR)/sb-web.env ]; then echo "Erro: $(SECRETS_DIR)/sb-web.env não encontrado. Rode 'make sb-web-token' primeiro." >&2; exit 1; fi
	@mkdir -p $(HOME)/.config/systemd/user
	ln -sfn $(CURDIR)/systemd/user/sb-web.service $(HOME)/.config/systemd/user/sb-web.service
	systemctl --user daemon-reload
	systemctl --user enable --now sb-web.service
	@echo "✓ sb-web.service instalado e ativado"

ha-vps-pack:
	@tar -czvf /tmp/homeassistant-vps-stack.tar.gz homeassistant/
	@echo "✓ Pacote gerado em /tmp/homeassistant-vps-stack.tar.gz pronto para envio à VPS."

ha-vps-deploy:
	@./bin/ha-deploy $(VPS)

tailscale-install:
	@./tailscale/install.sh

tailscale-status:
	@tailscale status || echo "Tailscale não está em execução ou não conectado. Rode sudo tailscale up."

ha-mcp-check:
	@./homeassistant/setup-mcp.sh check

ha-mcp-config:
	@./homeassistant/setup-mcp.sh config $(if $(DRY_RUN),--dry-run)

flow-validate flow-test:
	@$(MAKE) --no-print-directory -C vendor/flows-editor $@

flow-serve flow-run:
	@$(MAKE) --no-print-directory -C vendor/flows-editor $@ REPO="$(if $(REPO),$(REPO),$(CURDIR))"
