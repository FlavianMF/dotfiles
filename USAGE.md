# Como Usar Este Repositório

## 📥 Primeiras Vezes

### Opção 1: Clone e Instale (Recomendado)
```bash
# Clone
git clone <seu-repo-url> ~/dotfiles
cd ~/dotfiles

# Instale como usuário normal, SEM sudo (o script pede a senha quando precisar)
./install.sh

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

## 🤖 Harnesses de IA (Claude Code, Codex, OpenCode, Antigravity CLI)

```bash
./install.sh --dry-run                      # mostra o que mudaria nos harnesses, sem mudar nada
./install.sh --harness-only                 # só links + harnesses (sem apt, shell, tmux)
./install.sh --harness-only --with=codex,opencode   # instala também Codex e OpenCode (npm, ~/.local)
./install.sh --harness-only --with=antigravity      # instala o agy (~/.local/bin) e aplica a config em ~/.gemini
```

- **Instruções**: edite só `agents/AGENTS.md`. O Claude importa via `claude/CLAUDE.md`;
  Codex, OpenCode e Antigravity leem o link.
- **Plugins do Claude**: declare em `claude/settings.json` (`enabledPlugins` +
  `extraKnownMarketplaces`) e rode `make harness`. Depois `make plugins-freeze` e commite
  `claude/plugins.lock.json`. Para atualizar: `make plugins-update` e revise o diff do lock.
- **Skills**: ficam em `~/.agents/skills`. Instale com `npx skills add <repo> -g`; para o
  Claude ver, a skill precisa de link em `~/.claude/skills` (o skills CLI cria com
  `-a claude-code`).
- **Codex**: edite `codex/config.base.toml`, rode `make harness` e confira `make codex-drift`.
  Perfil sem sandbox: `codex --profile yolo`.
- **Harness²** (componente `harness2`, desligado): `./install.sh --with=harness2` ou `make harness2-install`.
  Clona o framework de recursive agent harnessing (Google Research) em `~/projetos_harness/harness2`,
  gerencia o venv Python 3.12+ com `uv` e expõe executáveis em `~/.local/bin` (`harness2`, `harness2-setup`,
  `harness2-check`, `harness2-demo`, `harness2-judge`, `harness2-report`, `harness2-bridge`). Configure
  `secrets/harness2.env` (a partir de `secrets/harness2.env.example`) e teste com `make harness2-check`.
  Aliases de terminal no zsh: `harness2-cd` e `harness2-venv`. Documentação completa em `harness2/README.md`.
- **Antigravity CLI** (`agy`): edite `antigravity/mcp_config.base.json` ou
  `antigravity/settings.base.json` (ou `antigravity/hooks.base.json`) e rode `make antigravity-config` (merge: o que o `agy`
  gravou sozinho fica). Skills vêm de `~/.agents/skills` via `skills.json` (renderizado com caminho absoluto). Os hooks do second brain
  (`SessionStart`, `PostToolUse`, `Stop`) rodam por padrão no `agy`; `SECOND_BRAIN_HOOKS=0` no shell os desliga.
  Rode o `make antigravity-config` no checkout principal. Sem MCP do GitHub; veja `antigravity/README.md`.
- **Modos de sessão**: `claude-dev`, `claude-review`, `claude-research`.
- **Hooks opcionais por projeto** (em `.claude/settings.local.json` do projeto):
  `"env": {"CLAUDE_FORMAT_TYPECHECK": "1"}` liga format/typecheck no fim do turno;
  `"env": {"SECOND_BRAIN_HOOKS": "0"}` desliga os hooks do second brain.
- **Peças do ECC** (componente `ecc`, desligado): `./install.sh --harness-only --with=ecc`.
  Linka skills (`verification-loop`, `eval-harness`, `search-first`, `gan-style-harness`,
  `ecc-security-review`), agents `ecc-*` (revisores e build resolvers de TS/Python/C++/Rust,
  GAN planner/generator/evaluator etc.) e regras por linguagem que só carregam quando o
  Claude lê um arquivo daquela extensão. Para atualizar o ECC, siga `vendor/ecc/SOURCE.md`.
- **Jev tools** (componente `jev`, desligado): `./install.sh --harness-only --with=jev` clona
  e compila `~/projetos_claude/jev-workflow` (repo privado). O hook `jev-e.sh`
  (UserPromptSubmit) já vem ligado em `claude/settings.json` em **modo sombra**
  (`JEV_MODE_E=shadow`): sugere uma skill, grava só em `~/.local/state/jev-tools/log.jsonl` e
  não escreve nada para o modelo; sem o build ele não faz nada. Desligar na hora:
  `JEV_TOOL_E=0` (em `.claude/settings.local.json`) ou `node ~/projetos_claude/jev-workflow/dist/cli.js off`.
  Promover a ativo é trocar `JEV_MODE_E` para `active` (só depois do critério da etapa 8 do plano).
- **ECC completo por projeto** (plugin `ecc@ecc`: 387 skills/commands, 68 agents): fica
  instalado e **desligado** no `claude/settings.json`, porque custa ~45k tokens em toda
  sessão (`claude plugin details ecc@ecc`). Ligue só onde for usar:
  `make ecc-on DIR=~/proj` (rules completas do ECC, incluindo `rules/common`, que carrega
  sempre e manda delegar a agents `ecc:*`) ou `make ecc-on DIR=~/proj NO_COMMON=1` (só os
  packs de linguagem). `make ecc-off DIR=~/proj` desfaz e `make ecc-status DIR=~/proj`
  mostra o estado efetivo (local, projeto ou usuário). `make ecc-auto DIR=~/proj` liga o
  ECC só se o projeto for web, C ou backend Node (detecção em `claude/ecc-detect.sh`, filtros em
  `claude/ecc-auto.conf`); web liga os packs do framework, C e Node só o plugin. `make ecc-off`
  cria `.claude/ecc.off`, que o `ecc-auto` respeita; `make ecc-on` remove o marcador. Pack
  específico: `make ecc-on DIR=~/proj PACKS=web,typescript`; só o plugin: `NO_RULES=1`. Com `SECOND_BRAIN_HOOKS=1`, o `SessionStart`
  injeta uma linha com esse estado (`ECC desligado (usuário). ...`). Nada entra no git do projeto (`.git/info/exclude`). Reinicie o Claude
  Code no projeto depois de ligar ou desligar.
  Hooks do ECC: perfil completo quando ligado (`ECC_HOOK_PROFILE=strict`, nada em `ECC_DISABLED_HOOKS`):
  rodam GateGuard, config-protection, `pre-compact`, `session-end` com resumo, `skill-tracker`, `cost-tracker`,
  quality gates e a observação do continuous-learning (log de tool calls em `~/.local/share/ecc-homunculus`).
  O observer Haiku em background liga com `make ecc-observer-config`. `ECC_OBSERVE_SKIP_PATHS` exclui diretórios
  com `secrets`, `.ssh` e `.aws`; `ECC_SKIP_OBSERVE=1` desliga o log de tool calls.
  `ECC_INSTINCT_CONFIDENCE_THRESHOLD=1` bloqueia a injeção de instincts no SessionStart (a confiança máxima do ECC é 0,9) e mantém
  o resto. É temporário, até 2026-10-29: depois disso, remova a variável de `claude/settings.json` ao revisar os instincts.
  `ECC_MAX_INJECTED_INSTINCTS=0` não funciona (volta ao padrão 6). `make ecc-observer-config` também deixa a raiz do
  homunculus em modo `0700`.
- **Deny list**: `rm -rf`, `sudo`, `chmod 777`, `ssh`/`scp`/`nc`, `curl | bash` e leitura de
  segredos estão bloqueados nos 3 harnesses. Precisa de um deles? Rode você mesmo no terminal
  (no Claude, `! comando`).
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


## 🧠 Second Brain Projects & Dashboard Web (Tailscale)

Para expor o dashboard com autenticação segura e acesso pelo celular via Tailscale:

1. Habilite HTTPS na tailnet (painel administrativo do Tailscale -> DNS -> HTTPS Certificates).
2. Rode `make sb-web-token` e `make sb-web-install`.
3. Rode `tailscale serve --bg --https=443 http://127.0.0.1:8765`.
4. Confira que `curl -s -o /dev/null -w '%{http_code}' https://loq-wsl-flv.tail48e6f7.ts.net/api/projects` imprime `401`. Se imprimir outro código, desligue o serve com `tailscale serve reset` e reporte.
5. No celular, abra `https://loq-wsl-flv.tail48e6f7.ts.net/login` e cole o token.

> [!CAUTION]
> **Segurança:** Nunca use `tailscale funnel`, pois ele expõe o serviço para a internet pública (use apenas `tailscale serve`). O token gerado por `make sb-web-token` é exibido apenas uma vez no terminal e protegido com permissão `0600` em `secrets/sb-web.env`; evite salvá-lo em histórico ou comandos expostos.

### Configuração da Task "Secretário" no Traycer

Para ativar o Secretário de Projetos em segundo plano:

1. No Traycer, crie uma Task intitulada `Secretário de Projetos` vinculando os repositórios `dotfiles`, `obsidian_vault` e `outlet_promo`.
2. Configure o prompt do Secretário com o conteúdo de `00_META/projects/secretario.md`.
3. Anote o `taskId` e o `agentId` da Task do Secretário e registre-os no manifesto do vault (`00_META/projects/manifest.yaml`):
   ```yaml
   secretary:
     traycer_task: "<taskId>"
     agent_id: "<agentId>"
   ```
4. O Secretário acordará a cada 20-30 minutos, sincronizará o estado com `sb projects activity set`, verificará quotas e despachará implementadores autorizados via `sb projects gate`.

## 🎮 Controle Remoto & Home Assistant

O repositório inclui automação para controle remoto da máquina física e do Windows via Home Assistant (app mobile no celular) e utilitário de linha de comando no WSL2:

### 1. Linha de Comando no WSL2 (`bin/pc-ctl`)
Utilitário para gerenciar energia, aplicativos e diagnósticos com suporte a `--dry-run`:
```bash
# Instalar o binário no PATH (~/.local/bin/pc-ctl)
make pc-ctl-install

# Checar status do sistema, Windows Host, SSH e Traycer
pc-ctl status

# Simulação segura de comandos
pc-ctl --dry-run shutdown
pc-ctl --dry-run sleep
pc-ctl --dry-run app obsidian

# Executar testes unitários TDD
make pc-ctl-test
```

#### Configuração de Wake e Tarefas Elevadas (`wake-setup`)
Configuração única e idempotente executada com elevação de Administrador no Windows:
```bash
# Simulação segura do que será configurado no Windows
pc-ctl --dry-run wake-setup

# Execução real (solicita prompt UAC no Windows uma única vez)
pc-ctl wake-setup
```
O que o `wake-setup` realiza:
1. Executa `Install-PcCtl.ps1`, copiando os scripts para `C:\ProgramData\pc-ctl\` e restringindo as permissões (ACL) para que apenas **Administradores** e **SYSTEM** possam gravar ou alterar os scripts. A ACL usa SIDs (`*S-1-5-32-544`, `*S-1-5-18`, `*S-1-5-32-545`), então funciona em Windows de qualquer idioma, e o script aborta se o `icacls` falhar.
2. Cria o arquivo de requisição `C:\ProgramData\pc-ctl\request.json` com leitura e escrita para usuários comuns (`(R,W)`, sem permissão de apagar).
3. Habilita os temporizadores de ativação (Wake Timers) do Windows na tomada (AC) e na bateria (DC) para o subgrupo `SUB_SLEEP` (`BD3B718A-0680-4D9D-8AB2-E1D2B4AC806D`).
4. Registra a tarefa agendada `pc-ctl-power` com privilégios elevados (`RunLevel Highest`), executando `Set-PowerProfile.ps1` sem solicitar UAC ao usuário durante o uso diário. Os passos 3 e 4 rodam dentro do script elevado, com `Register-ScheduledTask` e `powercfg`.

Se o script elevado falhar, o `wake-setup` sai com código 1 e grava `failed` no log.

#### Modos de Energia e Refrigeração (`power-mode`)
Permite selecionar perfis de energia do Windows e modos térmicos Lenovo sem prompt de UAC:
```bash
# Perfis disponíveis: eco, balanced, llm-boost, max, status

# Ativar perfil equilibrado padrão
pc-ctl power-mode balanced

# Ativar perfil econômico silencioso (SmartFanMode 1, Dynamic Boost 0)
pc-ctl power-mode eco

# Ativar otimização para inferência local com TTL de 90 minutos (padrão 2h, teto 4h)
pc-ctl power-mode llm-boost --ttl 90m

# Ativar perfil de desempenho máximo
pc-ctl power-mode max --ttl 2h

# Consultar perfil ativo e TTL restante
pc-ctl power-mode status

# Simulação com --dry-run (mostra a escrita no request.json e o schtasks /run)
pc-ctl --dry-run power-mode llm-boost --ttl 90m
```
Regras de segurança e invariantes:
- **Proteção de Bateria**: Os modos de alta potência (`llm-boost` e `max`) são recusados se o computador estiver na bateria (`on_battery`) ou se o estado da tomada não puder ser lido (`power_unknown`). O motivo vai para o log.
- **Canal sem UAC**: O comando do WSL2 escreve apenas no arquivo validado `C:\ProgramData\pc-ctl\request.json` e dispara a tarefa `schtasks /run /tn "pc-ctl-power"`. O script elevado valida rigorosamente o perfil contra a lista fixa e o TTL contra o teto.
- **Reversão Automática**: No fim do TTL (padrão de 2 horas, teto de 4 horas), a tarefa elevada agenda `pc-ctl-power-revert` para retornar automaticamente ao perfil `balanced`.
- **Log de Auditoria**: Cada decisão é registrada em formato JSON Lines em `~/.local/state/pc-ctl/sleep.log` com campos `ts`, `cmd`, `result` (`applied|refused|failed|dry-run|requested`), `reason`, `profile` e `until`.
- **Resultado real**: o `schtasks /run` é assíncrono. O `power-mode` grava `requested` no log. A tarefa elevada grava `applied`, `refused` ou `failed` no `state.json`, e `pc-ctl power-mode status` mostra o último pedido.

### 2. Instalação e Conexão do Tailscale
Para habilitar a rede mesh criptografada no Linux/WSL2 ou Windows:
```bash
# Instalar Tailscale no WSL2
make tailscale-install

# Conectar esta máquina à sua tailnet
sudo tailscale up

# Verificar status e IP Tailscale
make tailscale-status
```
No Windows, execute o instalador interativo: `.\install.ps1` (e selecione Tailscale).

### 3. Stack da VPS (Home Assistant + Mosquitto)
```bash
# Gerar pacote pronto para deploy na VPS
make ha-vps-pack
# Envie o pacote para a VPS e siga o passo a passo em homeassistant/README.md
```

### 4. Integração de MCP para Agentes de IA (`ha-mcp`)
Conecta seus agentes locais (Claude Code, Gemini CLI, Antigravity, OpenCode, Cursor) ao Home Assistant:
```bash
# Copiar o template de credenciais e preencher seu token
cp secrets/mcp.env.example secrets/mcp.env

# Validar conectividade Tailscale (100.105.143.75:8123) e uvx
make ha-mcp-check

# Simular a configuração dos clientes de IA
make ha-mcp-config DRY_RUN=1

# Aplicar a configuração
make ha-mcp-config
```

### 5. Provisionamento no Windows (HASS.Agent)
Em um terminal PowerShell como Administrador no Windows:
```powershell
.\powershell\hass-agent\install-hass-agent.ps1 -RegisterCommands
```

## 🆘 Troubleshooting Comum

### "Permission denied" ao rodar install.sh
`chmod +x` quase nunca resolve: o arquivo já é executável no git. Causa comum: arquivos de
root na sua home, deixados por um `sudo ./install.sh` antigo.
```bash
find ~ -user root -not -path '*/.git/*' | head
sudo chown -R "$USER:$USER" ~/.local ~/.npm ~/.oh-my-zsh ~/.tmux ~/.cache \
  ~/.copilot ~/.dotfiles-backup ~/.gitconfig.local
cd ~/dotfiles && ./install.sh   # sem sudo
```
Ainda falha? `bash -x ./install.sh 2>&1 | tail -20` mostra o primeiro `Permission denied`.

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
