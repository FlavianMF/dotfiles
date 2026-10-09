# Quick Start Guide

## 30 segundos para um ambiente dev completo

### 1. Clone o repositório
```bash
git clone <seu-repo-url> ~/dotfiles
cd ~/dotfiles
```

### 2. Execute o script de instalação
```bash
./install.sh
```

> Rode como **usuário normal, sem `sudo`**. O script chama `sudo` sozinho nos passos
> que precisam (apt, `/opt`, `/etc/apt`) e pede a senha. Rodar tudo com `sudo` deixa
> arquivos de root na sua home e quebra execuções seguintes.
> Se `./install.sh` der `Permission denied` por falta do bit de execução, use `bash install.sh`.

**Deu `Permission denied`?** Provavelmente sobrou arquivo de root de um `sudo ./install.sh` antigo:
```bash
find ~ -user root -not -path '*/.git/*' | head
sudo chown -R "$USER:$USER" ~/.local ~/.npm ~/.oh-my-zsh ~/.tmux ~/.cache \
  ~/.copilot ~/.dotfiles-backup ~/.gitconfig.local
./install.sh
```

### 3. Reabra seu terminal
```bash
exec zsh
```

### 4. Configure a fonte no seu terminal
- **GNOME Terminal**: Preferências → Fonte → FiraCode Nerd Font
- **VS Code**: Ctrl+, → "Font Family" → FiraCode Nerd Font
- **iTerm2**: Preferences → Profiles → Font

### 5. Instale plugins Neovim
```bash
nvim
:Lazy sync
:quitall
```

### 6. Instale plugins Tmux
```bash
tmux
Ctrl+Space + I
```

## ✅ Pronto!

Seu ambiente está completamente configurado.

### Comandos úteis

**Tmux:**
```
Ctrl+Space + n      → próxima janela
Ctrl+Space + p      → janela anterior
Ctrl+Space + c      → criar janela
Ctrl+Space + %      → split vertical
Ctrl+Space + "      → split horizontal
```

**Nvim + Tmux:**
```
Ctrl+h/j/k/l  → navega entre Vim e Tmux automaticamente
```

**Zsh:**
```
<Tab>           → autocompletar
<Ctrl+R>        → buscar no histórico
```

## 🆘 Problemas?

### "Símbolos estranhos no terminal"
→ Configure **FiraCode Nerd Font** no seu terminal

### "Plugins não carregam no Nvim"
```bash
nvim
:Lazy sync
:checkhealth
```

### "Tmux não responde a Ctrl+Space"
```bash
tmux kill-server
tmux
```

## 📚 Documentação Completa

Veja [README.md](README.md) para mais informações.
