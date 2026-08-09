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

# Detect if running interactively (stdin is terminal)
is_interactive() {
    [[ -t 0 ]]
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
    [nvim]="Neovim + LazyVim config"
    [ripgrep]="ripgrep (fast search, used by nvim Telescope)"
    [fd]="fd (fast file finder, used by nvim Telescope)"
    [lazygit]="lazygit (git UI, used by nvim plugin)"
)

# Packages for each optional component
declare -A COMPONENT_PACKAGES=(
    [node]="nodejs npm"
    [python]="python3.12 python3.12-venv python3.12-dev python3-pip"
    [ripgrep]="ripgrep"
    [fd]="fd-find"
)

# Track selected components (default: node and python selected)
declare -A SELECTED_COMPONENTS=(
    [node]=1
    [python]=1
    [docker]=0
    [gh]=0
    [nvim]=0
    [ripgrep]=0
    [fd]=0
    [lazygit]=0
)

# Interactive selection with keyboard navigation
select_components() {
    if ! is_interactive; then
        log_info "Running non-interactively. Installing default components: node, python"
        SELECTED_COMPONENTS[node]=1
        SELECTED_COMPONENTS[python]=1
        return
    fi

    local -a options=(node python docker gh nvim ripgrep fd lazygit)
    local current=0
    local done=0
    local old_stty

    # Save terminal settings and set raw mode
    old_stty=$(stty -g)
    stty -echo -icanon 2>/dev/null || true
    tput civis 2>/dev/null || true

    while [[ $done -eq 0 ]]; do
        clear
        echo ""
        echo "Select components to install (↑↓ to navigate, SPACE to toggle, ENTER to confirm):"
        echo ""

        for i in "${!options[@]}"; do
            local comp="${options[$i]}"
            local marker=" "
            local highlight=""

            if [[ $i -eq $current ]]; then
                highlight="\033[1;36m"  # Cyan bold
                marker="→"
            fi

            local checked=" "
            [[ ${SELECTED_COMPONENTS[$comp]} -eq 1 ]] && checked="✓"

            echo -e "${highlight}  ${marker} [$checked] ${comp} - ${OPTIONAL_COMPONENTS[$comp]}\033[0m"
        done

        echo ""
        echo "  Press ENTER to confirm selection"
        echo ""

        # Read one byte
        local input
        IFS= read -r -s -n 1 input

        case "$input" in
            $'\x1b')  # Escape sequence (arrow keys)
                IFS= read -r -s -n 1 input  # Read [
                IFS= read -r -s -n 1 input  # Read A or B
                case "$input" in
                    'A') current=$(( (current - 1 + ${#options[@]}) % ${#options[@]} )) ;;
                    'B') current=$(( (current + 1) % ${#options[@]} )) ;;
                esac
                ;;
            ' ')  # Space
                local comp="${options[$current]}"
                SELECTED_COMPONENTS[$comp]=$((1 - SELECTED_COMPONENTS[$comp]))
                ;;
            '')  # Enter
                done=1
                ;;
        esac
    done

    # Restore terminal
    tput cnorm 2>/dev/null || true
    stty "$old_stty" 2>/dev/null || true
    clear
}

select_components

# If nvim selected, force-select its dependencies
if [[ ${SELECTED_COMPONENTS[nvim]} -eq 1 ]]; then
    if [[ ${SELECTED_COMPONENTS[node]} -eq 0 ]]; then
        log_info "nvim selected: forcing node (required for treesitter)"
        SELECTED_COMPONENTS[node]=1
    fi
    if [[ ${SELECTED_COMPONENTS[ripgrep]} -eq 0 ]]; then
        log_info "nvim selected: forcing ripgrep (required for Telescope)"
        SELECTED_COMPONENTS[ripgrep]=1
    fi
    if [[ ${SELECTED_COMPONENTS[fd]} -eq 0 ]]; then
        log_info "nvim selected: forcing fd (required for Telescope)"
        SELECTED_COMPONENTS[fd]=1
    fi
    if [[ ${SELECTED_COMPONENTS[lazygit]} -eq 0 ]]; then
        log_info "nvim selected: forcing lazygit (used by nvim plugin)"
        SELECTED_COMPONENTS[lazygit]=1
    fi
fi

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

if [[ ${SELECTED_COMPONENTS[ripgrep]} -eq 1 ]]; then
    log_info "ripgrep selected"
    ALL_PACKAGES+=(${COMPONENT_PACKAGES[ripgrep]})
fi

if [[ ${SELECTED_COMPONENTS[fd]} -eq 1 ]]; then
    log_info "fd selected"
    ALL_PACKAGES+=(${COMPONENT_PACKAGES[fd]})
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

# Create fd symlink if installed (package name is fd-find, binary is fdfind)
if [[ ${SELECTED_COMPONENTS[fd]} -eq 1 ]] && ! command -v fd &> /dev/null; then
    if command -v fdfind &> /dev/null; then
        log_info "Creating symlink for fd (fdfind -> /usr/local/bin/fd)"
        $SUDO_CMD ln -sf "$(which fdfind)" /usr/local/bin/fd
    fi
fi

# Install Neovim if selected
if [[ ${SELECTED_COMPONENTS[nvim]} -eq 1 ]] && ! command -v nvim &> /dev/null; then
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

# Install lazygit if selected and not present
if [[ ${SELECTED_COMPONENTS[lazygit]} -eq 1 ]] && ! command -v lazygit &> /dev/null; then
    log_info "Installing lazygit..."
    LAZYGIT_VERSION=$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)
    LAZYGIT_URL="https://github.com/jesseduffield/lazygit/releases/download/$LAZYGIT_VERSION/lazygit_${LAZYGIT_VERSION#v}_Linux_x86_64.tar.gz"

    if [[ ! -d /tmp/lazygit ]]; then
        mkdir -p /tmp/lazygit
        curl -sL "$LAZYGIT_URL" | tar xzf - -C /tmp/lazygit
        $SUDO_CMD install -m 755 /tmp/lazygit/lazygit /usr/local/bin/lazygit
        rm -rf /tmp/lazygit
    fi
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
    "$HOME/.claude/skills/second-brain-sync"
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
mkdir -p "$HOME/.claude"

# zshrc
ln -sf "$REPO_DIR/zsh/.zshrc" "$HOME/.zshrc"
log_info "Symlinked .zshrc"

# tmux.conf
ln -sf "$REPO_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"
log_info "Symlinked .tmux.conf"

# nvim (entire directory) — only if nvim selected
if [[ ${SELECTED_COMPONENTS[nvim]} -eq 1 ]]; then
    mkdir -p "$HOME/.config/nvim"
    rm -rf "$HOME/.config/nvim" || true
    ln -sf "$REPO_DIR/nvim" "$HOME/.config/nvim"
    log_info "Symlinked nvim config"
fi

# gitconfig
ln -sf "$REPO_DIR/git/.gitconfig" "$HOME/.gitconfig"
log_info "Symlinked .gitconfig"

# git global ignore
ln -sf "$REPO_DIR/git/ignore" "$HOME/.config/git/ignore"
log_info "Symlinked git ignore"

# claude settings
ln -sf "$REPO_DIR/claude/settings.json" "$HOME/.claude/settings.json"
log_info "Symlinked .claude/settings.json"

# claude skills - second-brain-sync
mkdir -p "$HOME/.claude/skills"
ln -sf "$REPO_DIR/claude/skills/second-brain-sync" "$HOME/.claude/skills/second-brain-sync"
log_info "Symlinked .claude/skills/second-brain-sync"

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

# ===== Install Neovim plugins (if nvim selected) =====
if [[ ${SELECTED_COMPONENTS[nvim]} -eq 1 ]]; then
    log_info "Installing Neovim plugins (this may take a moment)..."
    nvim --headless "+Lazy! sync" +qa 2>/dev/null || log_warn "Could not auto-install nvim plugins. Run: :Lazy sync in nvim"
fi

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
[[ ${SELECTED_COMPONENTS[node]} -eq 1 ]] && echo "✓ Node.js and npm installed"
[[ ${SELECTED_COMPONENTS[python]} -eq 1 ]] && echo "✓ Python 3.12 installed"
[[ ${SELECTED_COMPONENTS[docker]} -eq 1 ]] && echo "✓ Docker installed"
[[ ${SELECTED_COMPONENTS[gh]} -eq 1 ]] && echo "✓ GitHub CLI (gh) installed"
[[ ${SELECTED_COMPONENTS[nvim]} -eq 1 ]] && echo "✓ Neovim installed"
[[ ${SELECTED_COMPONENTS[ripgrep]} -eq 1 ]] && echo "✓ ripgrep installed"
[[ ${SELECTED_COMPONENTS[fd]} -eq 1 ]] && echo "✓ fd installed"
[[ ${SELECTED_COMPONENTS[lazygit]} -eq 1 ]] && echo "✓ lazygit installed"
echo "✓ Oh My Zsh configured"
echo "✓ Zsh plugins installed (autosuggestions, syntax-highlighting)"
echo "✓ Spaceship prompt theme installed"
echo "✓ Tmux plugin manager installed"
echo "✓ Config files symlinked from $REPO_DIR"
echo "✓ Claude Code skill 'second-brain-sync' symlinked"
echo "✓ Git identity configured"
echo "✓ Tmux plugins installed"
[[ ${SELECTED_COMPONENTS[nvim]} -eq 1 ]] && echo "✓ Neovim plugins installed"
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
echo "Next steps:"
echo "1. Start a new shell or run: exec \$SHELL"
[[ ${SELECTED_COMPONENTS[docker]} -eq 1 ]] && echo "2. For Docker, run: newgrp docker (to avoid needing sudo)"
[[ ${SELECTED_COMPONENTS[gh]} -eq 1 ]] && echo "3. Authenticate with GitHub: gh auth login"
echo "4. Add your SSH keys to ~/.ssh/ if needed"
echo ""
