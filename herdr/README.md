# Herdr

Terminal workspace manager and multiplexer purpose-built for AI coding agents (Claude Code, Codex, Antigravity, OpenCode, etc.).

## Install & Update

```bash
make herdr-install                    # Installs herdr pinned in herdr/VERSION + herdr/SHA256
make herdr-update [VERSION=x.y.z]     # Re-pin to latest (or specific version), update SHA256 and review diff
make herdr-ssh-setup                  # Configures SSH on port 2222 in WSL2 for Herdr Desktop integration
```

The executable is installed to `~/.local/bin/herdr` and the configuration is linked from `herdr/config.toml` to `~/.config/herdr/config.toml`.

### Windows Host + WSL2 Setup (Option C)

For running the native **Herdr Desktop GUI** on Windows with agents running inside **WSL2** over SSH:
- See the complete guide in [installation.md](installation.md).
- Quick setup:
  - In WSL: `make herdr-ssh-setup` (or `./herdr/setup-wsl-ssh.sh`)
  - In Windows PowerShell: `powershell -ExecutionPolicy Bypass -File .\herdr\setup-host.ps1`

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
| **Next / Prev tab** | `prefix` + `n` / `prefix` + `p` (or `Ctrl/Alt+Shift+Right/Left`) | `bind -r n` / `bind -r p` |
| **Switch tab** | `prefix` + `1..9` | `select-window -t 1..9` |
| **Close tab** | `prefix` + `&` (or `prefix` + `Shift+x`) | `bind & kill-window` |
| **Split vertical (right)** | `prefix` + `v` | Split pane vertical |
| **Split horizontal (down)** | `prefix` + `-` | Split pane horizontal |
| **Pane navigation (Vim)** | `prefix` + `h` / `j` / `k` / `l` (or `Ctrl` / `Alt` + `h/j/k/l`) | Vim-tmux-navigator (`select-pane -L/-D/-U/-R`) |
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

## Herdr app: layout `traycer`

Mods e layouts existem só no **Herdr app** (GUI no Windows), em `%USERPROFILE%\.config\herdr-app`. O TUI (`herdr` 0.9.5) não tem mods. A referência autoritativa é o `AGENTS.md` dessa pasta.

```bash
make herdr-app-install               # ou: herdr/install-app.sh [--dry-run]
```

O script copia `herdr/app/` para a pasta do app e faz backup se o destino diferir. Depois, no app, aperte `ctrl-shift-l` para alternar o layout.

- **Layout `traycer`:** clone do `main` com uma coluna `side` à direita.
  - `lower`: pilha com a aba Agenttrail (mod `lower-tabs` desenha as abas e chama `layout.select`).
  - `filetree`: árvore de arquivos na barra lateral esquerda, abaixo de `spaces` e `agents`.
  - `cache-hit`: contador de cache dos agentes, abaixo de `filetree` na barra lateral esquerda.
  - `usage`: barra do `over9k-usage` acima da barra de status.
  - `usage-limits`: limites do Claude/Codex na linha da barra de status, ao lado do `workspace-status`.
  - Se o agente em foco estiver na aba atual, o mesmo terminal aparece duas vezes. Isso é esperado.
- **Validar:** `herdr-app.exe check 'C:\Users\<user>\.config\herdr-app\mods\cache-hit'` e `herdr-app.exe shot`.
- **Escape:** `ctrl-alt-shift-escape` volta ao layout `main`.

### Mods de terceiros instalados no app

Mods rodam como o seu usuário, sem sandbox. Eu li o código dos commits abaixo antes de copiar. Eles ficam só em `%USERPROFILE%\.config\herdr-app\mods`, não neste repo.

| Mod | Commit lido | Tecla | Observação |
| :--- | :--- | :--- | :--- |
| `over9k-usage` ([herunan/herdr-over9k](https://github.com/herunan/herdr-over9k)) | `a53c200` | — | Sem rede. Lê `~/.claude.json` e sessões do Codex. Os switches editam `~/.claude/settings.json`: deixe desligados. |
| `revive` ([dmazlum/herdr-revive](https://github.com/dmazlum/herdr-revive)) | `6e1b4a2` | `ctrl-shift-r` | **Não funciona com a máquina `wsl`**: o mod mostra "Revive works on this computer for now" para terminais de outra máquina. O passo `install` não foi rodado. Ele gravaria hooks em `~/.claude/settings.json`, `~/.codex/hooks.json` e `~/.zshrc`, que são symlinks para este repo. |
| `filetree` ([cybertron288/herdr-mods](https://github.com/cybertron288/herdr-mods/tree/main/filetree)) | `34e7c33` | — | Árvore de arquivos com cores de git. Só leitura de arquivos, sem rede, e funciona com a máquina `wsl`. Só cria `~/.local/state/herdr-filetree` no Windows. O `bridge.ts` é um hook opcional do Claude Code (exige `bun`): não foi ligado. |
| `file-icons` ([cybertron288/herdr-mods](https://github.com/cybertron288/herdr-mods/tree/main/file-icons)) | `34e7c33` | — | Ícones do Material Icon Theme e visualizador de arquivos. Fornece também o conjunto de 1.184 ícones SVG para o mod `filetree`. |
| `agenttrail` ([sodiumsun/agenttrail](https://github.com/sodiumsun/agenttrail)) | `3785d4e` | — | Só lê `127.0.0.1:5330-5344`. Inicia `npx -y agenttrail@0.4.1` apenas no botão "Start Map here". Com um terminal do `wsl` focado, mostra "No terminal in focus". |
| `space-names` ([SaifHarding/herdr-space-names](https://github.com/SaifHarding/herdr-space-names)) | `81523bc` | — | Sem `exec`, sem rede. |
| `usage-limits` ([nozikov/herdr-usage-limits](https://github.com/nozikov/herdr-usage-limits)) | `ca22615` | — | Sem rede. Roda `claude` e `codex` do WSL via `wsl.exe` (limites 5h/semana) e lê sessões locais. Adaptado em `herdr/app/mods/usage-limits`: `io/sh.js`, `io/helpers.js` e `ui/bar.js` (alinhamento à esquerda) mudaram, e o provider `agy` (limites do Antigravity via `agy -p "/usage"`) é novo, e o `wsl-run.sh` é novo. Fica na linha da barra de status do layout `traycer`. `sqlite3` falta no WSL: só o bloco de sessão do OpenCode fica de fora. |
| `tmux-prefix` ([herdrdev/herdr-layout-examples](https://github.com/herdrdev/herdr-layout-examples)) | `0ec9676` | `ctrl-space` | Versão adaptada em `herdr/app/mods/tmux-prefix`: prefixo `Ctrl+Space` (igual ao `tmux/.tmux.conf`) e `n`/`p` repetem como `bind -r`. `ctrl-space` duas vezes envia um `^@` real. Não há equivalente a `H/J/K/L` nem a `T/E`: o app não tem comando de resize por pane. |

O `keys.json` ganhou 4 chaves (`ctrl-b` virou `ctrl-space`). O backup está em `keys.json.bak.*` na mesma pasta.

## Agent Integrations & CLI Control

From a terminal or script:

```bash
herdr agent list                      # List agents and their current states
herdr agent explain <target> --json   # Inspect why an agent is classified with a state
herdr server reload-config            # Reload ~/.config/herdr/config.toml
herdr server stop                     # Gracefully stop the Herdr background server
```

When running *inside* a Herdr pane (`HERDR_ENV=1`), agents can interact with the Herdr CLI directly without opening nested client loops.
