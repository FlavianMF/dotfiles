# dotfiles

Reproducible development environment configuration. Clone and run `install.sh` to set up:

- **Shell**: zsh + Oh My Zsh + spaceship-prompt
- **Editor**: Neovim (LazyVim)
- **Multiplexer**: tmux + Catppuccin theme + plugins
- **Tools**: git, GitHub CLI (gh), Docker
- **Tools (optional)**: shellcheck (component `shellcheck`, apt or GitHub release binary)
- **AI harnesses**: Claude Code, Codex and OpenCode sharing one `AGENTS.md`, one skills dir and the same MCPs (see [AI harnesses](#ai-harnesses))

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
| `claude/settings.json` | Claude Code config | Model (opus/xhigh, subagents on sonnet), plugins, hooks, deny list, statusline |
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | Imports `agents/AGENTS.md` + Claude-only notes |
| `agents/AGENTS.md` | Codex / OpenCode / Claude | Shared instructions (performance, security, git, design skills) |
| `codex/`, `opencode/` | `~/.codex`, `~/.config/opencode` | Only when the component is selected or the tool is installed |
| `claude/hooks/jev-e.sh` | `~/.claude/hooks/` (directory link) | Runs only if jev-workflow is built (component `jev`) |
| `vendor/ecc/`, `claude/rules/` | `~/.agents/skills`, `~/.claude/{agents,rules}` | Component `ecc` (off by default): selected ECC pieces, global |
| `ecc@ecc` plugin, `vendor/ecc/upstream/` | Project `.claude/` | Full ECC, installed but off; `make ecc-on DIR=...` per project ([ECC](#ecc-affaan-mecc)) |

## AI harnesses

One set of instructions, skills and MCPs for Claude Code, Codex and OpenCode.

| Piece | Source of truth | How it gets installed |
|-------|-----------------|-----------------------|
| Instructions | `agents/AGENTS.md` | linked to `~/.codex/AGENTS.md` and `~/.config/opencode/AGENTS.md`; imported by `claude/CLAUDE.md` (`@~/dotfiles/agents/AGENTS.md`) |
| Claude plugins | `enabledPlugins` + `extraKnownMarketplaces` in `claude/settings.json` | `install.sh` reconciles with `claude plugin list --json` (installs what's missing, warns about extras). A plugin declared `false` is installed but kept off at user scope, to be enabled per project. `make plugins-freeze` records versions in `claude/plugins.lock.json` |
| Skills | `~/.agents/skills` (canonical, read by Codex and OpenCode) | `npx skills@<pinned> add ... -g`; shared skills get a link in `~/.claude/skills`. Skills Claude already gets from a plugin (impeccable, mattpocock, caveman, figma, typesafe) are installed for Codex/OpenCode only |
| `second-brain-sync` | `~/obsidian_vault/00_META/skills/second-brain-sync` | `~/.agents/skills/second-brain-sync` → vault, `~/.claude/skills/second-brain-sync` → `~/.agents/skills/...` |
| MCPs (Figma, Playwright, GitHub) | Claude: plugins; Codex: `codex/config.base.toml`; OpenCode: `opencode/opencode.json` | GitHub MCP uses a PAT (`secrets/github-mcp.env`): the hosted server doesn't offer OAuth to these clients |
| Codex config | `codex/config.base.toml` (+ `codex/yolo.config.toml` profile) | rendered into `~/.codex/config.toml`, keeping machine-only keys such as `[projects.*]`. `make codex-drift` shows differences |
| OpenCode config | `opencode/opencode.json` | symlinked (OpenCode doesn't rewrite it). `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1` in `.zshrc` avoids loading skills twice |

Components `codex` and `opencode` are **off by default** (`./install.sh --with=codex,opencode`); both install from npm into `~/.local` and are skipped if already installed. Logins are manual: the install prints a checklist at the end.

Claude Code extras (all in `claude/`): `statusline.sh` (model, cwd, git branch/dirty, % context left, caveman badge), `hooks/` (compact suggestion after ~50 tool calls, opt-in format/typecheck on Stop, second-brain hints/reminder behind `SECOND_BRAIN_HOOKS=1`) and `contexts/` (session modes via the `claude-dev`, `claude-review`, `claude-research` aliases).

**Jev tools** (component `jev`, off by default): `./install.sh --harness-only --with=jev` clones (private repo) and builds [jev-workflow](https://github.com/FlavianMF/jev-workflow) in `~/projetos_claude/jev-workflow` (override with `JEV_WORKFLOW_HOME`). `claude/hooks/jev-e.sh` is wired on `UserPromptSubmit` (timeout 2 s, `JEV_MODE_E=shadow` in `settings.json` `env`): in shadow mode it only appends a decision to `~/.local/state/jev-tools/log.jsonl` and prints nothing; it is a silent no-op without the build, without `TYPESAFE_API_KEY`, or when `JEV_TOOLS=0` / `JEV_TOOL_E=0` / the `DISABLED` marker is set.

**Deny lists** (same intent in the 3 harnesses): secrets reads (`~/.ssh`, `~/.aws`, `.env*`, `secrets/`), `curl | bash`, `ssh`/`scp`/`nc`, `rm -rf` (and variants), `sudo`, `chmod 777`. Claude: `permissions.deny`; OpenCode: `permission.bash`/`read`; Codex: sandbox + `codex/dotfiles.rules` (execpolicy, linked as `~/.codex/rules/dotfiles.rules`).

Useful targets: `make harness`, `make harness-dry-run`, `make plugins-freeze`, `make plugins-update`, `make codex-drift`, `make audit` (AgentShield, pinned, via npx), `make lint`, and the ECC ones below (`make ecc-on|ecc-off|ecc-status DIR=...`, `make ecc-rules`).

### ECC (affaan-m/ECC)

[ECC](https://github.com/affaan-m/ECC) (MIT) is used in two layers, both pinned to the same commit (`vendor/ecc/SOURCE.md`, currently v2.2.2 / `c70874f`).

**What costs context, and when.** Skills, commands and agents only exist if installed, but loading is split:

| Kind | Always in context (every turn) | Loaded on demand |
|------|--------------------------------|------------------|
| Skills / commands | name + description | `SKILL.md` body and supporting files, when invoked |
| Agents | description (in the Agent tool) | the agent prompt, when delegated to |
| Rules with `paths:` | nothing | the rule, when Claude reads a matching file |
| Rules without `paths:` | the whole file | — |
| Plugin hooks / MCP | no model tokens (hooks); MCP tool schemas | — |

For the full ECC that is ~45k tokens always-on (`claude plugin details ecc@ecc`: 387 skills/commands, 68 agents), so it is never enabled globally.

**Layer 1: selected pieces, global** (component `ecc`, off by default: `./install.sh --harness-only --with=ecc`). Skills, agents and path-scoped language rules vendored and rewritten in `vendor/ecc/` (see `SOURCE.md` for local modifications and what was left out). Skills go to `~/.agents/skills` (+ `~/.claude/skills` link), agents to `~/.claude/agents/ecc-*.md` (converted copies in `~/.config/opencode/agents/`; Codex has no agent files, it gets the skills), rules to `~/.claude/rules/ecc`. Languages: Python, TypeScript/JavaScript, C++, Rust from ECC; C, Makefile and CMake rules are local (`claude/rules/`, linked as `~/.claude/rules/local`).

**Layer 2: full ECC, per project** (Claude Code only). The `ecc@ecc` plugin is declared `"ecc@ecc": false` in `claude/settings.json`: `install.sh` installs it and keeps it disabled at user scope.

```bash
make ecc-on DIR=~/my-project              # plugin on + full ECC rules
make ecc-on DIR=~/my-project NO_COMMON=1  # language rules only, no rules/common
make ecc-status DIR=~/my-project
make ecc-off DIR=~/my-project
```

- `ecc-on` sets `enabledPlugins["ecc@ecc"] = true` in the project's `.claude/settings.local.json` and links `.claude/rules/ecc-upstream` → `vendor/ecc/upstream/rules/`. Both paths go to `.git/info/exclude`, so nothing lands in the project's git. Restart Claude Code in the project afterwards.
- `ecc-off` removes only that key and the link; the rest of `settings.local.json` stays.
- `rules/common` (~18 KB) has no `paths:`, so it loads in every session of that project and pushes automatic delegation to `ecc:*` agents. Use `NO_COMMON=1` to skip it.
- Rules: `vendor/ecc/upstream/rules/` is an unedited mirror of the pin (minus `README.md` and `*/hooks.md`), regenerated by `make ecc-rules` (`vendor/ecc/fetch-upstream.sh`).
- Hooks: `ECC_HOOK_PROFILE=minimal` plus `ECC_DISABLED_HOOKS=stop:evaluate-session,post:ecc-metrics-bridge` (env in `claude/settings.json`, mirrored in `pluginConfigs`). What still runs: `block-no-verify`, session save/resume (`session:start`, `session-end`), `cost-tracker`, `plan-canvas-pending`. GateGuard, config-protection, ECC's format/typecheck (ours is `claude/hooks/format-typecheck.sh`) and the continuous-learning observer stay off.
- The plugin also starts the `chrome-devtools-mcp` MCP server (overlaps with Playwright), and the Layer 1 skills/agents show up twice (`ecc-X` and `ecc:X`).

**Updating the pin**: `make plugins-update`, put the new marketplace commit (from `claude/plugins.lock.json`) at the top of `vendor/ecc/SOURCE.md`, `make ecc-rules`, review `git diff vendor/ecc/upstream`, and check whether hook IDs changed (`ECC_DISABLED_HOOKS`).

> `claude plugin marketplace add` / `install` rewrite `~/.claude/settings.json`, which is this repo's file: they drop `autoUpdate: false` and flip declared-off plugins to `true`. `install.sh` puts both back; after any manual plugin command, check `git diff claude/settings.json`.

## What's NOT Included

These are intentionally excluded for security and machine-specific reasons:

- `.ssh/` — SSH keys (restore manually)
- `.docker/` — Docker credentials
- `.config/github-copilot/` — Copilot auth
- `.config/gh/hosts.yml` — GitHub auth tokens
- `.claude/.credentials.json` — Claude credentials
- `secrets/*.env` — API keys (only `secrets/*.env.example` is versioned; `.zshrc` sources every `secrets/*.env`)
- `~/.codex/auth.json`, OpenCode auth — harness logins
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
