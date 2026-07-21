.PHONY: install help clean update backup

help:
	@echo "Dev Environment Setup - Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  make install      - Instala tudo (requer sudo)"
	@echo "  make update       - Atualiza configurações"
	@echo "  make backup       - Faz backup das configs atuais"
	@echo "  make clean        - Remove links simbólicos"
	@echo "  make help         - Mostra esta mensagem"

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
