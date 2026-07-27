# Configuração Nvim + Tmux + Zsh

## ✅ Melhorias Implementadas

### 1. **Colorscheme & Visual**
- ✨ Ativado **Monokai-Pro** como tema padrão
- 🎨 Configurado com background transparente
- 💫 Adicionadas cores personalizadas para LineNr, CursorLine
- 📊 Instalada **Lualine** com statusline customizada

### 2. **Integração com Tmux**
- 🔗 Configurado **vim-tmux-navigator** para navegação seamless (Ctrl+hjkl)
- 📦 Adicionado plugin **tmux.nvim** para sync de clipboard
- ⚙️ Melhorado `.tmux.conf` com detecção automática de Vim
- ⌨️ Prefix alterado para `Ctrl+Space` (mais natural que Ctrl+B)

### 3. **Integração com Zsh**
- 🐚 Shell padrão do Tmux configurado para Zsh
- ⏱️ Escape-time otimizado para melhor performance
- 🚀 Adicionadas fontes FiraCode Nerd Font para renderização correta

### 4. **Opções de Editor Melhoradas**
- 📐 Configurado `termguicolors` para cores 24-bit
- 🖼️ Statusline global (laststatus=3)
- 🧵 Smooth scroll habilitado
- 📊 Sign column e number width otimizados

### 5. **Statusline com Lualine**
- 🎯 Modo, branch git, diagnostics
- 📁 Filepath com indicador de modificações
- 🔢 Posição do cursor, encoding, file format
- 🎨 Cores harmonizadas com Monokai-Pro

## 🚀 Como Usar

### Navegação entre Vim e Tmux
```
Ctrl+h  → Move left
Ctrl+j  → Move down
Ctrl+k  → Move up
Ctrl+l  → Move right
```

### Atalhos Nvim
```
<C-a>           → Selecionar tudo
te              → Nova tab
<Tab>/<S-Tab>   → Próxima/anterior tab
ss              → Split horizontal
sv              → Split vertical
sh/sj/sk/sl     → Mover entre splits
<C-b>           → Toggle NvimTree
```

### Atalhos Tmux
```
Ctrl+Space      → Prefix
<Prefix>:       → Command mode
<Prefix>c       → Nova janela
<Prefix>"       → Split vertical
<Prefix>%       → Split horizontal
<Prefix>h/j/k/l → Navegar panes (ou Ctrl+hjkl)
<Prefix>H/J/K/L → Redimensionar panes
<Prefix>r       → Reload config
```

## 📋 Arquivos Modificados

- `~/.config/nvim/init.lua` - Config principal (sem mudanças)
- `~/.config/nvim/lua/config/options.lua` - Opções melhoradas
- `~/.config/nvim/lua/config/lazy.lua` - Colorscheme ativado
- `~/.config/nvim/lua/plugins/colorscheme.lua` - Monokai-Pro customizado
- `~/.config/nvim/lua/plugins/lualine.lua` - Nova statusline (CRIADO)
- `~/.config/nvim/lua/plugins/tmux-navigator.lua` - Integração Tmux melhorada
- `~/.tmux.conf` - Configuração Tmux otimizada
- `~/.zshrc` - Tema Spaceship + FiraCode Nerd Font

## ✨ Próximos Passos Opcionais

1. **Teste no terminal:**
   ```bash
   nvim
   # Abra Tmux: Ctrl+Space + c
   # Teste navegação com Ctrl+hjkl
   ```

2. **Customize cores (se necessário):**
   - Edite cores no `~/.config/nvim/lua/plugins/lualine.lua`
   - Ou em `~/.tmux.conf` (monokai_* variables)

3. **Adicione plugins adicionais:**
   - Treesitter para syntax highlighting avançado
   - Nvim-tree se quiser gerenciador de arquivos visual
   - Telescope para fuzzy finding

## 🔧 Troubleshooting

**Símbolos estranhos?**
- Confirme que você configurou FiraCode Nerd Font no seu terminal emulator

**Cores incorretas no Tmux?**
- Use: `echo $TERM` - deve ser `xterm-256color` ou similar
- No terminal emulator, confirme suporte a 256 cores

**Navegação Ctrl+hjkl não funciona?**
- Reinicie Tmux: `tmux kill-server` e abra novamente

**Lualine não aparece?**
- Execute `:Lazy sync` no Nvim para instalar plugins

## 📞 Verificação Rápida

Tudo instalado? ✅
```bash
nvim --version     # 0.12.4 ou superior
tmux -V            # 3.4 ou superior
echo $SHELL        # /usr/bin/zsh
```
