#!/bin/bash
#
# Dev Environment Setup Script
# Instala e configura Zsh, Oh-My-Zsh, Nvim, Tmux, e Fonts
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$REPO_DIR/config"
SCRIPTS_DIR="$REPO_DIR/scripts"

# Functions
print_header() {
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  $1"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

check_sudo() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Este script deve ser executado com sudo!"
        exit 1
    fi
}

backup_existing_config() {
    local config_file=$1
    local backup_dir="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"

    if [ -e "$config_file" ]; then
        mkdir -p "$backup_dir"
        cp -r "$config_file" "$backup_dir/"
        print_info "Backup de $config_file em $backup_dir"
    fi
}

install_dependencies() {
    print_header "Instalando Dependências"

    apt-get update
    apt-get install -y \
        build-essential \
        curl \
        wget \
        git \
        zsh \
        tmux \
        fontconfig \
        fontconfig-utils \
        fonts-firacode \
        fonts-noto-color-emoji \
        gettext \
        nodejs \
        npm \
        python3 \
        python3-pip \
        ripgrep \
        fd-find \
        fzf

    print_success "Dependências instaladas"
}

install_nvim() {
    print_header "Instalando Neovim"

    local nvim_version="v0.12.4"
    local nvim_dir="/opt/nvim-linux-x86_64"

    if [ -d "$nvim_dir" ]; then
        print_info "Neovim já está instalado"
        return
    fi

    cd /tmp
    wget -q "https://github.com/neovim/neovim/releases/download/${nvim_version}/nvim-linux-x86_64.tar.gz"
    tar xzf nvim-linux-x86_64.tar.gz -C /opt/
    rm nvim-linux-x86_64.tar.gz

    ln -sf "$nvim_dir/bin/nvim" /usr/local/bin/nvim

    print_success "Neovim $nvim_version instalado"
}

install_oh_my_zsh() {
    print_header "Instalando Oh-My-Zsh"

    if [ -d "$HOME/.oh-my-zsh" ]; then
        print_info "Oh-My-Zsh já está instalado"
        return
    fi

    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

    print_success "Oh-My-Zsh instalado"
}

install_fonts() {
    print_header "Instalando Fonts Nerd Font"

    mkdir -p "$HOME/.local/share/fonts"

    # FiraCode Nerd Font
    print_info "Baixando FiraCode Nerd Font..."
    cd "$HOME/.local/share/fonts"
    wget -q "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/FiraCode.zip"
    unzip -o -q FiraCode.zip
    rm FiraCode.zip

    # JetBrains Mono Nerd Font
    print_info "Baixando JetBrains Mono Nerd Font..."
    wget -q "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/JetBrainsMono.zip"
    unzip -o -q JetBrainsMono.zip
    rm JetBrainsMono.zip

    # Rebuild font cache
    fc-cache -fv "$HOME/.local/share/fonts" > /dev/null 2>&1

    print_success "Fonts instaladas"
}

setup_zsh_config() {
    print_header "Configurando Zsh"

    backup_existing_config "$HOME/.zshrc"
    cp "$CONFIG_DIR/zsh/.zshrc" "$HOME/.zshrc"

    print_success "Zsh configurado"
}

setup_nvim_config() {
    print_header "Configurando Neovim"

    mkdir -p "$HOME/.config/nvim"
    backup_existing_config "$HOME/.config/nvim"

    # Copy nvim config
    cp -r "$CONFIG_DIR/nvim"/* "$HOME/.config/nvim/"

    print_success "Neovim configurado"
    print_info "Execute 'nvim' e depois ':Lazy sync' para instalar plugins"
}

setup_tmux_config() {
    print_header "Configurando Tmux"

    backup_existing_config "$HOME/.tmux.conf"
    cp "$CONFIG_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"

    # Setup TPM (Tmux Plugin Manager)
    if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
        print_info "Instalando TPM (Tmux Plugin Manager)..."
        git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
    fi

    print_success "Tmux configurado"
    print_info "No Tmux, execute: Ctrl+Space + I para instalar plugins"
}

set_default_shell() {
    print_header "Definindo Shell Padrão"

    local zsh_path=$(which zsh)
    chsh -s "$zsh_path"

    print_success "Zsh definido como shell padrão"
}

print_summary() {
    echo ""
    print_header "Instalação Concluída! ✨"
    echo ""
    echo -e "${GREEN}Próximos passos:${NC}"
    echo ""
    echo "1. ${YELLOW}Reabra seu terminal ou execute:${NC}"
    echo "   ${BLUE}exec zsh${NC}"
    echo ""
    echo "2. ${YELLOW}Configure a fonte no seu terminal para:${NC}"
    echo "   ${BLUE}FiraCode Nerd Font${NC} (ou JetBrains Mono Nerd Font)"
    echo ""
    echo "3. ${YELLOW}No Neovim, instale os plugins:${NC}"
    echo "   ${BLUE}nvim${NC}"
    echo "   ${BLUE}:Lazy sync${NC}"
    echo ""
    echo "4. ${YELLOW}No Tmux, instale os plugins:${NC}"
    echo "   ${BLUE}tmux${NC}"
    echo "   ${BLUE}Ctrl+Space + I${NC}"
    echo ""
    echo -e "${GREEN}Atalhos úteis:${NC}"
    echo ""
    echo "Tmux:"
    echo "  ${BLUE}Ctrl+Space + n${NC}  - próxima aba"
    echo "  ${BLUE}Ctrl+Space + p${NC}  - aba anterior"
    echo "  ${BLUE}Ctrl+Space + c${NC}  - nova janela"
    echo ""
    echo "Vim:"
    echo "  ${BLUE}Ctrl+h/j/k/l${NC}  - navega entre Vim e Tmux"
    echo "  ${BLUE}<Tab>/<S-Tab>${NC} - próxima/anterior tab"
    echo ""
}

main() {
    echo ""
    print_header "Dev Environment Setup 🚀"
    echo ""
    echo "Repositório: $REPO_DIR"
    echo "Config Dir: $CONFIG_DIR"
    echo ""

    # Check sudo
    check_sudo

    # Installation steps
    install_dependencies
    install_nvim
    install_oh_my_zsh
    install_fonts
    setup_zsh_config
    setup_nvim_config
    setup_tmux_config
    set_default_shell

    # Summary
    print_summary

    echo ""
}

# Run main
main "$@"
