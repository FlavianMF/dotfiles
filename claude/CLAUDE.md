@~/dotfiles/agents/AGENTS.md

# Exclusivo do Claude Code

- **Subagentes** rodam em `sonnet` por padrão (`CLAUDE_CODE_SUBAGENT_MODEL`). Passe `model`
  explícito só quando a tarefa exigir julgamento de `opus`.
- **Skills de plugin** aparecem com prefixo (`impeccable:impeccable`,
  `mattpocock-skills:tdd`, `caveman:caveman`). As regras valem pelo nome base.
- **`suggest-compact`:** quando o hook avisar, aplique a regra de fronteira de fase.
- **`git-ops`:** commit, merge, push, status e rebase mecânicos vão para o agente `git-ops`
  (haiku). Se a sessão já tem o contexto, faça um commit simples direto.
- **Hooks:** antes de mudar, silenciar ou depurar um hook (second brain, `jev-e`,
  format/typecheck), leia `~/dotfiles/agents/docs/claude-hooks.md`.
- **ECC** (plugin `ecc@ecc`): antes de invocar um agente ou skill `ecc:*`, ou quando o usuário
  citar ECC, leia `~/dotfiles/agents/docs/ecc-por-projeto.md`. Só o usuário ou o wrapper
  `claude` do zsh liga e desliga o ECC, então peça ao usuário.
