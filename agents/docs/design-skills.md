# Skills de design de interface

Use uma skill de design por tarefa. `impeccable` e `design-taste-frontend` se contradizem em
fonte (`Geist` é correção numa e tell na outra) e em hero centralizado.

**`impeccable` é o padrão** sempre que houver projeto real com UI. Tem detector
determinístico com exit code, `PRODUCT.md` / `DESIGN.md`, hooks por harness, `critique` /
`polish` com backlog persistido, audit de acessibilidade, e cobre também mobile nativo.

**`design-taste-frontend` (Taste) só** para gerar uma página avulsa — landing, portfólio ou
redesign — em React/Next + Tailwind v4, sem contexto de projeto durável. Ao usá-la,
declare `DESIGN_VARIANCE`, `MOTION_INTENSITY` e `VISUAL_DENSITY` na resposta antes de
escrever código.

Para dashboard, data table, formulário multi-etapa, editor de código, UI de colaboração em
tempo real, mobile nativo, Vue/Svelte/Angular ou ajuste pontual de CSS, use `impeccable`. A
Taste custa ~20k tokens e a própria skill declara esses casos fora de escopo (§13).

Se as duas forem plausíveis, `impeccable` vence e o motivo vai na resposta.

Outras skills do pacote Taste:

- `gpt-taste` só em harness GPT/Codex.
- Uma direção estética por tarefa: `minimalist-ui` **ou** `industrial-brutalist-ui` **ou**
  `high-end-visual-design`. `full-output-enforcement` é ortogonal e pode empilhar com
  qualquer uma.
- Em conflito dentro do pacote, `design-taste-frontend/SKILL.md` vence
  (`stitch-design-taste/DESIGN.md` está desatualizado quanto a serifas).
- `design-taste-frontend-v1` só para projeto que dependa do comportamento antigo.
- `redesign-existing-projects` foi absorvida pelo §11 da v2; prefira a v2.

Contexto e decisões por trás destas regras:
`~/obsidian_vault/30_MOCs/Design de Interface com Agente.md`.
