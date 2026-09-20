# Preferências globais

## Skills de design de interface

Duas skills cobrem este domínio e **nunca devem ser usadas na mesma tarefa**: elas se
contradizem em fonte (`Geist` é correção numa e tell na outra) e em hero centralizado.

**`impeccable` é o padrão** sempre que houver projeto real com UI. Tem detector
determinístico com exit code, `PRODUCT.md` / `DESIGN.md`, hooks por harness, `critique` /
`polish` com backlog persistido, audit de acessibilidade, e cobre também mobile nativo.

**`design-taste-frontend` (Taste) só** para gerar uma página avulsa — landing, portfólio ou
redesign — em React/Next + Tailwind v4, sem contexto de projeto durável. Ao usá-la,
declarar `DESIGN_VARIANCE`, `MOTION_INTENSITY` e `VISUAL_DENSITY` na resposta antes de
escrever código.

Se as duas forem plausíveis, `impeccable` vence e o motivo vai na resposta.

**Não carregar a Taste** para dashboard, data table, formulário multi-etapa, editor de
código, UI de colaboração em tempo real, mobile nativo, Vue/Svelte/Angular, nem para
ajuste pontual de CSS. São ~20k tokens e a própria skill declara esses casos fora de
escopo (§13).

Outras skills do pacote Taste:

- `gpt-taste` só em harness GPT/Codex. Nunca junto de `design-taste-frontend`.
- Uma direção estética por tarefa: `minimalist-ui` **ou** `industrial-brutalist-ui` **ou**
  `high-end-visual-design`. `full-output-enforcement` é ortogonal e pode empilhar com
  qualquer uma.
- Em conflito dentro do pacote, `design-taste-frontend/SKILL.md` vence
  (`stitch-design-taste/DESIGN.md` está desatualizado quanto a serifas).
- `design-taste-frontend-v1` só para projeto que dependa do comportamento antigo.
- `redesign-existing-projects` foi absorvida pelo §11 da v2; preferir a v2.

Contexto e decisões por trás destas regras:
`~/obsidian_vault/30_MOCs/Design de Interface com Agente.md`.
