#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Some sudoers configs (used by "sudo ./install.sh", see USAGE.md) reset $HOME
# to the target user's home (root), which would symlink every dotfile into
# /root instead of the real user's home. Resolve the invoking user's real home.
if [[ -n "${SUDO_USER:-}" && "$EUID" -eq 0 ]]; then
    REAL_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    [[ -n "$REAL_HOME" ]] && HOME="$REAL_HOME"
fi

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

usage() {
    cat <<EOF
Usage: ./install.sh [options]

Options:
  --dry-run            Print what would change (links, installs, plugin/skill
                       reconciliation, Codex config render) without doing it.
                       Implies --harness-only
  --harness-only       Skip system packages, Oh My Zsh, tmux, git identity and
                       shell change; only link configs and set up the AI
                       harnesses (Claude Code, Codex, OpenCode)
  --with=a,b           Force-select components (e.g. --with=codex,opencode)
  --without=a,b        Force-deselect components (e.g. --without=claudeskills)
  -h, --help           Show this help
EOF
}

DRY_RUN=0
HARNESS_ONLY=0
FORCE_WITH=""
FORCE_WITHOUT=""
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --harness-only) HARNESS_ONLY=1 ;;
        --with=*) FORCE_WITH="${arg#--with=}" ;;
        --without=*) FORCE_WITHOUT="${arg#--without=}" ;;
        -h|--help) usage; exit 0 ;;
        *) log_error "Unknown option: $arg"; usage; exit 1 ;;
    esac
done

# Run a command, or only print it under --dry-run.
run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        echo -e "${YELLOW}[dry-run]${NC} $*"
    else
        "$@"
    fi
}

# Run a command as the invoking user when the script runs under sudo, so files
# created in $HOME (harness configs, npm prefix, plugin caches) aren't owned by
# root. Honors --dry-run.
as_user() {
    if [[ -n "${SUDO_USER:-}" && "$EUID" -eq 0 ]]; then
        run sudo -u "$SUDO_USER" -H env PATH="$PATH" "$@"
    else
        run "$@"
    fi
}

# command -v, ignoring Windows binaries exposed through WSL interop (/mnt/c/...):
# those can't read the Linux $HOME configs this script sets up.
has_native_cmd() {
    local path
    path="$(command -v "$1" 2>/dev/null)" || return 1
    [[ "$path" != /mnt/* ]]
}

if [[ $DRY_RUN -eq 1 ]]; then
    # The system-setup section (apt, curl installers, git clones) isn't dry-run
    # aware, so a dry run only covers the links and the AI harness setup.
    HARNESS_ONLY=1
    log_warn "Dry run (implies --harness-only): nothing will be changed"
fi
log_info "Starting dotfiles installation from $REPO_DIR"

# Check if running as root or with sudo
SUDO_CMD=""
if [[ $EUID -ne 0 ]]; then
    SUDO_CMD="sudo"
fi

# ===== Install system dependencies =====
if [[ $HARNESS_ONLY -eq 0 ]] && ! command -v apt-get &> /dev/null; then
    log_error "apt not found. This script supports Ubuntu/Debian systems only."
    exit 1
fi

# Base packages (always required; jq is used by the Claude plugin reconciliation
# and the statusline/hooks)
REQUIRED_PACKAGES=(git curl zsh tmux build-essential jq)

# Optional components
declare -A OPTIONAL_COMPONENTS=(
    [node]="Node.js (required for nvim treesitter)"
    [python]="Python 3.12 (dev environment)"
    [docker]="Docker (containerization)"
    [gh]="GitHub CLI (gh)"
    [vscode]="Visual Studio Code (editor)"
    [eim]="Espressif EIM (ESP-IDF Installation Manager, CLI)"
    [claudeskills]="Claude Code plugins (from settings.json) + skills in ~/.agents/skills"
    [codex]="OpenAI Codex CLI (npm, ~/.local) + ~/.codex config"
    [opencode]="OpenCode CLI (npm, ~/.local) + ~/.config/opencode config"
    [ecc]="ECC pieces vendored in vendor/ecc (skills, agents, language rules) + local C/Make/CMake rules"
    [nvim]="Neovim + LazyVim config"
    [ripgrep]="ripgrep (fast search, used by nvim Telescope)"
    [fd]="fd (fast file finder, used by nvim Telescope)"
    [lazygit]="lazygit (git UI, used by nvim plugin)"
    [shellcheck]="shellcheck (shell script linter, used by make lint)"
    [yazi]="yazi (terminal file manager)"
    [usbip]="usbip client (attach USB devices shared by usbipd-win from Windows)"
)

# Packages for each optional component
declare -A COMPONENT_PACKAGES=(
    [node]="nodejs npm"
    [python]="python3.12 python3.12-venv python3.12-dev python3-pip"
    [ripgrep]="ripgrep"
    [fd]="fd-find"
)

# Track selected components (default: node, python, gh, vscode selected)
declare -A SELECTED_COMPONENTS=(
    [node]=1
    [python]=1
    [docker]=0
    [gh]=1
    [vscode]=1
    [eim]=1
    [claudeskills]=1
    [codex]=0
    [opencode]=0
    [ecc]=0
    [nvim]=0
    [ripgrep]=0
    [fd]=0
    [lazygit]=0
    [shellcheck]=0
    [yazi]=0
    [usbip]=0
)

# System-wide vs current-user-only install scope for non-apt tools (Neovim, lazygit, fd)
# apt packages are always system-wide regardless (no per-user install mode in apt)
SYSTEM_WIDE=1

# Interactive selection with keyboard navigation
select_components() {
    if ! is_interactive; then
        log_info "Running non-interactively. Installing default components: node, python, gh, vscode, eim, claudeskills (system-wide install: enabled)"
        SELECTED_COMPONENTS[node]=1
        SELECTED_COMPONENTS[python]=1
        SELECTED_COMPONENTS[gh]=1
        SELECTED_COMPONENTS[vscode]=1
        SELECTED_COMPONENTS[eim]=1
        SELECTED_COMPONENTS[claudeskills]=1
        return
    fi

    local -a options=(systemwide node python docker gh vscode eim claudeskills codex opencode ecc nvim yazi ripgrep fd lazygit shellcheck usbip)
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

            if [[ "$comp" == "systemwide" ]]; then
                local checked=" "
                [[ $SYSTEM_WIDE -eq 1 ]] && checked="✓"
                echo -e "${highlight}  ${marker} [$checked] System-wide install - Neovim/lazygit/fd install to /opt & /usr/local/bin for all users (unchecked = current user only, ~/.local)\033[0m"
            else
                local checked=" "
                [[ ${SELECTED_COMPONENTS[$comp]} -eq 1 ]] && checked="✓"
                echo -e "${highlight}  ${marker} [$checked] ${comp} - ${OPTIONAL_COMPONENTS[$comp]}\033[0m"
            fi
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
                if [[ "$comp" == "systemwide" ]]; then
                    SYSTEM_WIDE=$((1 - SYSTEM_WIDE))
                else
                    SELECTED_COMPONENTS[$comp]=$((1 - SELECTED_COMPONENTS[$comp]))
                fi
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

if [[ $HARNESS_ONLY -eq 1 ]]; then
    # Only the harness-related components make sense without system setup.
    for comp in "${!SELECTED_COMPONENTS[@]}"; do
        [[ "$comp" == claudeskills || "$comp" == ecc ]] || SELECTED_COMPONENTS[$comp]=0
    done
    log_info "Harness-only mode: skipping system packages, shell, tmux and editor setup"
else
    select_components
fi

# --with / --without override both the defaults and the interactive selection
IFS=',' read -r -a _force_with <<< "$FORCE_WITH"
IFS=',' read -r -a _force_without <<< "$FORCE_WITHOUT"
for comp in "${_force_with[@]}" "${_force_without[@]}"; do
    [[ -z "$comp" ]] && continue
    if [[ -z "${OPTIONAL_COMPONENTS[$comp]+x}" ]]; then
        log_error "Unknown component: $comp (known: ${!OPTIONAL_COMPONENTS[*]})"
        exit 1
    fi
done
for comp in "${_force_with[@]}"; do [[ -n "$comp" ]] && SELECTED_COMPONENTS[$comp]=1; done
for comp in "${_force_without[@]}"; do [[ -n "$comp" ]] && SELECTED_COMPONENTS[$comp]=0; done
unset _force_with _force_without

if [[ $HARNESS_ONLY -eq 0 ]]; then
log_info "Checking and installing system dependencies..."

if [[ $SYSTEM_WIDE -eq 1 ]]; then
    log_info "Install scope: system-wide (tools go to /opt, /usr/local/bin)"
else
    log_info "Install scope: current-user only for Neovim/lazygit/fd (~/.local); apt packages remain system-wide (Linux package managers have no per-user install mode)"
fi

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
    # shellcheck disable=SC2206 # intentional word split of the package list
    ALL_PACKAGES+=(${COMPONENT_PACKAGES[node]})
fi

if [[ ${SELECTED_COMPONENTS[python]} -eq 1 ]]; then
    log_info "Python 3.12 selected"
    # shellcheck disable=SC2206 # intentional word split of the package list
    ALL_PACKAGES+=(${COMPONENT_PACKAGES[python]})
fi

if [[ ${SELECTED_COMPONENTS[ripgrep]} -eq 1 ]]; then
    log_info "ripgrep selected"
    # shellcheck disable=SC2206 # intentional word split of the package list
    ALL_PACKAGES+=(${COMPONENT_PACKAGES[ripgrep]})
fi

if [[ ${SELECTED_COMPONENTS[fd]} -eq 1 ]]; then
    log_info "fd selected"
    # shellcheck disable=SC2206 # intentional word split of the package list
    ALL_PACKAGES+=(${COMPONENT_PACKAGES[fd]})
fi

if [[ ${SELECTED_COMPONENTS[yazi]} -eq 1 ]]; then
    log_info "yazi selected"
    UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "0")
    if [[ $(echo "$UBUNTU_VERSION >= 24.04" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
        ALL_PACKAGES+=("yazi")
    else
        ALL_PACKAGES+=("cargo")
    fi
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
        if [[ $SYSTEM_WIDE -eq 1 ]]; then
            log_info "Creating symlink for fd (fdfind -> /usr/local/bin/fd)"
            $SUDO_CMD ln -sf "$(which fdfind)" /usr/local/bin/fd
        else
            log_info "Creating symlink for fd (fdfind -> ~/.local/bin/fd)"
            mkdir -p "$HOME/.local/bin"
            ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
        fi
    fi
fi

# Install yazi via cargo if selected and not present (Ubuntu < 24.04 fallback)
if [[ ${SELECTED_COMPONENTS[yazi]} -eq 1 ]] && ! command -v yazi &> /dev/null; then
    UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "0")
    if [[ $(echo "$UBUNTU_VERSION < 24.04" | bc -l 2>/dev/null || echo 1) -eq 1 ]]; then
        log_info "Installing yazi via cargo..."
        source "$HOME/.cargo/env" 2>/dev/null || true
        if [[ $SYSTEM_WIDE -eq 1 ]]; then
            cargo install --git https://github.com/sxyazi/yazi.git yazi
        else
            cargo install --git https://github.com/sxyazi/yazi.git yazi --root "$HOME/.local"
        fi
    fi
fi

# Install Neovim if selected
if [[ ${SELECTED_COMPONENTS[nvim]} -eq 1 ]] && ! command -v nvim &> /dev/null; then
    log_info "Installing Neovim..."
    NVIM_VERSION=$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)
    NVIM_URL="https://github.com/neovim/neovim/releases/download/$NVIM_VERSION/nvim-linux-x86_64.tar.gz"

    if [[ $SYSTEM_WIDE -eq 1 ]]; then
        if [[ ! -d /opt/nvim-linux-x86_64 ]]; then
            $SUDO_CMD mkdir -p /opt/nvim-linux-x86_64
            curl -sL "$NVIM_URL" | $SUDO_CMD tar xzf - -C /opt/ --strip-components=1 -C /opt/nvim-linux-x86_64 2>/dev/null || \
            (curl -sL "$NVIM_URL" | tar xzf - && $SUDO_CMD mv nvim-linux-x86_64/* /opt/nvim-linux-x86_64/ && rm -rf nvim-linux-x86_64)
        fi

        # Symlink to PATH
        $SUDO_CMD ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim 2>/dev/null || true
    else
        NVIM_INSTALL_DIR="$HOME/.local/opt/nvim-linux-x86_64"
        mkdir -p "$HOME/.local/bin"
        if [[ ! -d "$NVIM_INSTALL_DIR" ]]; then
            mkdir -p "$NVIM_INSTALL_DIR"
            curl -sL "$NVIM_URL" | tar xzf - -C "$NVIM_INSTALL_DIR" --strip-components=1
        fi
        ln -sf "$NVIM_INSTALL_DIR/bin/nvim" "$HOME/.local/bin/nvim" 2>/dev/null || true
        log_warn "Installed nvim to ~/.local/bin — ensure it's on your PATH"
    fi
fi

# Install lazygit if selected and not present
if [[ ${SELECTED_COMPONENTS[lazygit]} -eq 1 ]] && ! command -v lazygit &> /dev/null; then
    log_info "Installing lazygit..."
    LAZYGIT_VERSION=$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)
    LAZYGIT_URL="https://github.com/jesseduffield/lazygit/releases/download/$LAZYGIT_VERSION/lazygit_${LAZYGIT_VERSION#v}_Linux_x86_64.tar.gz"

    if [[ ! -d /tmp/lazygit ]]; then
        mkdir -p /tmp/lazygit
        curl -sL "$LAZYGIT_URL" | tar xzf - -C /tmp/lazygit
        if [[ $SYSTEM_WIDE -eq 1 ]]; then
            $SUDO_CMD install -m 755 /tmp/lazygit/lazygit /usr/local/bin/lazygit
        else
            mkdir -p "$HOME/.local/bin"
            install -m 755 /tmp/lazygit/lazygit "$HOME/.local/bin/lazygit"
        fi
        rm -rf /tmp/lazygit
    fi
fi

# Install shellcheck if selected and not present: apt first, then the official
# static release binary into ~/.local/bin when apt/sudo isn't usable.
if [[ ${SELECTED_COMPONENTS[shellcheck]} -eq 1 ]] && ! command -v shellcheck &> /dev/null; then
    log_info "Installing shellcheck..."
    if { [[ $EUID -eq 0 ]] || sudo -n true 2>/dev/null || is_interactive; } && \
        $SUDO_CMD apt-get install -y shellcheck; then
        log_info "shellcheck installed via apt"
    else
        log_warn "apt install of shellcheck failed or no sudo; falling back to the GitHub release binary"
        case "$(uname -m)" in
            x86_64) SC_ARCH="x86_64" ;;
            aarch64|arm64) SC_ARCH="aarch64" ;;
            *) SC_ARCH="" ;;
        esac
        SC_VERSION=$(curl -s https://api.github.com/repos/koalaman/shellcheck/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)
        if [[ -n "$SC_ARCH" && -n "$SC_VERSION" ]]; then
            SC_TMP="$(mktemp -d)"
            if curl -fsSL "https://github.com/koalaman/shellcheck/releases/download/$SC_VERSION/shellcheck-$SC_VERSION.linux.$SC_ARCH.tar.xz" | tar xJf - -C "$SC_TMP"; then
                mkdir -p "$HOME/.local/bin"
                install -m 755 "$SC_TMP/shellcheck-$SC_VERSION/shellcheck" "$HOME/.local/bin/shellcheck"
                [[ -n "${SUDO_USER:-}" && "$EUID" -eq 0 ]] && chown "$SUDO_USER": "$HOME/.local/bin/shellcheck"
                log_info "shellcheck $SC_VERSION installed to ~/.local/bin"
            else
                log_warn "shellcheck download failed; install it manually (https://github.com/koalaman/shellcheck#installing)"
            fi
            rm -rf "$SC_TMP"
        else
            log_warn "Unsupported arch $(uname -m) or GitHub API unreachable; install shellcheck manually"
        fi
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

# Install Visual Studio Code if selected and not present
if [[ ${SELECTED_COMPONENTS[vscode]} -eq 1 ]] && ! command -v code &> /dev/null; then
    log_info "Installing Visual Studio Code..."
    command -v gpg &> /dev/null || $SUDO_CMD apt-get install -y gnupg
    $SUDO_CMD mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | $SUDO_CMD tee /etc/apt/keyrings/packages.microsoft.gpg > /dev/null
    $SUDO_CMD chmod go+r /etc/apt/keyrings/packages.microsoft.gpg
    echo "Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Signed-By: /etc/apt/keyrings/packages.microsoft.gpg
Components: main" | $SUDO_CMD tee /etc/apt/sources.list.d/vscode.sources > /dev/null
    $SUDO_CMD apt-get update
    $SUDO_CMD apt-get install -y code
fi

# Install usbip client (for attaching USB devices shared by usbipd-win on Windows)
if [[ ${SELECTED_COMPONENTS[usbip]} -eq 1 ]] && ! command -v usbip &> /dev/null; then
    log_info "Installing usbip client..."
    $SUDO_CMD apt-get install -y linux-tools-generic 2>/dev/null || log_warn "linux-tools-generic install failed"
    USBIP_BIN=$(find /usr/lib/linux-tools/*-generic -name usbip 2>/dev/null | head -1)
    if [[ -n "$USBIP_BIN" ]]; then
        $SUDO_CMD update-alternatives --install /usr/local/bin/usbip usbip "$USBIP_BIN" 20
        log_info "usbip client installed"
    else
        log_warn "usbip binary not found under /usr/lib/linux-tools/*-generic after install — check manually"
    fi
fi

# Install Espressif EIM (ESP-IDF Installation Manager) and provision ESP-IDF if selected
EIM_PROVISIONED=0
if [[ ${SELECTED_COMPONENTS[eim]} -eq 1 ]]; then
    if ! command -v eim &> /dev/null; then
        log_info "Installing Espressif EIM (ESP-IDF Installation Manager)..."
        $SUDO_CMD install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://dl.espressif.com/dl/eim/eim.gpg | $SUDO_CMD tee /etc/apt/keyrings/eim.gpg > /dev/null
        $SUDO_CMD chmod 0644 /etc/apt/keyrings/eim.gpg
        curl -fsSL https://dl.espressif.com/dl/eim/eim.sources | $SUDO_CMD tee /etc/apt/sources.list.d/espressif.sources > /dev/null
        $SUDO_CMD apt-get update
        $SUDO_CMD apt-get install -y eim-cli
    fi

    if command -v eim &> /dev/null; then
        log_info "Running ESP-IDF provisioning via EIM..."
        EIM_CONFIG_SOURCE="$REPO_DIR/eim/eim_config-linux.toml"

        if [[ -f "$EIM_CONFIG_SOURCE" ]]; then
            EIM_CONFIG_TEMP="$(mktemp /tmp/eim_config.XXXXXX.toml)"
            sed "s|__HOME__|$HOME|g" "$EIM_CONFIG_SOURCE" > "$EIM_CONFIG_TEMP"

            if eim install --config "$EIM_CONFIG_TEMP"; then
                log_info "ESP-IDF provisioned successfully"
                EIM_PROVISIONED=1
            else
                log_warn "EIM provisioning failed"
            fi

            rm -f "$EIM_CONFIG_TEMP"
        else
            log_warn "EIM config not found at $EIM_CONFIG_SOURCE"
        fi
    else
        log_warn "eim command not found. You may need to restart your shell and run: eim install --config $REPO_DIR/eim/eim_config-linux.toml"
    fi
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

fi # end of system setup (skipped with --harness-only)

# ===== Backup existing configs =====
log_info "Creating backup of existing configs..."
run mkdir -p "$BACKUP_DIR"

CONFIG_ITEMS=(
    "$HOME/.zshrc"
    "$HOME/.tmux.conf"
    "$HOME/.config/nvim"
    "$HOME/.gitconfig"
    "$HOME/.config/git/ignore"
    "$HOME/.claude/settings.json"
    "$HOME/.claude/CLAUDE.md"
    "$HOME/.claude/statusline.sh"
    "$HOME/.claude/hooks"
    "$HOME/.claude/skills/second-brain-sync"
    "$HOME/.agents/skills/second-brain-sync"
    "$HOME/.codex/config.toml"
    "$HOME/.codex/yolo.config.toml"
    "$HOME/.codex/AGENTS.md"
    "$HOME/.codex/rules/dotfiles.rules"
    "$HOME/.claude/rules/ecc"
    "$HOME/.claude/rules/local"
    "$HOME/.config/opencode/opencode.json"
    "$HOME/.config/opencode/AGENTS.md"
)

# Keep the path relative to $HOME inside the backup, so same-named files
# (~/.codex/AGENTS.md, ~/.config/opencode/AGENTS.md) don't overwrite each other.
for item in "${CONFIG_ITEMS[@]}"; do
    if [[ -e "$item" || -L "$item" ]]; then
        log_warn "Backing up $item"
        rel="${item#"$HOME"/}"
        run mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
        run cp -r "$item" "$BACKUP_DIR/$rel"
    fi
done

# Move something out of the way into the backup dir (used for legacy,
# hand-installed skills that are now managed by a plugin or the skills CLI).
move_to_backup() {
    local item="$1" rel
    rel="${item#"$HOME"/}"
    log_warn "Moving $item to $BACKUP_DIR/$rel"
    run mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    run mv "$item" "$BACKUP_DIR/$rel"
}

# ===== Create symlinks =====
log_info "Creating symlinks..."

# Symlink with fallback to copy if the filesystem doesn't support symlinks
create_config_link() {
    local source="$1" target="$2"
    if [[ ! -e "$source" && $DRY_RUN -eq 0 ]]; then
        log_warn "Source not found: $source"
        return
    fi
    if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
        return
    fi
    as_user mkdir -p "$(dirname "$target")"
    as_user rm -rf "$target"
    if as_user ln -sf "$source" "$target" 2>/dev/null; then
        [[ $DRY_RUN -eq 1 ]] || log_info "Symlinked $target"
    else
        log_warn "Symlink failed, copying instead: $target"
        as_user cp -r "$source" "$target"
    fi
}

# Skills live canonically in ~/.agents/skills (read by Codex and OpenCode);
# Claude Code only reads ~/.claude/skills, so shared skills get a link there.
link_shared_skill() {
    local name="$1" source="$2"
    create_config_link "$source" "$HOME/.agents/skills/$name"
    create_config_link "$HOME/.agents/skills/$name" "$HOME/.claude/skills/$name"
}

create_config_link "$REPO_DIR/zsh/.zshrc" "$HOME/.zshrc"
create_config_link "$REPO_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"

# nvim (entire directory) — only if nvim selected
if [[ ${SELECTED_COMPONENTS[nvim]} -eq 1 ]]; then
    create_config_link "$REPO_DIR/nvim" "$HOME/.config/nvim"
fi

create_config_link "$REPO_DIR/git/.gitconfig" "$HOME/.gitconfig"
create_config_link "$REPO_DIR/git/ignore" "$HOME/.config/git/ignore"
create_config_link "$REPO_DIR/claude/settings.json" "$HOME/.claude/settings.json"
create_config_link "$REPO_DIR/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
create_config_link "$REPO_DIR/claude/statusline.sh" "$HOME/.claude/statusline.sh"
create_config_link "$REPO_DIR/claude/hooks" "$HOME/.claude/hooks"

# second-brain-sync skill lives in the obsidian_vault repo itself, not here
# (keeps the skill's source versioned alongside the vault it manages). It is
# shared by the 3 harnesses: ~/.agents/skills/second-brain-sync -> vault, and
# ~/.claude/skills/second-brain-sync -> ~/.agents/skills/second-brain-sync.
VAULT_DIR="$HOME/obsidian_vault"
if [[ ! -d "$VAULT_DIR/.git" ]]; then
    log_info "Cloning obsidian_vault (second-brain-sync skill source)..."
    as_user git clone https://github.com/FlavianMF/obisidian_vault.git "$VAULT_DIR"
fi
link_shared_skill second-brain-sync "$VAULT_DIR/00_META/skills/second-brain-sync"

# ===== AI harnesses: Claude Code plugins + skills, Codex, OpenCode =====
# Declarative, not symlinked where the tool keeps machine state:
# installed_plugins.json/.skill-lock.json carry absolute paths and machine
# metadata, and Codex rewrites its own config.toml. So plugins are reconciled
# from claude/settings.json, skills are replayed with the skills CLI, and the
# Codex config is rendered from codex/config.base.toml. Idempotent.
HARNESS_CHECKLIST=()

# claude, npx, codex and opencode are typically user-local (~/.local/bin, nvm's
# node bin dir) and invisible to sudo's secure_path — prepend them.
export PATH="$HOME/.local/bin:$PATH"
NVM_NODE_BIN="$(find "$HOME/.nvm/versions/node" -maxdepth 2 -type d -name bin 2>/dev/null | sort -V | tail -1 || true)"
[[ -n "$NVM_NODE_BIN" ]] && export PATH="$NVM_NODE_BIN:$PATH"

NODE_OK=0
if command -v npx >/dev/null 2>&1; then
    NODE_MAJOR="$(node -v 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/')"
    [[ -n "$NODE_MAJOR" && "$NODE_MAJOR" -ge 20 ]] && NODE_OK=1
fi

# Pinned so a skills CLI release can't silently change the install layout.
SKILLS_CLI="skills@1.5.18"
skills_add() {
    as_user npx -y "$SKILLS_CLI" add "$@" -g -y || log_warn "npx $SKILLS_CLI add $1 failed"
}

# --- Codex / OpenCode binaries (components off by default) ---
install_npm_cli() {
    local bin="$1" pkg="$2"
    if has_native_cmd "$bin"; then
        log_info "$bin already installed ($(command -v "$bin")), skipping"
        return
    fi
    if ! command -v npm >/dev/null 2>&1; then
        log_warn "npm not found; install Node (component node, or nvm) and rerun to get $bin"
        return
    fi
    log_info "Installing $bin ($pkg) into ~/.local..."
    as_user npm install -g --prefix "$HOME/.local" "$pkg" || log_warn "npm install $pkg failed"
}

[[ ${SELECTED_COMPONENTS[codex]} -eq 1 ]] && install_npm_cli codex @openai/codex
[[ ${SELECTED_COMPONENTS[opencode]} -eq 1 ]] && install_npm_cli opencode opencode-ai

CODEX_ACTIVE=0
if [[ ${SELECTED_COMPONENTS[codex]} -eq 1 ]] || has_native_cmd codex || [[ -d "$HOME/.codex" ]]; then
    CODEX_ACTIVE=1
fi
OPENCODE_ACTIVE=0
if [[ ${SELECTED_COMPONENTS[opencode]} -eq 1 ]] || has_native_cmd opencode || [[ -d "$HOME/.config/opencode" ]]; then
    OPENCODE_ACTIVE=1
fi

# --- Claude Code plugins, reconciled from claude/settings.json ---
CLAUDE_SETTINGS="$REPO_DIR/claude/settings.json"
if [[ ${SELECTED_COMPONENTS[claudeskills]} -eq 1 ]]; then
    if has_native_cmd claude && command -v jq >/dev/null 2>&1; then
        log_info "Reconciling Claude Code plugins with claude/settings.json..."
        known_mkts="$(claude plugin marketplace list --json 2>/dev/null | jq -r '.[].name' 2>/dev/null || true)"
        while IFS=$'\t' read -r mkt_name mkt_src; do
            [[ -z "$mkt_name" || -z "$mkt_src" ]] && continue
            grep -qxF "$mkt_name" <<< "$known_mkts" && continue
            log_info "Adding marketplace $mkt_name ($mkt_src)"
            as_user claude plugin marketplace add "$mkt_src" < /dev/null || log_warn "marketplace add $mkt_src failed"
        done < <(
            printf 'claude-plugins-official\tanthropics/claude-plugins-official\n'
            jq -r '.extraKnownMarketplaces // {} | to_entries[]
                   | [.key, (.value.source.repo // .value.source.url // .value.source.path // "")] | @tsv' "$CLAUDE_SETTINGS"
        )
        # `marketplace add` rewrites settings.json (the repo file) and drops
        # autoUpdate; versions are pinned on purpose, so put it back.
        if [[ $DRY_RUN -eq 0 ]] && jq -e '.extraKnownMarketplaces // {} | any(.[]; .autoUpdate != false)' "$CLAUDE_SETTINGS" >/dev/null; then
            log_info "Restoring autoUpdate:false on declared marketplaces"
            settings_tmp="$(mktemp)"
            jq '.extraKnownMarketplaces |= with_entries(.value.autoUpdate = false)' "$CLAUDE_SETTINGS" > "$settings_tmp" \
                && cat "$settings_tmp" > "$CLAUDE_SETTINGS"
            rm -f "$settings_tmp"
        fi

        installed_plugins="$(claude plugin list --json 2>/dev/null | jq -r '.[].id' 2>/dev/null || true)"
        # Declared = every key in enabledPlugins. `false` means installed but off at
        # user scope (enabled per project, e.g. ecc@ecc via claude/ecc-project.sh).
        declared_plugins="$(jq -r '.enabledPlugins // {} | keys[]' "$CLAUDE_SETTINGS")"
        disabled_plugins="$(jq -r '.enabledPlugins // {} | to_entries[] | select(.value == false) | .key' "$CLAUDE_SETTINGS")"
        while read -r plugin_id; do
            [[ -z "$plugin_id" ]] && continue
            grep -qxF "$plugin_id" <<< "$installed_plugins" && continue
            log_info "Installing plugin $plugin_id"
            as_user claude plugin install "$plugin_id" -y < /dev/null || log_warn "plugin install $plugin_id failed"
        done <<< "$declared_plugins"
        # install enables at user scope (and rewrites settings.json, which is the repo
        # file); put declared-off plugins back to false.
        while read -r plugin_id; do
            [[ -z "$plugin_id" ]] && continue
            [[ "$(jq -r --arg p "$plugin_id" '.enabledPlugins[$p]' "$CLAUDE_SETTINGS")" == false ]] && continue
            log_info "Disabling plugin $plugin_id at user scope (declared false)"
            as_user claude plugin disable "$plugin_id" -s user < /dev/null || log_warn "plugin disable $plugin_id failed"
        done <<< "$disabled_plugins"
        while read -r plugin_id; do
            [[ -z "$plugin_id" ]] && continue
            grep -qxF "$plugin_id" <<< "$declared_plugins" && continue
            log_warn "Plugin $plugin_id is installed but not enabled in claude/settings.json (declare it there or: claude plugin uninstall $plugin_id)"
        done <<< "$installed_plugins"

        # impeccable used to be hand-copied into ~/.claude (skill + 4 agents);
        # now it comes from the impeccable@impeccable plugin, so retire the copies
        # once the plugin is in place to avoid a duplicate skill.
        if [[ $DRY_RUN -eq 1 ]] || claude plugin list --json 2>/dev/null | jq -e '.[] | select(.id == "impeccable@impeccable")' >/dev/null 2>&1; then
            if [[ -d "$HOME/.claude/skills/impeccable" && ! -L "$HOME/.claude/skills/impeccable" ]]; then
                move_to_backup "$HOME/.claude/skills/impeccable"
            fi
            for agent_file in "$HOME"/.claude/agents/impeccable-*.md; do
                [[ -f "$agent_file" && ! -L "$agent_file" ]] && move_to_backup "$agent_file"
            done
        fi
    else
        log_warn "claude CLI or jq not found (checked PATH incl. ~/.local/bin), skipping plugin reconciliation"
    fi

    # --- Skills (canonical dir ~/.agents/skills) ---
    if [[ $NODE_OK -eq 1 ]]; then
        # Hand-copied skill dirs in ~/.claude/skills that the skills CLI now owns:
        # move them aside so the CLI can install the canonical copy + link.
        LEGACY_SKILL_DIRS=(llm-council)
        for legacy in "${LEGACY_SKILL_DIRS[@]}"; do
            if [[ -d "$HOME/.claude/skills/$legacy" && ! -L "$HOME/.claude/skills/$legacy" ]]; then
                move_to_backup "$HOME/.claude/skills/$legacy"
            fi
        done

        log_info "Installing shared skills (Claude Code + Codex + OpenCode)..."
        skills_add Leonxlnx/taste-skill --skill '*' -a claude-code codex opencode
        skills_add vercel-labs/skills --skill find-skills -a claude-code codex opencode
        skills_add tenfoldmarc/llm-council-skill --skill llm-council -a claude-code codex opencode

        # Skills Claude Code already gets from its plugins: install the upstream
        # skills-CLI equivalent for Codex/OpenCode only. They land in
        # ~/.agents/skills without a ~/.claude/skills link, so Claude doesn't load
        # them twice.
        if [[ $CODEX_ACTIVE -eq 1 || $OPENCODE_ACTIVE -eq 1 ]]; then
            log_info "Installing Codex/OpenCode equivalents of Claude plugin skills..."
            skills_add pbakaus/impeccable --skill impeccable -a codex opencode
            skills_add mattpocock/skills --skill diagnosing-bugs tdd prototype research domain-modeling \
                codebase-design code-review wizard grilling writing-for-agents -a codex opencode
            skills_add JuliusBrussee/caveman --skill caveman caveman-commit caveman-review caveman-compress \
                caveman-help caveman-stats cavecrew -a codex opencode
            skills_add figma/mcp-server-guide --skill '*' -a codex opencode
            skills_add typesafe-ai/skills --skill typesafe-ai -a codex opencode
        fi
    else
        log_warn "Node >=20 required by the skills CLI (found $(node -v 2>/dev/null || echo none)); skipping npx skills add. Install a newer Node (e.g. nvm) and rerun."
    fi

    # ~/.claude/skills should only hold links into ~/.agents/skills (synced/ is
    # managed by Claude itself).
    for entry in "$HOME"/.claude/skills/*; do
        [[ -e "$entry" || -L "$entry" ]] || continue
        [[ "$(basename "$entry")" == synced ]] && continue
        [[ -L "$entry" ]] && continue
        log_warn "Unmanaged skill dir $entry (not a link into ~/.agents/skills); move it to ~/.agents/skills or install it with npx skills add"
    done
fi

# --- ECC pieces (vendor/ecc, pinned; see vendor/ecc/SOURCE.md) ---
if [[ ${SELECTED_COMPONENTS[ecc]} -eq 1 ]]; then
    log_info "Linking vendored ECC skills, agents and rules..."
    # Skills: canonical in ~/.agents/skills (Codex, OpenCode) + link for Claude.
    for skill_dir in "$REPO_DIR"/vendor/ecc/skills/*/; do
        link_shared_skill "$(basename "$skill_dir")" "${skill_dir%/}"
    done
    # Agents: Claude Code format. Codex has no agent-file equivalent (skills only).
    for agent_file in "$REPO_DIR"/vendor/ecc/agents/*.md; do
        create_config_link "$agent_file" "$HOME/.claude/agents/ecc-$(basename "$agent_file")"
    done
    # Path-scoped rules: only load when Claude reads a matching file.
    create_config_link "$REPO_DIR/vendor/ecc/rules" "$HOME/.claude/rules/ecc"
    create_config_link "$REPO_DIR/claude/rules" "$HOME/.claude/rules/local"
    if [[ $OPENCODE_ACTIVE -eq 1 ]]; then
        # OpenCode rejects Claude's agent frontmatter (tools/model), so it gets
        # converted copies instead of links; only changed files are rewritten.
        if [[ $DRY_RUN -eq 1 ]]; then
            python3 "$REPO_DIR/opencode/render_agents.py" "$REPO_DIR/vendor/ecc/agents" \
                "$HOME/.config/opencode/agents" --prefix ecc- --dry-run
        else
            as_user python3 "$REPO_DIR/opencode/render_agents.py" "$REPO_DIR/vendor/ecc/agents" \
                "$HOME/.config/opencode/agents" --prefix ecc- || log_warn "OpenCode agent render failed"
        fi
    fi
fi

# --- Codex config ---
if [[ $CODEX_ACTIVE -eq 1 ]]; then
    log_info "Configuring Codex (~/.codex)..."
    if [[ $DRY_RUN -eq 1 ]]; then
        echo -e "${YELLOW}[dry-run]${NC} render $HOME/.codex/config.toml from codex/config.base.toml; diff:"
        codex_current="$HOME/.codex/config.toml"
        [[ -f "$codex_current" ]] || codex_current=/dev/null
        diff -u "$codex_current" \
            <(python3 "$REPO_DIR/codex/render_config.py" "$REPO_DIR/codex/config.base.toml" "$HOME/.codex/config.toml" --dry-run) || true
    else
        as_user mkdir -p "$HOME/.codex"
        if as_user python3 "$REPO_DIR/codex/render_config.py" "$REPO_DIR/codex/config.base.toml" "$HOME/.codex/config.toml"; then
            log_info "Rendered ~/.codex/config.toml (machine-only keys preserved; see: make codex-drift)"
        else
            log_warn "Codex config render failed"
        fi
    fi
    create_config_link "$REPO_DIR/codex/yolo.config.toml" "$HOME/.codex/yolo.config.toml"
    # Command deny list (execpolicy). Codex writes its own approvals to
    # ~/.codex/rules/default.rules, so ours lives in a separate file.
    create_config_link "$REPO_DIR/codex/dotfiles.rules" "$HOME/.codex/rules/dotfiles.rules"
    create_config_link "$REPO_DIR/agents/AGENTS.md" "$HOME/.codex/AGENTS.md"
    HARNESS_CHECKLIST+=(
        "Codex: codex login (conta ChatGPT)"
        "Codex: codex mcp login figma (OAuth do MCP do Figma)"
        "Codex: GitHub MCP usa PAT — preencha ~/dotfiles/secrets/github-mcp.env (ver .env.example)"
    )
fi

# --- OpenCode config ---
if [[ $OPENCODE_ACTIVE -eq 1 ]]; then
    log_info "Configuring OpenCode (~/.config/opencode)..."
    # OpenCode doesn't rewrite opencode.json at runtime, so a symlink is safe.
    create_config_link "$REPO_DIR/opencode/opencode.json" "$HOME/.config/opencode/opencode.json"
    create_config_link "$REPO_DIR/agents/AGENTS.md" "$HOME/.config/opencode/AGENTS.md"
    HARNESS_CHECKLIST+=(
        "OpenCode: opencode auth login (ou /connect no TUI) para o OpenCode Zen (modelo padrão opencode/big-pickle, grátis, exige conta)"
        "OpenCode: preencha OPENROUTER_API_KEY em ~/dotfiles/secrets/openrouter.env (ver .env.example)"
        "OpenCode: opencode mcp auth figma (OAuth do MCP do Figma)"
        "OpenCode: GitHub MCP usa PAT — preencha ~/dotfiles/secrets/github-mcp.env (ver .env.example)"
    )
fi

if [[ ${SELECTED_COMPONENTS[claudeskills]} -eq 1 ]]; then
    HARNESS_CHECKLIST+=(
        "Claude Code: /plugin -> figma: autenticar o MCP do Figma (OAuth) se ainda não fez"
        "Claude Code: plugin github usa GITHUB_PERSONAL_ACCESS_TOKEN de ~/dotfiles/secrets/github-mcp.env"
        "Claude Code: /status e conferir a statusline; claude plugin list --json deve bater com claude/settings.json"
    )
fi

if [[ $HARNESS_ONLY -eq 0 ]]; then
# ===== Configure git identity =====
if [[ ! -f "$HOME/.gitconfig.local" ]]; then
    log_info "Setting up git identity..."

    if is_interactive; then
        read -r -p "Enter your git user name: " git_name
        read -r -p "Enter your git email: " git_email
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

fi # end of git identity / plugins / shell setup (skipped with --harness-only)

# ===== Summary =====
echo ""
log_info "Installation complete!"
echo ""
echo "Summary:"
echo "=========="
if [[ $HARNESS_ONLY -eq 0 ]]; then
echo "✓ Install scope: $( [[ $SYSTEM_WIDE -eq 1 ]] && echo 'system-wide' || echo 'current-user (tools)' )"
echo "✓ System dependencies installed"
[[ ${SELECTED_COMPONENTS[node]} -eq 1 ]] && echo "✓ Node.js and npm installed"
[[ ${SELECTED_COMPONENTS[python]} -eq 1 ]] && echo "✓ Python 3.12 installed"
[[ ${SELECTED_COMPONENTS[docker]} -eq 1 ]] && echo "✓ Docker installed"
[[ ${SELECTED_COMPONENTS[gh]} -eq 1 ]] && echo "✓ GitHub CLI (gh) installed"
[[ ${SELECTED_COMPONENTS[vscode]} -eq 1 ]] && echo "✓ Visual Studio Code installed"
[[ ${SELECTED_COMPONENTS[eim]} -eq 1 ]] && echo "✓ Espressif EIM installed"
[[ $EIM_PROVISIONED -eq 1 ]] && echo "✓ ESP-IDF provisioned via EIM"
[[ ${SELECTED_COMPONENTS[nvim]} -eq 1 ]] && echo "✓ Neovim installed"
[[ ${SELECTED_COMPONENTS[ripgrep]} -eq 1 ]] && echo "✓ ripgrep installed"
[[ ${SELECTED_COMPONENTS[fd]} -eq 1 ]] && echo "✓ fd installed"
[[ ${SELECTED_COMPONENTS[lazygit]} -eq 1 ]] && echo "✓ lazygit installed"
[[ ${SELECTED_COMPONENTS[shellcheck]} -eq 1 ]] && echo "✓ shellcheck installed"
[[ ${SELECTED_COMPONENTS[yazi]} -eq 1 ]] && echo "✓ yazi installed"
[[ ${SELECTED_COMPONENTS[usbip]} -eq 1 ]] && echo "✓ usbip client installed"
echo "✓ Oh My Zsh configured"
echo "✓ Zsh plugins installed (autosuggestions, syntax-highlighting)"
echo "✓ Spaceship prompt theme installed"
echo "✓ Tmux plugin manager installed"
fi
echo "✓ Config files symlinked from $REPO_DIR"
echo "✓ Skill 'second-brain-sync' linked (~/.agents/skills + ~/.claude/skills)"
[[ ${SELECTED_COMPONENTS[claudeskills]} -eq 1 ]] && echo "✓ Claude Code plugins reconciled with claude/settings.json; skills in ~/.agents/skills"
[[ $CODEX_ACTIVE -eq 1 ]] && echo "✓ Codex configured (~/.codex/config.toml rendered, AGENTS.md linked)"
[[ ${SELECTED_COMPONENTS[ecc]} -eq 1 ]] && echo "✓ ECC skills/agents/rules linked (vendor/ecc @ c70874f)"
[[ $OPENCODE_ACTIVE -eq 1 ]] && echo "✓ OpenCode configured (~/.config/opencode/opencode.json + AGENTS.md linked)"
if [[ $HARNESS_ONLY -eq 0 ]]; then
echo "✓ Git identity configured"
echo "✓ Tmux plugins installed"
[[ ${SELECTED_COMPONENTS[nvim]} -eq 1 ]] && echo "✓ Neovim plugins installed"
fi
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
echo "Next steps:"
echo "1. Start a new shell or run: exec \$SHELL"
[[ ${SELECTED_COMPONENTS[docker]} -eq 1 ]] && echo "2. For Docker, run: newgrp docker (to avoid needing sudo)"
[[ ${SELECTED_COMPONENTS[gh]} -eq 1 ]] && echo "3. Authenticate with GitHub: gh auth login"
echo "4. Add your SSH keys to ~/.ssh/ if needed"
[[ ${SELECTED_COMPONENTS[usbip]} -eq 1 ]] && echo "5. On Windows, run: usbipd list / usbipd attach --wsl --busid <busid>"
echo ""
if [[ ${#HARNESS_CHECKLIST[@]} -gt 0 ]]; then
    echo "Manual checklist (AI harnesses):"
    for item in "${HARNESS_CHECKLIST[@]}"; do
        echo "  [ ] $item"
    done
    echo ""
fi
[[ $DRY_RUN -eq 1 ]] && log_warn "Dry run finished: nothing was changed"
exit 0
