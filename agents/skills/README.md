# Skills versionadas aqui

`install.sh` liga cada pasta ao harness que a lê:

| Skill | Claude Code (`~/.claude/skills`) | Codex e OpenCode (`~/.agents/skills`) |
| --- | --- | --- |
| `figjam-pm-canvas`, `reverse-engineer-anything` | sim | sim |
| `flow`, `phase` | sim | **não** |

## Por que `flow` e `phase` só no Claude Code

As duas têm `disable-model-invocation: true`: só rodam por comando explícito (`/flow`, `/phase`).
O Claude Code respeita essa chave. Codex e OpenCode leem `~/.agents/skills` e **podem ignorá-la**
(não verificado). Sem a chave, o modelo poderia disparar `phase` e criar um filho no Traycer sozinho.

Por isso `install.sh` liga as duas só em `~/.claude/skills` (`link_claude_skill`) e remove o link
antigo em `~/.agents/skills` (`remove_stale_shared_link`). O custo: `/flow` e `/phase` não existem
no Codex nem no OpenCode.

Para reverter depois de verificar que o harness respeita a chave, troque `link_claude_skill`
por `link_shared_skill` no `install.sh` e ajuste o teste `test_install_links_the_skill_for_claude_code_only`.

## Onde a skill acha o motor

`flow` e `phase` resolvem `agents/flows` a partir do próprio local (seguindo o link com `readlink -f`).
A variável `FLOWS_DIR` sobrepõe o caminho.
