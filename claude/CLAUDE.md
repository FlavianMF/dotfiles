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
- **Herdr no WSL (`HERDR_ENV` vazio):** o Herdr do usuário é o app de desktop do Windows, e o
  servidor `herdr` do WSL fica parado. Não pare em "não estou no Herdr". Quando o usuário pedir
  uma sessão ou um pane novo, use `herdr-app` (wrapper de `herdr-app.exe`), nunca o CLI `herdr`:
  `herdr-app do space.new --name <nome> --machine wsl --folder <pasta> --argv '["claude"]'
  --task "<primeira mensagem>"`. Rode `herdr-app ls` antes e `hc read <terminal>` depois, sem o
  prefixo `wsl/`. Não rode `herdr-app` sem argumento e não pare o app nem o core. Passe o
  contexto por um handoff em `~/.config/cockpit/handoff-<runbook>.md`. Detalhes em
  `~/.claude/projects/-home-flv-outlet-promo/memory/reference-herdr-app-abrir-sessao-claude.md`.
