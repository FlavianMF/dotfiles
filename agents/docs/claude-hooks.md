# Hooks do Claude Code

Leia antes de mudar, silenciar ou depurar um hook.

## Second brain (`SECOND_BRAIN_HOOKS=1`)

- O SessionStart injeta notas do vault relacionadas ao repo.
- O Stop lembra de enfileirar candidatos (`sb candidate add`) depois de várias edições
  (arquivos e Bash de escrita).
- O comando `/review-web` (ou `/sb-review`) inicia a interface web FastAPI (`sb review web`)
  para triar candidatos no navegador.
- Desligue por projeto: `"env": {"SECOND_BRAIN_HOOKS": "0"}` em `.claude/settings.local.json`.

## `jev-e` (UserPromptSubmit, modo sombra)

Grava num log local qual skill o Jev sugeriria e não escreve nada no contexto.
Desligue por projeto: `"env": {"JEV_TOOL_E": "0"}` em `.claude/settings.local.json`.

## Format/typecheck no Stop

Fica desligado por padrão. Ligue por projeto: `"env": {"CLAUDE_FORMAT_TYPECHECK": "1"}`
(e, se quiser, `CLAUDE_FORMAT_TYPECHECK_CMD`) em `.claude/settings.local.json`.
