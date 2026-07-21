# Dev Environment Setup

Uma configuração completa e otimizada de ambiente de desenvolvimento com **Zsh**, **Oh-My-Zsh**, **Neovim**, **Tmux** e **FiraCode Nerd Font**.

## 🎯 O que é Incluído

- ✨ **Zsh** com Oh-My-Zsh + Spaceship Prompt
- 🎨 **Neovim** com LazyVim + Monokai-Pro + Lualine
- 🔗 **Tmux** com integração seamless com Nvim
- 🖋️ **FiraCode Nerd Font** para renderização correta
- 🚀 Navegação integrada: Vim ↔ Tmux ↔ Zsh

## 📋 Requisitos

- Ubuntu 22.04+ ou Debian
- Internet para download de pacotes
- `sudo` access

## ⚡ Instalação Rápida

```bash
git clone <repo-url> dotfiles
cd dotfiles
chmod +x install.sh
./install.sh
```

O script vai:
1. ✅ Instalar todas as dependências
2. ✅ Instalar fontes Nerd Font (FiraCode)
3. ✅ Instalar Zsh + Oh-My-Zsh
4. ✅ Instalar Neovim
5. ✅ Instalar Tmux com plugins
6. ✅ Copiar/symlink todas as configurações
7. ✅ Definir Zsh como shell padrão

## 🎮 Navegação Rápida

### Tmux
```
Ctrl+Space + n  →  próxima aba
Ctrl+Space + p  →  aba anterior
Ctrl+Space + c  →  nova janela
Ctrl+Space + "  →  split horizontal
Ctrl+Space + %  →  split vertical
Ctrl+Space + r  →  reload config
```

### Nvim
```
<Tab>/<S-Tab>  →  próxima/anterior tab
ss             →  split horizontal
sv             →  split vertical
sh/sj/sk/sl    →  mover entre splits
<C-b>          →  toggle NvimTree
```

### Integração Vim ↔ Tmux
```
Ctrl+h/j/k/l   →  navega entre splits Vim e panes Tmux
```

## 📁 Estrutura do Repositório

```
.
├── README.md                  # Este arquivo
├── install.sh                 # Script de instalação principal
├── .gitignore                 # Git ignore
├── config/                    # Arquivos de configuração
│   ├── zsh/
│   │   └── .zshrc            # Configuração Zsh + Spaceship
│   ├── nvim/                 # Configuração Neovim
│   │   ├── init.lua
│   │   ├── lua/config/
│   │   ├── lua/plugins/
│   │   └── SETUP.md          # Documentação visual
│   └── tmux/
│       └── .tmux.conf        # Configuração Tmux
└── scripts/
    └── fonts-install.sh      # Script para instalar fontes
```

## 🔧 Pós-Instalação

### 1. Configurar Terminal Emulator
Configure a fonte do seu terminal para **FiraCode Nerd Font** (ou JetBrains Mono Nerd Font):
- GNOME Terminal: Preferências → Fonte
- VS Code: Settings → Font Family
- iTerm2: Preferences → Profiles → Font

### 2. Iniciar Zsh
```bash
exec zsh
```

### 3. Instalar Plugins Nvim (primeira vez)
```bash
nvim
# Dentro do Nvim:
:Lazy sync
```

### 4. Instalar Plugins Tmux
```bash
# Se usar tmux-plugin-manager (tpm)
tmux
# Depois: Ctrl+Space + I (instala plugins)
```

## 🎨 Personalizações

### Mudar Tema Nvim
Edite `config/nvim/lua/plugins/colorscheme.lua`:
```lua
-- Descomente e ative outro tema
-- require("sonokai").setup({...})
```

### Mudar Prefixo Tmux
Edite `config/tmux/.tmux.conf`:
```bash
set -g prefix C-a  # Mude para o que preferir
```

### Adicionar Plugins Nvim
Crie arquivo em `config/nvim/lua/plugins/seu-plugin.lua`:
```lua
return {
  {
    "usuario/seu-plugin",
    opts = {...},
  },
}
```

## 🐛 Troubleshooting

### "Símbolos estranhos no terminal?"
→ Configure FiraCode Nerd Font no seu terminal emulator

### "Nvim não carrega plugins?"
```bash
nvim
:Lazy sync
:quitall
nvim
```

### "Tmux não responde a Ctrl+Space?"
```bash
tmux kill-server
# Abra novamente
```

### "Zsh não está sendo usado?"
```bash
chsh -s /usr/bin/zsh
exec zsh
```

## 📚 Referências

- [Oh-My-Zsh](https://github.com/ohmyzsh/ohmyzsh)
- [LazyVim](https://www.lazyvim.org)
- [Neovim](https://neovim.io)
- [Tmux](https://github.com/tmux/tmux)
- [FiraCode Font](https://github.com/tonsky/FiraCode)
- [Spaceship Prompt](https://spaceship-prompt.sh)

## 💡 Dicas

1. **Usar com Docker:**
   ```dockerfile
   FROM ubuntu:24.04
   COPY . /root/dotfiles
   RUN cd /root/dotfiles && ./install.sh
   ```

2. **Atualizar configurações:**
   ```bash
   cd ~/dotfiles
   git pull
   ./install.sh --update
   ```

3. **Backup suas configs:**
   ```bash
   ./install.sh --backup
   ```

## 📝 Notas

- Este setup é otimizado para Ubuntu 22.04+
- Funciona bem em WSL2 (Windows Subsystem for Linux)
- Compatível com macOS (com pequenos ajustes)
- Suporta ambientes com e sem GUI

## 🤝 Contribuindo

Sugestões de melhorias são bem-vindas! Faça um fork e crie um PR.

## 📄 Licença

MIT License - sinta-se livre para usar e modificar

---

**Criado com ❤️ para desenvolvedores que apreciam bom terminal**
