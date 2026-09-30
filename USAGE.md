# Como Usar Este Repositório

## 📥 Primeiras Vezes

### Opção 1: Clone e Instale (Recomendado)
```bash
# Clone
git clone <seu-repo-url> ~/dotfiles
cd ~/dotfiles

# Instale (vai pedir senha sudo)
sudo ./install.sh

# Reabra o terminal
exec zsh
```

### Opção 2: Use Makefile
```bash
cd ~/dotfiles
make install
```

### Opção 3: Instalação Manual
```bash
# Veja o install.sh para ver exatamente o que é necessário
cat install.sh
```

## 🔄 Atualizando Configurações

Se você modificar alguma configuração localmente e quer salvar no repo:

```bash
cd ~/dotfiles
make update
```

Isso copia:
- `~/.zshrc` → `config/zsh/.zshrc`
- `~/.tmux.conf` → `config/tmux/.tmux.conf`
- `~/.config/nvim` → `config/nvim/`

Depois faça commit:
```bash
git add config/
git commit -m "Update configurations"
git push
```

## 🔧 Modificar Configurações

### Mudar Tema Nvim
Edite: `config/nvim/lua/plugins/colorscheme.lua`
```lua
-- Descomente o tema que quer usar
-- require("sonokai").setup({...})
```

### Mudar Prefixo Tmux
Edite: `config/tmux/.tmux.conf`
```bash
set -g prefix C-a  # Mude para o que preferir
```

### Adicionar Aliases Zsh
Edite: `config/zsh/.zshrc`
```bash
alias ll='ls -lah'
alias vim='nvim'
```

### Adicionar Plugins Nvim
Crie arquivo: `config/nvim/lua/plugins/meu-plugin.lua`
```lua
return {
  {
    "usuario/repo-do-plugin",
    lazy = false,
    opts = {
      -- configurações aqui
    },
  },
}
```

## 💾 Backup

Faça backup automático das suas configs:
```bash
make backup
```

Os backups vão para `./backups/` com timestamp.

## 🗑️ Limpar Tudo

Se algo der errado:
```bash
make clean      # Remove symlinks
make backup     # Faz backup antes
```

## 🐳 Usar com Docker

```dockerfile
FROM ubuntu:24.04

WORKDIR /root

# Clone seu repositório
RUN git clone <seu-repo-url> dotfiles
WORKDIR /root/dotfiles

# Instale
RUN chmod +x install.sh && \
    ./install.sh

# Use
CMD ["/usr/bin/zsh"]
```

Build e use:
```bash
docker build -t dev-env .
docker run -it dev-env
```

## 🤖 Harnesses de IA (Claude Code, Codex, OpenCode)

```bash
./install.sh --dry-run                      # mostra o que mudaria nos harnesses, sem mudar nada
./install.sh --harness-only                 # só links + harnesses (sem apt, shell, tmux)
./install.sh --harness-only --with=codex,opencode   # instala também Codex e OpenCode (npm, ~/.local)
```

- **Instruções**: edite só `agents/AGENTS.md`. O Claude importa via `claude/CLAUDE.md`;
  Codex e OpenCode leem o link.
- **Plugins do Claude**: declare em `claude/settings.json` (`enabledPlugins` +
  `extraKnownMarketplaces`) e rode `make harness`. Depois `make plugins-freeze` e commite
  `claude/plugins.lock.json`. Para atualizar: `make plugins-update` e revise o diff do lock.
- **Skills**: ficam em `~/.agents/skills`. Instale com `npx skills add <repo> -g`; para o
  Claude ver, a skill precisa de link em `~/.claude/skills` (o skills CLI cria com
  `-a claude-code`).
- **Codex**: edite `codex/config.base.toml`, rode `make harness` e confira `make codex-drift`.
  Perfil sem sandbox: `codex --profile yolo`.
- **Modos de sessão**: `claude-dev`, `claude-review`, `claude-research`.
- **Hooks opcionais por projeto** (em `.claude/settings.local.json` do projeto):
  `"env": {"CLAUDE_FORMAT_TYPECHECK": "1"}` liga format/typecheck no fim do turno;
  `"env": {"SECOND_BRAIN_HOOKS": "0"}` desliga os hooks do second brain.
- **Auditoria**: `make audit` (AgentShield com versão fixada, via npx).
- **Lint**: `make lint` (bash -n, shellcheck, JSON e TOML). O shellcheck é o componente
  `shellcheck` do `install.sh` (desligado por padrão).

## 🔐 Adicionar Secrets (Seguro)

Se você quer adicionar secrets sem expostos no git:

1. Copie o exemplo: `cp secrets/github-mcp.env.example secrets/github-mcp.env`
2. Preencha o valor (o arquivo real é ignorado pelo git; só `*.env.example` é versionado)
3. O `.zshrc` carrega todo `~/dotfiles/secrets/*.env` ao abrir o shell

## 📱 Sincronizar Entre Máquinas

### Máquina A (Criar)
```bash
cd ~/dotfiles
make update
git add config/
git commit -m "Sync from machine A"
git push
```

### Máquina B (Aplicar)
```bash
cd ~/dotfiles
git pull
# Configurações já estão em sync!
```

## 🆘 Troubleshooting Comum

### "Zsh não inicia"
```bash
chsh -s /usr/bin/zsh
exec zsh
```

### "Nvim plugins não carregam"
```bash
nvim
:Lazy sync
:checkhealth
```

### "Tmux não inicia"
```bash
tmux kill-server
# Edite config/tmux/.tmux.conf se necessário
tmux
```

### "Fonte não aparece"
1. Reinstale: `./install.sh`
2. Reconfigure terminal para "FiraCode Nerd Font"
3. Reinicie terminal

## 📚 Arquivos Importantes

| Arquivo | Descrição |
|---------|-----------|
| `install.sh` | Script de instalação principal |
| `config/zsh/.zshrc` | Configuração Zsh |
| `config/tmux/.tmux.conf` | Configuração Tmux |
| `config/nvim/` | Todas as configs Neovim |
| `README.md` | Documentação completa |
| `QUICKSTART.md` | Guia rápido |
| `Makefile` | Atalhos úteis |

## 🚀 Next Steps

1. Customize conforme necessário
2. Commit suas mudanças
3. Push para seu repositório
4. Compartilhe com seu time!

---

**Dica:** Você pode fazer um fork deste repositório e criar seu próprio setup customizado!
