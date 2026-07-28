#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%s)"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Detect if running interactively
is_interactive() {
    [[ $- == *i* ]]
}

log_info "Starting dotfiles installation from $REPO_DIR"

# Check if running as root or with sudo
SUDO_CMD=""
if [[ $EUID -ne 0 ]]; then
    SUDO_CMD="sudo"
fi

# ===== Install system dependencies =====
log_info "Checking and installing system dependencies..."

if ! command -v apt-get &> /dev/null; then
    log_error "apt not found. This script supports Ubuntu/Debian systems only."
    exit 1
fi

# Base packages (always required)
REQUIRED_PACKAGES=(git curl zsh tmux build-essential)

# Optional components
declare -A OPTIONAL_COMPONENTS=(
    [node]="Node.js (required for nvim treesitter)"
    [python]="Python 3.12 (dev environment)"
    [docker]="Docker (containerization)"
    [gh]="GitHub CLI (gh)"
)

# Packages for each optional component
declare -A COMPONENT_PACKAGES=(
    [node]="nodejs npm"
    [python]="python3.12 python3.12-venv python3.12-dev python3-pip"
)

# Track selected components
declare -A SELECTED_COMPONENTS=(
    [docker]=0
    [gh]=0
)

# Interactive selection
select_components() {
    if ! is_interactive; then
        log_info "Running non-interactively. Installing default components: node, python"
        SELECTED_COMPONENTS[node]=1
        SELECTED_COMPONENTS[python]=1
        return
    fi

    echo ""
    echo "Select components to install (use space to select/deselect, enter to confirm):"
    echo ""

    local options=()
    local defaults=()
    for comp in "${!OPTIONAL_COMPONENTS[@]}"; do
        options+=("$comp")
    done

    # Simple menu loop for selection
    while true; do
        echo "Available components:"
        for i in "${!options[@]}"; do
            local comp="${options[$i]}"
            local checked=" "
            [[ ${SELECTED_COMPONENTS[$comp]} -eq 1 ]] && checked="✓"
            echo "  [$checked] $comp - ${OPTIONAL_COMPONENTS[$comp]}"
        done
        echo "  [done] Proceed with installation"
        echo ""
        read -p "Toggle component (node/python/docker/gh) or 'done': " choice

        case "$choice" in
            done) break ;;
            node|python|docker|gh)
                SELECTED_COMPONENTS[$choice]=$((1 - SELECTED_COMPONENTS[$choice]))
                ;;
            *)
                echo "Invalid choice"
                ;;
        esac
        echo ""
    done
}

select_components

# Build package list based on selections
ALL_PACKAGES=("${REQUIRED_PACKAGES[@]}")

if [[ ${SELECTED_COMPONENTS[node]} -eq 1 ]]; then
    log_info "Node.js selected"
    ALL_PACKAGES+=(${COMPONENT_PACKAGES[node]})
fi

if [[ ${SELECTED_COMPONENTS[python]} -eq 1 ]]; then
    log_info "Python 3.12 selected"
    ALL_PACKAGES+=(${COMPONENT_PACKAGES[python]})
fi

# Check if packages are installed
MISSING_PACKAGES=()
for pkg in "${ALL_PACKAGES[@]}"; do
    if ! dpkg -l 2>/dev/null | grep -q "^ii  $pkg"; then
        MISSING_PACKAGES+=("$pkg")
    fi
done

if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
    log_info "Installing missing packages: ${MISSING_PACKAGES[*]}"
    $SUDO_CMD apt-get update
    $SUDO_CMD apt-get install -y "${MISSING_PACKAGES[@]}"
fi

# Install Neovim if not present
if ! command -v nvim &> /dev/null; then
    log_info "Installing Neovim..."
    NVIM_VERSION=$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)
    NVIM_URL="https://github.com/neovim/neovim/releases/download/$NVIM_VERSION/nvim-linux-x86_64.tar.gz"

    if [[ ! -d /opt/nvim-linux-x86_64 ]]; then
        $SUDO_CMD mkdir -p /opt/nvim-linux-x86_64
        curl -sL "$NVIM_URL" | $SUDO_CMD tar xzf - -C /opt/ --strip-components=1 -C /opt/nvim-linux-x86_64 2>/dev/null || \
        (curl -sL "$NVIM_URL" | tar xzf - && $SUDO_CMD mv nvim-linux-x86_64/* /opt/nvim-linux-x86_64/ && rm -rf nvim-linux-x86_64)
    fi

    # Symlink to PATH
    $SUDO_CMD ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim 2>/dev/null || true
fi

# Install Docker if selected and not present
if [[ ${SELECTED_COMPONENTS[docker]} -eq 1 ]] && ! command -v docker &> /dev/null; then
    log_info "Installing Docker..."
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    $SUDO_CMD sh /tmp/get-docker.sh
    if [[ -n "${USER:-}" ]]; then
        $SUDO_CMD usermod -aG docker "$USER" 2>/dev/null || true
        log_warn "You may need to log out and back in for Docker group membership to take effect"
    fi
    rm /tmp/get-docker.sh
fi

# Install GitHub CLI if selected and not present
if [[ ${SELECTED_COMPONENTS[gh]} -eq 1 ]] && ! command -v gh &> /dev/null; then
    log_info "Installing GitHub CLI (gh)..."
    $SUDO_CMD mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | $SUDO_CMD dd of=/etc/apt/keyrings/githubcli-archive-keyring.gpg
    $SUDO_CMD chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    # Use DEB822 format for sources.list.d on Ubuntu 24.04+
    echo "Types: deb
URIs: https://cli.github.com/packages
Suites: stable
Signed-By: /etc/apt/keyrings/githubcli-archive-keyring.gpg
Components: main" | $SUDO_CMD tee /etc/apt/sources.list.d/github-cli.sources > /dev/null
    $SUDO_CMD apt-get update
    $SUDO_CMD apt-get install -y gh
fi

# ===== Install Oh My Zsh =====
if [[ ! -d $HOME/.oh-my-zsh ]]; then
    log_info "Installing Oh My Zsh..."
    RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" 2>/dev/null || true
fi

# ===== Install Zsh plugins and theme =====
log_info "Installing Zsh plugins and theme..."

ZSH_PLUGINS_DIR="$ZSH_CUSTOM/plugins"
mkdir -p "$ZSH_PLUGINS_DIR"

# zsh-autosuggestions
if [[ ! -d "$ZSH_PLUGINS_DIR/zsh-autosuggestions" ]]; then
    log_info "Cloning zsh-autosuggestions..."
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_PLUGINS_DIR/zsh-autosuggestions"
else
    log_info "Updating zsh-autosuggestions..."
    git -C "$ZSH_PLUGINS_DIR/zsh-autosuggestions" pull origin master
fi

# zsh-syntax-highlighting
if [[ ! -d "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting" ]]; then
    log_info "Cloning zsh-syntax-highlighting..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting"
else
    log_info "Updating zsh-syntax-highlighting..."
    git -C "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting" pull origin master
fi

# spaceship-prompt theme
ZSH_THEMES_DIR="$ZSH_CUSTOM/themes"
mkdir -p "$ZSH_THEMES_DIR"

if [[ ! -d "$ZSH_THEMES_DIR/spaceship-prompt" ]]; then
    log_info "Cloning spaceship-prompt theme..."
    git clone https://github.com/spaceship-prompt/spaceship-prompt "$ZSH_THEMES_DIR/spaceship-prompt"
else
    log_info "Updating spaceship-prompt theme..."
    git -C "$ZSH_THEMES_DIR/spaceship-prompt" pull origin master
fi

# ===== Install TPM (Tmux Plugin Manager) =====
if [[ ! -d $HOME/.tmux/plugins/tpm ]]; then
    log_info "Installing TPM (Tmux Plugin Manager)..."
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
else
    log_info "Updating TPM..."
    git -C ~/.tmux/plugins/tpm pull origin master
fi

# ===== Backup existing configs =====
log_info "Creating backup of existing configs..."
mkdir -p "$BACKUP_DIR"

CONFIG_ITEMS=(
    "$HOME/.zshrc"
    "$HOME/.tmux.conf"
    "$HOME/.config/nvim"
    "$HOME/.gitconfig"
    "$HOME/.config/git/ignore"
    "$HOME/.claude/settings.json"
)

for item in "${CONFIG_ITEMS[@]}"; do
    if [[ -e "$item" ]]; then
        log_warn "Backing up $item"
        cp -r "$item" "$BACKUP_DIR/"
    fi
done

# ===== Create symlinks =====
log_info "Creating symlinks..."

# Ensure directories exist
mkdir -p "$HOME/.config/git"
mkdir -p "$HOME/.config/nvim"
mkdir -p "$HOME/.claude"

# zshrc
ln -sf "$REPO_DIR/zsh/.zshrc" "$HOME/.zshrc"
log_info "Symlinked .zshrc"

# tmux.conf
ln -sf "$REPO_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"
log_info "Symlinked .tmux.conf"

# nvim (entire directory)
rm -rf "$HOME/.config/nvim" || true
ln -sf "$REPO_DIR/nvim" "$HOME/.config/nvim"
log_info "Symlinked nvim config"

# gitconfig
ln -sf "$REPO_DIR/git/.gitconfig" "$HOME/.gitconfig"
log_info "Symlinked .gitconfig"

# git global ignore
ln -sf "$REPO_DIR/git/ignore" "$HOME/.config/git/ignore"
log_info "Symlinked git ignore"

# claude settings
ln -sf "$REPO_DIR/claude/settings.json" "$HOME/.claude/settings.json"
log_info "Symlinked .claude/settings.json"

# ===== Configure git identity =====
if [[ ! -f "$HOME/.gitconfig.local" ]]; then
    log_info "Setting up git identity..."

    if is_interactive; then
        read -p "Enter your git user name: " git_name
        read -p "Enter your git email: " git_email
    else
        log_warn "Not running interactively. Please configure git manually later:"
        log_warn "  git config --global user.name 'Your Name'"
        log_warn "  git config --global user.email 'your.email@example.com'"
        git_name="${GIT_NAME:-}"
        git_email="${GIT_EMAIL:-}"
    fi

    if [[ -n "$git_name" && -n "$git_email" ]]; then
        cat > "$HOME/.gitconfig.local" << EOF
[user]
	name = $git_name
	email = $git_email
EOF
        log_info "Created .gitconfig.local"
    fi
fi

# ===== Install Tmux plugins =====
log_info "Installing Tmux plugins..."
"$HOME/.tmux/plugins/tpm/bin/install_plugins" 2>/dev/null || log_warn "Could not auto-install tmux plugins. Run: prefix + I in tmux"

# ===== Install Neovim plugins =====
log_info "Installing Neovim plugins (this may take a moment)..."
nvim --headless "+Lazy! sync" +qa 2>/dev/null || log_warn "Could not auto-install nvim plugins. Run: :Lazy sync in nvim"

# ===== Set default shell to zsh =====
if [[ "$SHELL" != "$(which zsh)" ]]; then
    log_info "Changing default shell to zsh..."
    if is_interactive; then
        read -p "Change your default shell to zsh? (requires password) [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            chsh -s "$(which zsh)"
            log_info "Default shell changed to zsh. You may need to log out and back in."
        fi
    else
        log_warn "Not running interactively. To change default shell, run: chsh -s $(which zsh)"
    fi
fi

# ===== Summary =====
echo ""
log_info "Installation complete!"
echo ""
echo "Summary:"
echo "=========="
echo "✓ System dependencies installed"
echo "✓ Neovim installed"
[[ ${SELECTED_COMPONENTS[node]} -eq 1 ]] && echo "✓ Node.js and npm installed"
[[ ${SELECTED_COMPONENTS[python]} -eq 1 ]] && echo "✓ Python 3.12 installed"
[[ ${SELECTED_COMPONENTS[docker]} -eq 1 ]] && echo "✓ Docker installed"
[[ ${SELECTED_COMPONENTS[gh]} -eq 1 ]] && echo "✓ GitHub CLI (gh) installed"
echo "✓ Oh My Zsh configured"
echo "✓ Zsh plugins installed (autosuggestions, syntax-highlighting)"
echo "✓ Spaceship prompt theme installed"
echo "✓ Tmux plugin manager installed"
echo "✓ Config files symlinked from $REPO_DIR"
echo "✓ Git identity configured"
echo "✓ Tmux plugins installed"
echo "✓ Neovim plugins installed"
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
echo "Next steps:"
echo "1. Start a new shell or run: exec \$SHELL"
[[ ${SELECTED_COMPONENTS[docker]} -eq 1 ]] && echo "2. For Docker, run: newgrp docker (to avoid needing sudo)"
[[ ${SELECTED_COMPONENTS[gh]} -eq 1 ]] && echo "3. Authenticate with GitHub: gh auth login"
echo "4. Add your SSH keys to ~/.ssh/ if needed"
echo ""
