# Herdr

Terminal workspace manager and multiplexer purpose-built for AI coding agents (Claude Code, Codex, Antigravity, OpenCode, etc.).

## Install & Update

```bash
make herdr-install                    # Installs herdr pinned in herdr/VERSION + herdr/SHA256
make herdr-update [VERSION=x.y.z]     # Re-pin to latest (or specific version), update SHA256 and review diff
```

The executable is installed to `~/.local/bin/herdr` and the configuration is linked from `herdr/config.toml` to `~/.config/herdr/config.toml`.

## Key Features

- **Agent Detection:** Live state indicators in sidebar:
  - `working`: agent running a turn or tool
  - `blocked`: agent awaiting human input / confirmation
  - `done`: completed task
  - `idle` / `unknown`
- **Persistent Daemon:** Panes and sessions survive client disconnects and SSH drops.
- **Mouse & Keyboard:** Full clickable GUI (click panes, drag split borders, menus) + standard chords.
- **Theme:** Configured with Catppuccin Mocha to match `tmux` and `yazi`.

## Keybindings (Tmux-Compatible)

The configuration in `herdr/config.toml` uses the same bindings as your `tmux/.tmux.conf`:

| Action | Chord | Tmux Equivalent |
| :--- | :--- | :--- |
| **Prefix key** | `Ctrl+Space` (or `Ctrl+B`) | `set -g prefix C-Space` |
| **Reload config** | `prefix` + `r` | `bind r source-file ~/.tmux.conf` |
| **New tab (window)** | `prefix` + `c` | `bind c new-window` |
| **Next / Prev tab** | `prefix` + `n` / `prefix` + `p` (or `Alt+Shift+Right/Left`) | `bind -r n` / `bind -r p` |
| **Switch tab** | `prefix` + `1..9` | `select-window -t 1..9` |
| **Close tab** | `prefix` + `&` (or `prefix` + `Shift+x`) | `bind & kill-window` |
| **Split vertical (right)** | `prefix` + `v` | Split pane vertical |
| **Split horizontal (down)** | `prefix` + `-` | Split pane horizontal |
| **Pane navigation (Vim)** | `prefix` + `h` / `j` / `k` / `l` (or `Alt` + `h/j/k/l`) | Vim-tmux-navigator (`select-pane -L/-D/-U/-R`) |
| **Seamless Neovim nav** | `Ctrl+h` / `j` / `k` / `l` in Neovim | Seamless jump across Neovim splits and Herdr panes |
| **Cycle panes** | `prefix` + `Tab` / `prefix` + `Shift+Tab` | Cycle panes |
| **Resize panes (Vim)** | `prefix` + `H` / `J` / `K` / `L` (or `Alt+Shift+H/J/K/L`) | `bind -r H/J/K/L resize-pane 5` |
| **Resize mode (Modal)** | `prefix` + `Shift+R` | Modal repeatable resize (`h/j/k/l` until Esc/Enter) |
| **3-Column Layout (New)** | `prefix` + `Shift+T` | `bind T layout-3col.sh new` (lateral 25% \| centro 50% \| lateral 25%) |
| **3-Column Layout (Apply)** | `prefix` + `Shift+E` | `bind E layout-3col.sh apply` |
| **Copy mode** | `prefix` + `[` | `copy-mode` (Vi navigation, search `/`, yank `y`) |
| **Edit scrollback** | `prefix` + `e` | Open pane scrollback in `$EDITOR` (Neovim) |
| **Zoom toggle** | `prefix` + `z` | `bind z resize-pane -Z` |
| **Close pane** | `prefix` + `x` | `bind x kill-pane` |
| **Detach session** | `prefix` + `d` (or `prefix` + `q`) | `bind d detach-client` |
| **Cycle agents** | `F7` / `F8` | Previous / Next agent |

## Agent Integrations & CLI Control

From a terminal or script:

```bash
herdr agent list                      # List agents and their current states
herdr agent explain <target> --json   # Inspect why an agent is classified with a state
herdr server reload-config            # Reload ~/.config/herdr/config.toml
herdr server stop                     # Gracefully stop the Herdr background server
```

When running *inside* a Herdr pane (`HERDR_ENV=1`), agents can interact with the Herdr CLI directly without opening nested client loops.
