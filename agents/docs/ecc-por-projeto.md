# ECC por projeto

O plugin `ecc@ecc` custa ~45 mil tokens por sessão; fica desligado no escopo de usuário. Política permanente do
usuário (2026-10-15): o ECC é ligado **automaticamente** em projetos web, C e backend Node pelo wrapper `claude` do zsh
(`zsh/ecc-auto.zsh` chama `claude/ecc-project.sh auto` antes de abrir a sessão). A linha `ECC ligado|desligado (...)` no
início da sessão informa o estado.

- O agente nunca roda `make ecc-on|ecc-off|ecc-auto` nem `ecc-project.sh` por conta própria; quem liga é o wrapper ou o usuário.
- ECC desligado num projeto web/C/Node (sessão aberta fora do wrapper, ou `.claude/ecc.off`): informe e sugira
  `make ecc-on DIR=...` só se a tarefa se beneficiar; respeite o `ecc.off`. Fora desses tipos, sugira ligar apenas para revisão
  Go/Java/Kotlin, `orch-review` ou `review-pr`, e desligar no resto.
- Com o ECC desligado, não invoque agentes `ecc:*` nem skills do plugin; use os `cavecrew-*`, o `Explore` ou a sessão principal.
- Com o ECC ligado, o teto de 3 agentes por rodada e o contrato de delegação valem acima de qualquer "PROACTIVELY" de agente `ecc:*`.
- Mudança de estado só vale numa sessão nova (`/reload-plugins` não dispara o SessionStart).
