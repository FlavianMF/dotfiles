# Fluxos de agentes

Fluxos de agentes como botões. O motor lê `flows/ecc-dev.yaml`, cria um agente filho por fase pelo CLI `traycer` e para nos portões humanos.

## Como iniciar

Pré-requisito: crie o agente base fixo (seção abaixo) e exporte as duas variáveis.

```sh
export TRAYCER_EPIC_ID=<id do Task>
export TRAYCER_AGENT_ID=<id do agente base>
make flow-validate                       # valida flows/ecc-dev.yaml
make flow-serve REPO=~/meu-repo          # servidor em http://127.0.0.1:8765/
make flow-run INPUT="ideia do trabalho"  # run pelo motor, sem servidor
make flow-test                           # testes
```

Variáveis: `PYTHON` (padrão `python3`), `FLOW`, `PORT`, `REPO` (padrão: diretório do Makefile raiz), `NAME` (padrão `ecc-dev`).
O servidor escuta só em `127.0.0.1`.

## As 3 paradas humanas

| Parada | Quando |
| --- | --- |
| `prd` | Fase manual. Você roda `prompts/prp-prd.md` na sua sessão. O motor espera o arquivo e a sua aprovação. |
| `plan` | Você lê o plano antes da implementação. |
| `pr` | Você aprova antes de abrir o PR. |

O nó `review` também tem `gate: human`, mas só roda se `diff_lines > 150` ou o run é sensível. Quando roda, você lê os achados antes do commit. Pulado, não para.

## Como aprovar

- Pela página do servidor: use o botão do nó.
- Pelo CLI: `python -m engine.cli approve <nó> [--run ID]`, dentro de `agents/flows/`.
- Para ver o estado e avançar o run: `python -m engine.cli status`.

## Onde fica o estado do run

Um arquivo `<run_id>.json` por run, em `$FLOWS_STATE_DIR` (padrão `~/.local/state/flows`). O servidor usa o mesmo padrão, mudável com `--state-dir`. O arquivo guarda só texto e números, sem segredo. As saídas das fases ficam no repo do trabalho, em `.claude/PRPs/`.

## Agente base fixo do Task

O CLI `traycer` recusa rodar sem `TRAYCER_EPIC_ID` e `TRAYCER_AGENT_ID`. O `TRAYCER_AGENT_ID` precisa ser de um agente real do Task: ele vira o pai dos filhos de cada fase.

Existe um único agente base por Task. Para criar:

1. No Task, crie um agente novo (UI do Traycer ou `traycer_create_agent`) e deixe-o idle, sem mensagem.
2. Copie o id dele (`traycer_get_self` rodado nele, ou a lista de agentes).
3. Exporte `TRAYCER_EPIC_ID` (id do Task) e `TRAYCER_AGENT_ID` (id desse agente).

Não arquive nem mande mensagem ao agente base. Se criar outro Task, crie outro agente base.

## Perfil e modelos (decisão de 2026-11-05)

- Todo nó usa o perfil `6b0bf0d5-a512-4d98-9f8c-5387a980777a` (conta `claude`), no lugar de `ambient`.
- O nó `review` saiu de `antigravity`/`claude-opus-5.5` para `claude`/`opus`/`high`. A revisão a frio continua num filho novo, sem fork.
- Modelo, esforço e perfil continuam editáveis em `flows/ecc-dev.yaml`, sem mexer no motor.

## Limite de cota

Antes de criar cada filho, o motor lê os limites do perfil (janelas de 5h e 7 dias). Se a maior passar de 80%, o nó vira `awaiting_quota` e o motor não cria o filho. Retome quando a cota baixar, ou aborte. Se o motor não consegue ler a cota, o nó também espera.

## Como medir um run

O transcript pode não trazer uso de tokens. Meça pela cota do perfil, antes e depois:

1. Antes do run, anote a cota: `python -m engine.cli status --no-advance --json` e o limite do perfil no Traycer.
2. Rode o fluxo até o fim.
3. Leia a cota de novo e subtraia. A diferença em `usedPercent` é o custo do run.
4. Para o custo por fase, rode `make flow-report RUN=<run_id>`. O motor grava `quota_before` (antes de criar o filho) e `quota_after` (ao fim do turno) em cada nó, e o relatório mostra os dois na coluna de cota. Cada leitura traz `updated_at`: se for igual nas duas, o CLI devolveu cache e a diferença não vale.

A cota vem de cache curto: espere alguns minutos entre leituras.
