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

O script copia `herdr/app/` para a pasta do app e faz backup se o destino diferir. Depois, reabra o app para ler layout e mods novos. O `ctrl-shift-l` só alterna entre layouts, não recarrega.

- **Layout `traycer`:** clone do `main` com abas extras na barra lateral esquerda.
  - `agenttrail`: aba `Agenttrail` na pilha `left-tabs` da barra lateral esquerda, ao lado de `Projetos` e `Arquivos`.
  - `filetree`: árvore de arquivos na barra lateral esquerda, abaixo de `spaces` e `agents`.
  - `cache-hit`: contador de cache dos agentes, abaixo de `filetree` na barra lateral esquerda.
  - `usage`: barra do `over9k-usage` acima da barra de status.
  - `usage-limits`: limites do Claude/Codex na linha da barra de status, ao lado do `workspace-status`.
  - Integração com o over9k: `over9k-tabs` no lugar de `tabs` (botões To-do e Timeline, botões de janela), `over9k-todos` e `over9k-prompts` no painel direito, `over9k-footer` no rodapé da sidebar e `terminal_menu: over9k-menu` (lançar, retomar e fechar agentes).
  - Teclas (`keys/over9k.json`, seções `layout:traycer` e `layout:over9k`): `ctrl-tab` abre o Switcher e `ctrl-shift-w` fecha a aba com confirmação. O `ctrl-shift-x` continua como `pane.close`.
  - Se o agente em foco estiver na aba atual, o mesmo terminal aparece duas vezes. Isso é esperado.
- **Layout `multiproject`:** base do layout `cockpit`, com as abas do `traycer`. O `traycer` continua igual. Serve ao trabalho em vários projetos ao mesmo tempo.
  - Parte do `cockpit.json` porque o mod `cockpit` exige o stack `center` (vistas `home`, `work`, `inbox`, `todo` e outras), a sidebar, o sino e a barra de status. Como aba solta num layout derivado do `traycer`, ele falha com "don't have a center stack named home".
  - A sidebar esquerda tem as abas `Agentes` (cockpit), `Projetos` (over9k, todos os spaces), `Arquivos`, `Agenttrail` e `Insights`, mais o `cache-hit`.
  - A barra `over9k-usage` fica acima da barra de status do cockpit.
  - Use um space por projeto e um agente por pane. A vista `home` do cockpit mostra PRs e CI. O `To-do` do cockpit e o `todo` do Herdr são listas diferentes.
  - Teclas: `keys/multiproject.json` junta as teclas do cockpit (`ctrl-alt-*`) com `ctrl-tab` (Switcher) e `ctrl-shift-w` (fecha a aba).
  - Não inclui o painel `skillshare`. O binário `cockpit` roda no WSL, como no layout `cockpit`.
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
| `agenttrail` ([sodiumsun/agenttrail](https://github.com/sodiumsun/agenttrail)) | `3785d4e` | — | Só lê `127.0.0.1:5330-5344`. Inicia `npx -y agenttrail@0.4.1` apenas no botão "Start Map here". Adaptado em `herdr/app/mods/agenttrail`: `feed.js` e `main.js` tratam a máquina `wsl` como local (prop `localMachines`), rodam `git` nela com `exec(..., {on})` e iniciam o Map com `bash -lc` + nvm. O layout `traycer` usa `localMachines: ["wsl"]` e não fixa a porta, então o painel segue o terminal em foco. Para fixar o Map do serviço systemd (`~/dotfiles`), use `"port": 5330`. Faltam o `gpui-kit.d.ts` e o `jsconfig.json` no repo: só tipos, ficam na pasta instalada. |
| `space-names` ([SaifHarding/herdr-space-names](https://github.com/SaifHarding/herdr-space-names)) | `81523bc` | — | Sem `exec`, sem rede. |
| `usage-limits` ([nozikov/herdr-usage-limits](https://github.com/nozikov/herdr-usage-limits)) | `ca22615` | — | Sem rede. Roda `claude` e `codex` do WSL via `wsl.exe` (limites 5h/semana) e lê sessões locais. Adaptado em `herdr/app/mods/usage-limits`: `io/sh.js`, `io/helpers.js` e `ui/bar.js` (alinhamento à esquerda) mudaram, e o provider `agy` (limites do Antigravity via `agy -p "/usage"`) é novo, e o `wsl-run.sh` é novo. Fica na linha da barra de status do layout `traycer`. `sqlite3` falta no WSL: só o bloco de sessão do OpenCode fica de fora. |
| `insights` ([GaganSD/coding-agent-toolkit](https://github.com/GaganSD/coding-agent-toolkit/tree/main/herdr-insights), MIT) | `819ac53` | — | Painel de tokens e modelos de Claude, Codex e Antigravity. Sem rede: só `exec` de `node` (o app usa o Node do Windows, que exige 22.15 ou mais) e escrita do próprio índice em `~/.config/herdr-app/data/insights`. Adaptado em `herdr/app/mods/insights/main.js`: a função `sessionHome()` lê a prop `sessionHome` e aponta o coletor para o home do WSL via UNC (`\\wsl.localhost\Ubuntu\home\flv`). O layout `traycer` ganhou a aba `Insights` na pilha `left-tabs`. Não rodei o `npm run install:local`, que gera `runtime.json` e um botão de toolbar. Sem `runtime.json`, o mod usa o `node` do PATH do Windows. |
| `skillshare` ([runkids/skillshare](https://github.com/runkids/skillshare/tree/main/herdr/skillshare), MIT) | `752f7b1` (CLI `v0.30.10`) | — | Painel de skills, agentes, MCPs, plugins e hooks. O mod roda o CLI na máquina do space (`exec ... {on}`), então a máquina `wsl` funciona sem fork. Usa rede: `curl` (versão do painel) e `git clone` (auditoria antes de instalar). Vendorizado sem mudança em `herdr/app/mods/skillshare`. O layout `traycer` ganhou o painel `skillshare-panel` (oculto) e o botão `skillshare-toggle` na barra de status. O CLI está em `~/.local/bin/skillshare` (release `v0.30.10`, sha256 `6ea22732…ef230` conferido). **`skillshare init` não foi rodado.** Sem config, o painel mostra erro. O `init` padrão importaria 282 skills e ligaria 7 alvos. O `sync` grava em `~/.claude/skills` e `~/.codex/skills`: rode sempre `--dry-run` antes. O botão "Update panel" troca os arquivos do mod no app, fora deste repo. |
| `tmux-prefix` ([herdrdev/herdr-layout-examples](https://github.com/herdrdev/herdr-layout-examples)) | `0ec9676` | `ctrl-space` | Versão adaptada em `herdr/app/mods/tmux-prefix`: prefixo `Ctrl+Space` (igual ao `tmux/.tmux.conf`) e `n`/`p` repetem como `bind -r`. `ctrl-space` duas vezes envia um `^@` real. Não há equivalente a `H/J/K/L` nem a `T/E`: o app não tem comando de resize por pane. |

O `keys.json` ganhou 4 chaves (`ctrl-b` virou `ctrl-space`). O backup está em `keys.json.bak.*` na mesma pasta.

### Ferramentas de terceiros fora do app

| Ferramenta | Versão | Observação |
| :--- | :--- | :--- |
| `memex` ([nicosuave/memex](https://github.com/nicosuave/memex), MIT) | `0.34.0` (Homebrew, `brew pin memex`) | Busca e retomada de sessões de Claude, Codex e outros. Instalado com `brew install memex`, sem `curl \| sh`. A config fica em `memex/config.toml`, linkada em `~/.memex/config.toml`: sem embeddings, sem MCP, sem web UI, sem `dream`, e com `[redaction]` ligado. O índice (`~/.memex`, 227 MB) é local. Não instalei o plugin herdr do `memex`, nem a skill, nem o serviço (`brew services`). Use `memex --no-update-check --non-interactive search "<termos>"`. Camada separada do vault (`sb search`): ver a seção "Second brain" do `agents/AGENTS.md`. |
| `herdr-resurrect` ([ntindle/herdr-resurrect](https://github.com/ntindle/herdr-resurrect), MIT) | `dab5bed` (v0.2.0) | Plugin do **TUI no WSL** (`herdr plugin link herdr/plugins/herdr-resurrect`). Li o código: sem rede, sem escrita em `~/.claude`, `~/.codex` ou rc do shell. Lê só `~/.claude/projects` e `~/.codex/sessions` para achar o id da sessão. Autosave por evento ligado. `autoRestore` desligado: restaure com a ação `restore` (`herdr plugin action invoke restore --plugin ntindle.herdr-resurrect`). Config em `~/.config/herdr/plugins/config/ntindle.herdr-resurrect/settings.json`: `agentResumeCommands` troca `--continue` e `resume --last` por relançamento sem flag, então o agente só retoma com `session ref` (`claude --resume <id>`, `codex resume <id>`). **Cache:** o `--resume` reenvia o histórico e reescreve o cache no 1º turno, e o cache já está frio após reinício. Meça com `cache-hit`. **Windows:** o app usa `herdr-core`/`hc`, que não tem `plugin`. O plugin não roda lá. A persistência do app vem do `hc`: `hc keep <terminal>` ou `hc run --keep` recria os programas como shells após `hc server stop`. **Caminho do link:** aponta para o worktree. Depois do merge, rode `herdr plugin unlink ntindle.herdr-resurrect` e `herdr plugin link ~/dotfiles/herdr/plugins/herdr-resurrect`. |

## Agent Integrations & CLI Control

From a terminal or script:

```bash
herdr agent list                      # List agents and their current states
herdr agent explain <target> --json   # Inspect why an agent is classified with a state
herdr server reload-config            # Reload ~/.config/herdr/config.toml
herdr server stop                     # Gracefully stop the Herdr background server
```

When running *inside* a Herdr pane (`HERDR_ENV=1`), agents can interact with the Herdr CLI directly without opening nested client loops.

## Herdr app: layouts `over9k` e `cockpit`

Dois layouts vendorizados de terceiros, ao lado do `traycer`. O `ctrl-shift-l` cicla entre todos. O `ctrl-alt-shift-escape` volta ao `main`. Instale com `make herdr-app-install`.

| Layout | Fonte (commit fixado) | Foco |
| :--- | :--- | :--- |
| `over9k` | `OVER9K_VERSION` (herunan/herdr-over9k, MIT) | Sidebar de projetos e agentes, abas To-do/Timeline, rodapé de uso |
| `cockpit` | `COCKPIT_VERSION` (quaresc/cockpit, MIT) | Painel de agentes com PRs, CI, inbox e runbook |

- **over9k:** usa os mods `over9k*` já forkados aqui, mais `over9k-footer`, `over9k-tabs`, `over9k-todos` e `over9k-prompts` do upstream. O `over9k/mod.json` local mantém `place: left` e `size: 268`. As teclas do upstream não entram, porque colidem com o `ctrl-tab` e o `ctrl-shift-w` do `keys.json`.
- **over9k-todos (adaptado para WSL):** o botão "Let agents keep these lists" checa e grava a regra, o comando `todo` e o hook no WSL (`exec` com `on: "wsl"`), não no Windows. O `setup.sh` vem do `over9k-options` e roda com `sh -c`. O `todo.sh --rule` segue o symlink de `~/.claude/CLAUDE.md` e `~/.codex/AGENTS.md`, para o `mv` não o trocar por arquivo comum. O hook e o wrapper apontam para `/mnt/c/.../herdr-app/mods`, então dependem do Windows montado.
- **cockpit:** o app roda no Windows e o binário `cockpit` roda no WSL2 (modo "remote desk" do upstream, em preview). O `app/cockpit.json` aponta para a máquina `wsl` em `127.0.0.1`. Isso funciona porque o `.wslconfig` usa `networkingMode=mirrored`.
- **Teclas do cockpit:** `keys/cockpit.json` troca `cmd` por `ctrl-alt` e entra só na seção `layout:cockpit`. O `install-app.sh` mescla esse arquivo no `keys.json` com backup. Exemplos: `ctrl-alt-p` paleta, `ctrl-alt-0` Home, `ctrl-alt-j` próximo agente em espera. Em teclado ABNT2, `ctrl-alt` é AltGr: se uma tecla digitar caractere, mude-a em `keys/cockpit.json`.

Instalar o binário do cockpit no WSL2 (uma vez, sem `curl | sh`):

```bash
git clone https://github.com/quaresc/cockpit /tmp/cockpit-up
COCKPIT_NO_SETUP=1 COCKPIT_VERSION=0.40.4 sh /tmp/cockpit-up/install.sh   # confira o release em COCKPIT_VERSION
cockpit hub start                                                        # o mod também inicia o hub sozinho
```

Limites do cockpit em modo runner (preview upstream): as ações de escrita são parciais, e o contador "Agents" da Home pode mostrar 0 mesmo com agentes na sidebar. Sem MCPs de Linear, Jira ou Datadog: a Home usa só `gh` e os agentes. Se precisar de mais, siga a etapa de fork do mod, como em `cache-hit` (`patches/cache-hit-wsl-claude-session.patch`).
