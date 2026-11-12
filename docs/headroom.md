# Headroom neste dotfiles

O Headroom é um proxy local que comprime o contexto antes de ele chegar ao provedor. Esta página descreve o que o dotfiles liga a ele e como você checa o proxy.

Para o motivo da compressão, leia [[Headroom Preserva o Prefixo do Cache e Comprime Só o Turno Recente]]. Para o lugar do Headroom no corte de tokens, leia [[Router de Tokens em 3 Camadas - Carga, Contexto e Modelo]].

## Instalação persistente

O Headroom fica em `~/.local/opt/headroom`. É um clone do repositório `headroomlabs-ai/headroom` com um venv em `.venv`. O link `~/.local/bin/headroom` aponta para `~/.local/opt/headroom/.venv/bin/headroom`. A versão medida em 2026-11-12 foi `0.44.1-dev`.

O dotfiles não instala o Headroom. Nenhum script do repositório cria esse clone nem o venv. O dotfiles só aponta clientes para o proxy.

## O que o dotfiles liga

O proxy escuta em `127.0.0.1:8787`. Estes arquivos usam essa URL:

- `claude/settings.json` define `ANTHROPIC_BASE_URL` no bloco `env`. O Claude Code lê esse arquivo por `~/.claude/settings.json`, que é um link para ele.
- `antigravity/mcp_config.base.json` registra o servidor MCP `headroom`. O comando é `/home/flv/.local/bin/headroom mcp serve`, com o caminho absoluto do usuário `flv`.
- `traycer/setup_headroom.sh` configura o Traycer. Ele grava `ANTHROPIC_BASE_URL`, `GOOGLE_GEMINI_BASE_URL` e `AGY_ACP_CCPA_BASE_URL` com `traycer config env set`. Ele também atualiza `envOverrides` em `~/.traycer/host/config/provider-overrides.json` com `jq`.
- `traycer/install.sh` chama `setup_headroom.sh` na instalação inicial e repassa `--dry-run`.
- `traycer/agy-acp-wrapper` copia `GOOGLE_GEMINI_BASE_URL` para `AGY_ACP_CCPA_BASE_URL`. O host do Traycer remove as variáveis `AGY_ACP_*` antes de iniciar o `agy_acp_server`.

Para ver o que o script muda, sem gravar nada, rode `bash traycer/setup_headroom.sh --dry-run`.

## Subir o proxy

Rode este comando num terminal que fique aberto:

```bash
~/.local/bin/headroom proxy --host 127.0.0.1 --port 8787
```

Esse é o comando do processo que estava ativo em 2026-11-12. As opções acima são os valores padrão. O dotfiles não tem unidade systemd nem script que suba o proxy no boot. Depois de reiniciar a máquina, suba o proxy à mão.

O `headroom install apply` instala um deploy persistente. O comando aparece em `headroom install --help`. Ninguém o testou neste repositório.

## Checar o proxy

Rode `headroom doctor`. O comando sai com 0 se tudo estiver bem, 1 se houver avisos e 2 se o proxy estiver fora do ar.

Estes endereços respondem 200 quando o proxy está ativo:

| Endereço | Conteúdo |
| --- | --- |
| `http://127.0.0.1:8787/health` | Estado do serviço e se ele está pronto. |
| `http://127.0.0.1:8787/stats` | JSON com requisições, tokens removidos e custo estimado. |
| `http://127.0.0.1:8787/dashboard` | Página HTML com a economia acumulada. |

O comando `headroom dashboard` abre a mesma página no navegador.

## Risco do `ANTHROPIC_BASE_URL`

O `claude/settings.json` fixa `ANTHROPIC_BASE_URL` em `http://127.0.0.1:8787` para toda sessão do Claude Code. Isso cria dois riscos:

- Se o proxy estiver parado, a sessão perde o caminho para a API. Não testei a mensagem de erro. Suba o proxy antes de abrir o Claude Code.
- O `headroom doctor` avisa que o Claude Code 2.1.322 desativa o comando `/remote-control` quando `ANTHROPIC_BASE_URL` aponta para um endpoint próprio.

Para uma sessão sem o proxy, remova a chave de `claude/settings.json`. Essa edição vale para todas as sessões, pois o arquivo é um link para o repositório.

## Fontes

- Spec "Spec: Headroom and Traycer Setup Integration in Dotfiles" (artifact do épico, 2026-11-12).
- `traycer/setup_headroom.sh`, `traycer/install.sh`, `traycer/agy-acp-wrapper`, `claude/settings.json` e `antigravity/mcp_config.base.json`.
- Medidas do proxy em execução e saída do `headroom doctor`, em 2026-11-12.
