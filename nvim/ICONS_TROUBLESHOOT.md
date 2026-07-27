# Solucionar Problemas com Ícones no Nvim

## ✅ Checklist Rápido

- [ ] FiraCode Nerd Font instalada?
- [ ] Terminal configurado para FiraCode Nerd Font?
- [ ] Nvim foi reiniciado?
- [ ] `:Lazy sync` foi executado?

## 🔍 Diagnosticar o Problema

### 1. Verificar Fonte Instalada

```bash
fc-list | grep -i firacode
```

Se não aparecer nada, instale:
```bash
mkdir -p ~/.local/share/fonts
cd ~/.local/share/fonts
wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/FiraCode.zip
unzip -o FiraCode.zip
rm FiraCode.zip
fc-cache -fv ~/.local/share/fonts
```

### 2. Verificar Terminal

Abra seu terminal e verifique em **Preferências** ou **Settings**:
- **GNOME Terminal**: Preferências → Perfil → Fonte
- **VS Code**: `Ctrl+,` → "Font Family" → FiraCode
- **iTerm2**: Preferences → Profiles → Font
- **Konsole**: Settings → Edit Profile → Font

Selecione: **FiraCode Nerd Font** (ou **FiraCode Nerd Font Mono**)

### 3. Verificar Nvim Config

Dentro do Nvim, execute:
```vim
:set encoding?
:echo has('nvim')
:echo vim.g.have_nerd_font
```

Deve retornar `true` para `have_nerd_font`.

### 4. Verificar Plugin

```vim
:Lazy show nvim-web-devicons
```

Se não aparecer, force sincronização:
```vim
:Lazy sync
:q
nvim
```

## 🐛 Problemas Comuns

### Problema: Quadradinhos pretos em vez de ícones

**Causa**: Fonte não está configurada no terminal

**Solução**:
1. Abra Preferências do Terminal
2. Selecione **FiraCode Nerd Font**
3. Reinicie o terminal
4. Abra novamente o Nvim

### Problema: Ícones aparecem mas com cores erradas

**Causa**: Terminal não suporta cores 24-bit

**Solução**:
```bash
# Verificar suporte de cores
echo $TERM
# Deve ser: xterm-256color ou alacritty ou screen-256color

# Se não for, configure em ~/.zshrc:
export TERM=xterm-256color
```

### Problema: Ícones só aparecem em algumas abas

**Causa**: Plugins não estão carregados

**Solução**:
```vim
:Lazy show lualine.nvim
:Lazy show nvim-tree
:Lazy sync
```

### Problema: Ícones aparecem no Dashboard mas não em NvimTree

**Causa**: NvimTree não está usando web-devicons

**Solução**: Verifique `~/.config/nvim/lua/plugins/ui.lua` ou busque por nvim-tree:
```vim
:Lazy show nvim-tree
```

## 🔧 Debug Mode

Execute dentro do Nvim:

```vim
" Ver informações sobre ícones
:lua require('nvim-web-devicons').has('lua')

" Ver se lualine está usando ícones
:Lazy show lualine.nvim
:LualineToggle

" Ver informações de terminal
:echo &encoding
:echo &termguicolors
```

## 📝 Teste Rápido

Dentro do Nvim, crie um arquivo de teste:

```bash
nvim test_icons.lua
```

Dentro do arquivo, veja se aparecem ícones no lado esquerdo (Nvim Tree) ou na statusline (Lualine).

## 🎯 Solução Completa

Se nada funcionar, faça uma limpeza completa:

```bash
# Backup config
cp -r ~/.config/nvim ~/.config/nvim.backup

# Limpar cache
rm -rf ~/.cache/nvim
rm -rf ~/.local/share/nvim/

# Reinstalar
cd ~/.config/nvim
git pull
nvim
:Lazy sync
:qa

# Testar
nvim
```

## ✨ Verificação Final

Se tudo funcionar corretamente, você deve ver:
- ✅ Ícones de arquivo no Dashboard
- ✅ Ícones no Nvim Tree (se ativo com `<C-b>`)
- ✅ Ícones na Lualine (statusline)
- ✅ Ícones no Git Status (se tiver)

## 📞 Se Ainda Não Funcionar

```vim
" Execute este comando dentro do Nvim:
:checkhealth
```

Procure por problemas em:
- `nvim`
- `nvim.web_devicons`

Se houver avisos, execute as sugestões.

---

**Dica**: Se a fonte parecer pequena, você pode aumentar no terminal:
- **GNOME Terminal**: Pressione `Ctrl++`
- **VS Code**: `Ctrl++`
- **iTerm2**: `Cmd++`
