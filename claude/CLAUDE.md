@~/dotfiles/agents/AGENTS.md

# Exclusivo do Claude Code

- Subagentes rodam em `sonnet` por padrão (`CLAUDE_CODE_SUBAGENT_MODEL`); passe `model`
  explícito só quando a tarefa exigir julgamento de `opus`.
- Skills de plugin aparecem com prefixo (`impeccable:impeccable`,
  `mattpocock-skills:tdd`, `caveman:caveman`); as regras acima valem pelo nome base.
- O hook `suggest-compact` avisa quando a sessão passa de ~50 tool calls: trate como
  sinal para compactar na próxima fronteira de fase, não no meio da edição.
- Hooks do second brain (`SECOND_BRAIN_HOOKS=1`): o SessionStart injeta notas do vault
  relacionadas ao repo; o Stop lembra de rodar `vault_sync.py` depois de várias edições.
  Desligue por projeto com `"env": {"SECOND_BRAIN_HOOKS": "0"}` em
  `.claude/settings.local.json`.
- Format/typecheck no Stop é opt-in por projeto: `"env": {"CLAUDE_FORMAT_TYPECHECK": "1"}`
  (e opcionalmente `CLAUDE_FORMAT_TYPECHECK_CMD`) em `.claude/settings.local.json`.
