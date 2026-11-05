---
name: phase
description: 'Roda uma única fase de um fluxo de agentes, isolada, sem criar run (exemplo: /phase plan "caminho do PRD"). Só por comando explícito.'
disable-model-invocation: true
argument-hint: '<nó> "<entrada>" [--flow <fluxo>] [--wait]'
---

# /phase

Roda uma fase do fluxo fora de qualquer run, pelo adaptador do Traycer (`engine.cli phase`).
Sem estado nem portão: a fase cria um filho, envia o prompt e devolve o id.
O prompt, o modelo e as saídas vêm do YAML do fluxo (padrão `ecc-dev`).

O comando começa com estas duas linhas (o shell não guarda variáveis). `FLOWS_DIR` já definida vence:

```bash
SKILL_DIR="<diretório base desta skill, que o harness informa>"
FLOWS_DIR="${FLOWS_DIR:-${SKILL_DIR:?defina SKILL_DIR}/../../flows}"
```

Depois rode:

`PYTHONPATH="$FLOWS_DIR" python3 -m engine.cli phase <nó> --input "<entrada>"`

- `<entrada>` substitui `{{input}}` do prompt. Sem ela, vale a lista de entradas do nó.
- `--slug <slug>` define o `${slug}` dos caminhos. Sem ele, vale o do run ativo do repo,
  ou o derivado da entrada.
- `--wait` espera o fim do turno (até 30 min) e lista quais saídas existem.
- `--flow <fluxo>` escolhe outro fluxo.

## Depois do comando

1. Mostre a saída: o id do filho e os arquivos de saída esperados.
2. Diga que o filho segue no Traycer: o usuário abre o agente. Não leia nem aprove as saídas.

## Erros

- Exit 2: nó manual (rode o prompt na sua sessão), nó inexistente, slug ausente ou ambiente
  sem Traycer. Repasse a mensagem de `error:`.
- Exit 1: cota acima de 80% ou falha do CLI. Repasse a mensagem e não repita sozinho.
