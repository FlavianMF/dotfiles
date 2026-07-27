# dotfiles

Reproducible development environment configuration. Clone and run `install.sh` to set up:

- **Shell**: zsh + Oh My Zsh + spaceship-prompt
- **Editor**: Neovim (LazyVim)
- **Multiplexer**: tmux + Catppuccin theme + plugins
- **Tools**: git, GitHub CLI (gh), Docker
- **Claude Code**: settings with caveman plugin

## Quick Start

```bash
git clone <repo-url> ~/dotfiles
cd ~/dotfiles
./install.sh
```

The script will:
1. Install system dependencies via apt
2. Install Neovim, Docker, and GitHub CLI
3. Set up Oh My Zsh with plugins and spaceship theme
4. Install and configure tmux with TPM and plugins
5. Create symlinks to all configs from this repo
6. Prompt for git identity (user.name, user.email)
7. Install all Neovim and tmux plugins

## What's Included

| Component | Source | Notes |
|-----------|--------|-------|
| `.zshrc` | `zsh/` | Oh My Zsh config with custom aliases and exports |
| `.tmux.conf` | `tmux/` | Catppuccin mocha theme, vim-tmux-navigator, plugins |
| `nvim/` | Entire LazyVim config | init.lua, plugins, lazy-lock.json (74 plugins pinned) |
| `.gitconfig` | `git/` | Includes gh auth, excludes user.name/email (set locally) |
| `git/ignore` | Global gitignore (`.config/git/ignore`) | Excludes Claude local settings |
| `claude/settings.json` | Claude Code config | Model (Haiku), effort level, caveman plugin |

## What's NOT Included

These are intentionally excluded for security and machine-specific reasons:

- `.ssh/` — SSH keys (restore manually)
- `.docker/` — Docker credentials
- `.config/github-copilot/` — Copilot auth
- `.config/gh/hosts.yml` — GitHub auth tokens
- `.claude/.credentials.json` — Claude credentials
- `~/.local/share/nvim/` — Plugin installs (regenerated from `lazy-lock.json`)
- `.zsh_history`, `.bash_history` — Shell history
- All runtime/cache files

## Post-Installation

After running `install.sh`:

1. **Start a new shell or** `exec $SHELL` to reload configuration
2. **Restore SSH keys** to `~/.ssh/` manually
3. **Authenticate with GitHub**: `gh auth login`
4. **(Optional) Docker**: Run `newgrp docker` to avoid `sudo` for docker commands
5. **For zsh as default shell**: Script attempts `chsh -s $(which zsh)` (requires sudo)

## Git Identity

Git user name and email are stored in `~/.gitconfig.local` (not tracked in repo). The install script prompts for these values. To change later:

```bash
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

## Symlink Strategy

All configs are symlinked from this repo to your home directory. This means:

- **Changes in `~/.zshrc` etc. directly modify the repo** — always test before pushing
- Use `git status` to see what changed
- Backup is created at `~/.dotfiles-backup/<timestamp>/` before first installation

## Customization

Edit config files in the repo directory and they'll take effect immediately (next shell/app reload). For example:

```bash
# Edit nvim config
$EDITOR ~/dotfiles/nvim/lua/config/options.lua

# Edit tmux
$EDITOR ~/dotfiles/tmux/.tmux.conf
```

Then commit and push to keep your setup in sync across machines.

## Troubleshooting

### Docker installation fails
On Ubuntu 24.04, the install script may require sudo password. Ensure your user has sudoers access.

### Tmux plugins don't load
Run `prefix + I` inside tmux to install plugins manually (TPM should auto-install during setup).

### Neovim plugins missing
Inside nvim, run `:Lazy sync` to reinstall all plugins from `lazy-lock.json`.

### zsh doesn't use the config
Ensure symlink is correct: `readlink ~/.zshrc` should point to `<repo-path>/zsh/.zshrc`.

Start a fresh shell: `exec zsh`.

## System Requirements

- **OS**: Ubuntu 20.04 LTS or newer (uses `apt`)
- **Sudo access**: For system package installation and shell change

## Terminal Font

The zsh config expects **FiraCode Nerd Font Mono** for proper rendering of prompt symbols. Install it on your system or adjust `SPACESHIP_CHAR_SYMBOL` in `.zshrc`.

See `TERMINAL_FIX.md` for notes on terminal configuration.
