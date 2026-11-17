# ECC por projeto

O plugin `ecc@ecc` custa ~45 mil tokens por sessão e fica desligado no escopo de usuário.
Política permanente do usuário (2026-10-15): o wrapper `claude` do zsh liga o ECC
**automaticamente** em projetos web, C e backend Node (`zsh/ecc-auto.zsh` chama
`claude/ecc-project.sh auto` antes de abrir a sessão). A linha `ECC ligado|desligado (...)` no
início da sessão informa o estado.

- **Quem liga:** só o usuário ou o wrapper rodam `make ecc-on|ecc-off|ecc-auto` e
  `ecc-project.sh`. Peça ao usuário.
- **Desligado num projeto web, C ou Node** (sessão aberta fora do wrapper, ou
  `.claude/ecc.off`): informe e sugira `make ecc-on DIR=...` quando a tarefa justificar ~45k
  tokens. Respeite o `ecc.off`.
- **Fora desses tipos:** sugira ligar só para revisão Go, Java ou Kotlin, `orch-review` ou
  `review-pr`. Sugira desligar no resto.
- **Desligado:** use os `cavecrew-*`, o `Explore` ou a sessão principal.
- **Ligado:** delegue no máximo 3 agentes por rodada, mesmo que um agente `ecc:*` diga
  "PROACTIVELY".
- **Mudança de estado:** vale só numa sessão nova (`/reload-plugins` não dispara o
  SessionStart).
