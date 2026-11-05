---
name: flow
description: 'Inicia, acompanha e aprova um fluxo de agentes pelo motor local de agents/flows (exemplo: /flow ecc-dev "ideia"). Só por comando explícito.'
disable-model-invocation: true
argument-hint: '<fluxo> "<ideia>" | status | approve <nó>'
---

# /flow

Chama o motor local (`engine.cli`), sem servidor. As fases, os modelos e os portões
estão no YAML do fluxo (`$FLOWS_DIR/flows/<fluxo>.yaml`): leia-o só se o usuário perguntar. Roda no repo atual.

Cada comando começa com estas duas linhas (o shell não guarda variáveis). `FLOWS_DIR` já definida vence:

```bash
SKILL_DIR="<diretório base desta skill, que o harness informa>"
FLOWS_DIR="${FLOWS_DIR:-${SKILL_DIR:?defina SKILL_DIR}/../../flows}"
```

`<motor>` é `PYTHONPATH="$FLOWS_DIR" python3 -m engine.cli`:

- `/flow <fluxo> "<ideia>"`: `<motor> run <fluxo> --input "<ideia>"`. O texto vira o slug do run.
- `/flow status`: `<motor> status`. Avança o que dá e mostra o estado de cada fase.
- `/flow approve <nó>`: `<motor> approve <nó>`. Aprova o portão humano da fase.

## Depois do comando

1. Mostre a saída ao usuário sem resumir: ela traz o estado de cada fase.
2. Se a fase `prd` espera arquivo (nó manual), diga que o usuário escreve o PRD na
   própria sessão, com a ideia que passou. O motor só segue quando o arquivo existe.
3. Se há fase em `awaiting_gate`, peça ao usuário para ler as saídas e decidir.
   Nunca rode `approve` por conta própria.
4. Se há fase em `awaiting_quota` ou `awaiting_upgrade`, repasse o motivo e pare.
5. O motor não roda em segundo plano. Para avançar, rode `/flow status` de novo.

## Erros

- Exit 2: o pedido é inválido (fluxo, nó, run, ambiente). Repasse a mensagem de `error:`.
- Exit 1: o CLI do Traycer falhou. Repasse a mensagem e não repita sozinho.
- "missing environment variables": a sessão não roda dentro de um agente do Traycer.
