# Decisões

Registro curto das decisões deste dotfiles. Cada item tem decisão, motivo e data. A data é a do artifact ou do commit que registra a decisão. Para o detalhe de uso, leia [headroom.md](headroom.md) e [skills.md](skills.md).

## 1. Headroom como proxy persistente fora do repositório

- **Data:** 2026-11-12.
- **Decisão:** o Headroom roda de `~/.local/opt/headroom`, com o link `~/.local/bin/headroom`. O dotfiles só aponta os clientes para `http://127.0.0.1:8787`.
- **Motivo:** a spec "Spec: Headroom and Traycer Setup Integration in Dotfiles" quer o proxy e a ferramenta MCP ativos numa máquina nova, sem passo manual. A spec não registra por que o código do Headroom fica fora do repositório.
- **Consequência:** nada no dotfiles instala nem sobe o proxy. Se o proxy parar, o Claude Code perde o caminho para a API, pois `claude/settings.json` fixa `ANTHROPIC_BASE_URL`.
- **Contexto:** [[Headroom Preserva o Prefixo do Cache e Comprime Só o Turno Recente]].

## 2. CCPA do Antigravity passa pelo proxy

- **Data:** 2026-11-12 (commit `ca09296`, PR #15).
- **Decisão:** `traycer/setup_headroom.sh` grava `AGY_ACP_CCPA_BASE_URL` no Traycer e em `provider-overrides.json`. O `traycer/agy-acp-wrapper` repõe essa variável a partir de `GOOGLE_GEMINI_BASE_URL`.
- **Motivo:** o host do Traycer remove as variáveis `AGY_ACP_*` antes de iniciar o `agy_acp_server`. Sem o wrapper, as chamadas CCPA não chegam ao proxy. Isso vem do comentário do wrapper. Não testei o caminho de ponta a ponta.

## 3. Skills soltas fora do escopo global

- **Data:** 2026-11-12.
- **Decisão:** as skills de `claude/skills-auto.conf` ficam só em `~/.agents/skills`. O `claude/skills-project.sh` liga cada uma por link no projeto que precisa dela. O `install.sh` não recria o link global.
- **Motivo:** o bloco de skills custava cerca de 10,9 mil tokens em todo turno. Essa é uma estimativa de caracteres divididos por 4. O corte vem da spec "Corte de tokens do bloco de skills". Ninguém mediu o ganho real com `/context`.
- **Contexto:** [[context total esconde a economia da lista de skills]].

## 4. Tipo `manual` para skills sem tipo de projeto

- **Data:** 2026-11-12.
- **Decisão:** cinco skills têm o tipo `manual` em `claude/skills-auto.conf`. O `auto` nunca as liga. O comando `claude/skills-project.sh add <skill> [dir]` liga uma por projeto.
- **Motivo:** a spec "Skills avulsas em escopo de projeto" tirou nove skills do escopo global para reduzir tokens por turno. O tipo `manual` deixa a escolha para o usuário. A spec não registra por que essas cinco não têm tipo de projeto.
