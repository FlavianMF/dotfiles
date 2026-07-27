# Solução para Ícones no Terminal Zutty

## ⚠️ O Problema

Zutty é um terminal minimalista que pode não ter suporte completo para fontes Nerd Font customizadas via GUI ou CLI.

## ✅ Soluções

### Opção 1: Instalar GNOME Terminal (Recomendado)

```bash
sudo apt-get install gnome-terminal
```

Depois configure a fonte:
1. Abra GNOME Terminal
2. Menu (≡) → Preferências
3. Perfil padrão → Texto → Fonte
4. Selecione "FiraCode Nerd Font" ou "JetBrains Mono Nerd Font"

### Opção 2: Instalar Alacritty (Terminal Moderno)

```bash
sudo apt-get install alacritty
```

Depois crie `~/.config/alacritty/alacritty.toml`:

```toml
[font]
family = "FiraCode Nerd Font Mono"
size = 11.0

[window]
opacity = 0.95
```

### Opção 3: Usar xterm com configuração

```bash
sudo apt-get install xterm
```

Crie `~/.Xresources`:

```
xterm*faceName: FiraCode Nerd Font Mono
xterm*faceSize: 11
xterm*termName: xterm-256color
```

Depois carregue:
```bash
xrdb -merge ~/.Xresources
```

### Opção 4: Manter Zutty mas com workaround

Se quer manter Zutty, o problema pode ser que:
1. Zutty usa renderização de GPU e pode não reconhecer Nerd Fonts bem
2. Considere apenas usar caracteres ASCII nos ícones (fallback)

## 🎯 Recomendação

**GNOME Terminal** é a melhor opção:
- Interface gráfica fácil
- Suporte completo a Nerd Fonts
- Integra bem com GNOME

```bash
# Instalar e usar
sudo apt-get install gnome-terminal
gnome-terminal
```

Depois:
1. Menu → Preferências
2. Selecione a fonte "FiraCode Nerd Font"
3. Abra Nvim e veja os ícones! ✨

## ✅ Testar Depois

```bash
nvim
# Devem aparecer ícones no Dashboard e na Lualine
:Lazy show nvim-web-devicons
```

---

**Qual opção prefere?**
