# Fluxo de Trabalho no Terminal

Guia prático para usar tmux, Neovim e agentes IA de forma produtiva.

## 🎛️ Layout 3 Colunas

Crie um layout padrão com três panes lado a lado para agente, editor e shell.

### Criar o layout
```
<Prefix>T
```
Abre três panes com proporção padrão **25% | 50% | 25%** (esquerda | centro | direita), com foco no centro. Útil para:
- **Esquerda**: Agente IA (Claude Code, Codex, OpenCode)
- **Centro**: Neovim (editor principal)
- **Direita**: Shell/testes/logs

Os panes herdam o diretório atual.

### Ajustar a proporção
A largura de cada pane lateral é configurável pela variável `@layout3_side` (padrão: 25).

**Em ~/.tmux.conf:**
```
set -g @layout3_side 20   # Laterais mais estreitas (20%)
set -g @layout3_side 30   # Laterais mais largas (30%)
```

**Em runtime (sem editar arquivo):**
```bash
tmux set -g @layout3_side 20
<Prefix>E  # Reaplica a proporção
```

### Reaplica a proporção
```
<Prefix>E
```
Se você já tem 3 panes e mudou `@layout3_side`, use `<Prefix>E` para reajustar as larguras sem perder a layout.

Recarregar a config: `<Prefix>r` (tmux recarrega `~/.tmux.conf`).

---

## 📊 Sessões e Janelas

Organize seu trabalho com uma sessão por projeto e uma janela por tarefa.

### Estratégia recomendada

- **Sessão por projeto**: `tmux new-session -s meuapp`
- **Janela por tarefa**: `<Prefix>c` (nova janela), renomeie com `<Prefix>,`

Exemplo:
```bash
tmux new-session -s dotfiles -c ~/dotfiles
tmux new-window -n edit
tmux new-window -n test
tmux new-window -n research
```

### Não sair ao fechar a última janela
```
# Já está configurado em ~/.tmux.conf:
set -g detach-on-destroy off
```
A sessão persiste mesmo ao fechar a última janela. Reabra com `tmux attach -t dotfiles`.

### Persistência com tmux-resurrect

O plugin **tmux-resurrect** salva o estado da sessão (panes, layouts, comandos rodando).

- Salvar: `<Prefix>C-s`
- Restaurar: `<Prefix>C-r`

Útil para voltar ao trabalho após reiniciar ou fechar o terminal.

---

## 🔀 Navegação e Cópia

Navegue entre Neovim e panes tmux de forma contínua.

### Navegar entre panes e nvim
```
<Ctrl>h  →  Move esquerda
<Ctrl>j  →  Move abaixo
<Ctrl>k  →  Move acima
<Ctrl>l  →  Move direita
```
Funciona em ambas as direções:
- Dentro do Nvim: Ctrl+hjkl navega entre splits
- Do Nvim para tmux: Ctrl+hjkl sai do Nvim e navega panes
- Dentro de tmux: Ctrl+hjkl navega panes

### Redimensionar panes
```
<Prefix>H  →  Aumenta esquerda (+5)
<Prefix>J  →  Aumenta abaixo (+5)
<Prefix>K  →  Aumenta acima (+5)
<Prefix>L  →  Aumenta direita (+5)
```
Use com `-r` para repetir sem soltar o prefix.

### Copiar com vi-mode
```
<Prefix>[       →  Entra em copy-mode
  v             →  Inicia seleção (caractere)
  V             →  Inicia seleção (linha)
  C-v           →  Inicia seleção (bloco)
  y ou Enter    →  Copia para buffer
  q             →  Sai de copy-mode
```

**OSC 52 (clipboard do sistema):** A config já usa `OSC 52` para copiar direto para o clipboard do seu terminal (funciona em SSH).

### Zoom em um pane
```
<Prefix>z
```
Expande o pane ativo para tela cheia. Pressione novamente para voltar.

### Quebrar e reunir panes
```
<Prefix>!   →  Move pane para janela nova (_hidden_pane)
<Prefix>@   →  Reunir pane anterior
```

---

## 🔧 Neovim com Agentes

Trabalhe com agentes IA editando código em tempo real no Nvim.

### Recarregar buffers editados pelo agente

Se o agente modificou um arquivo enquanto o Nvim estava aberto, use:
```vim
:checktime       " Verifica buffers modificados no disco
```

Ou ative `autoread` em tempo real adicionando ao `init.lua`:
```lua
vim.opt.autoread = true
```

### Ver diffs das mudanças

Se [lazygit](https://github.com/jesseduffield/lazygit) está instalado (verifice com `which lazygit`), use dentro do Nvim:
```vim
:LazyGit
```

Ou pelo terminal:
```bash
lazygit
```

### Copiar caminho do arquivo

O plugin `copy-file-path.nvim` oferece comandos úteis dentro do Nvim:
```vim
:CopyFilePath               " Copia caminho relativo
:CopyAbsoluteFilePath       " Copia caminho absoluto
:CopyRelativeFilePathFromHome  " Copia relativo à home (~)
:CopyFileName               " Copia só o nome do arquivo
```

Use um desses para copiar e colar no seu prompt do agente (ex.: pedir para editar um arquivo específico).

---

## 🤖 CLIs de Agentes

Execute Claude Code, Codex ou OpenCode num pane separado, numa sessão tmux dedicada.

### Aliases de sessão

Tres sessão e modo (contexto extra no system prompt) juntos:
```bash
# Dev mode (padrão, contexto de desenvolvimento)
claude-dev

# Review mode (focado em revisão de código)
claude-review

# Research mode (busca ampla, documentação)
claude-research
```

Mais documentação: `~/dotfiles/claude/contexts/`.

### Estratégia: um agente por pane

1. Abra a layout 3-coluna: `<Prefix>T`
2. No pane esquerdo, inicie um agente:
   ```bash
   claude-dev        # ou claude --continue, claude --resume
   ```
3. No pane central, abra Nvim: `nvim ~/seu-projeto`
4. No pane direito, rode testes/build/shell

### Git worktrees para paralelo

Para rodar dois agentes em paralelo (ex.: pesquisa em uma branch, dev em outra):
```bash
git worktree add -b feat/new ~/tmp/new-feature
cd ~/tmp/new-feature
tmux new-window -n research
claude-research
```

### `--continue` e `--resume`

Retome uma sessão do agente:
```bash
claude --continue      # Continua última sessão
claude --resume        # Menu interativo de sessões
```

### Compactar na fronteira de fase

Quando atingir ~50 tool calls, use dentro do agente:
```
/compact
```
Isto reduz o contexto, mantendo as conclusões. Continua na próxima sessão com `--continue`.

### Monitorar agentes com tmux-claude-monitor

Plugin **tmux-claude-monitor** mostra em tempo real qual agente está esperando input.

```
<Prefix>m   →  Abre monitor (mostra "waiting for input" se aplicável)
```

---

## 📋 Cheatsheet

| Atalho | O que faz |
|--------|-----------|
| **Layout & Panes** | |
| `<Prefix>T` | Criar layout 3 colunas (25/50/25) |
| `<Prefix>E` | Reaplica proporção do layout |
| `<Prefix>c` | Nova janela |
| `<Prefix>n` | Próxima janela |
| `<Prefix>p` | Cola o buffer do tmux (paste-buffer) |
| `<Prefix>"` | Split horizontal |
| `<Prefix>%` | Split vertical |
| `<Prefix>!` | Break pane para janela |
| `<Prefix>@` | Join pane anterior |
| **Navegação** | |
| `<Ctrl>h/j/k/l` | Navega entre Nvim splits e tmux panes |
| `<Prefix>H/J/K/L` | Redimensiona pane (+5) |
| `<Prefix>z` | Zoom/unzoom pane |
| **Copy Mode** | |
| `<Prefix>[` | Entra copy-mode |
| `v` | Seleção (char) |
| `V` | Seleção (linha) |
| `C-v` | Seleção (bloco) |
| `y` | Copia |
| `q` | Sai copy-mode |
| **Sessões** | |
| `<Prefix>$` | Renomeia sessão |
| `<Prefix>d` | Desanexa (detach) |
| `<Prefix>C-s` | Salva com resurrect |
| `<Prefix>C-r` | Restaura com resurrect |
| **Config** | |
| `<Prefix>r` | Recarrega ~/.tmux.conf |
| `<Prefix>:` | Modo comando tmux |
| **Agentes** | |
| `<Prefix>m` | Monitor agentes (tmux-claude-monitor) |
| `<Prefix>d` | Desanexa para agente continuar rodando |
| **Nvim (ex.: LazyVim)** | |
| `<Tab>/<S-Tab>` | Próxima/anterior tab |
| `:checktime` | Recarrega buffers do disco |
| `:LazyGit` | Git UI (se lazygit instalado) |
| `:CopyFilePath` | Copia caminho relativo |

---

## 💡 Fluxo Recomendado

1. **Inicie a sessão:**
   ```bash
   cd ~/seu-projeto
   tmux new-session -s meuapp -c .
   ```

2. **Configure a layout:**
   ```
   <Prefix>T          # 3 colunas
   ```

3. **Preencha os panes:**
   - Esquerda: `claude-dev`
   - Centro: `nvim .`
   - Direita: `npm run dev` ou shell

4. **Trabalhe:**
   - Navegue com `<Ctrl>h/j/k/l`
   - Copie caminhos de arquivo no Nvim
   - Cole no agente para contexto

5. **Salve o estado:**
   ```
   <Prefix>C-s        # resurrect
   ```

6. **Ao sair:**
   ```
   <Prefix>d          # Desanexa
   # ... máquina desliga, volta depois ...
   tmux attach -t meuapp
   <Prefix>C-r        # Restaura
   ```

---

**Veja também:**
- `nvim/SETUP.md` — Configuração do Neovim
- `agents/AGENTS.md` — Instruções para agentes
- `~/.tmux.conf` — Configuração completa do tmux
