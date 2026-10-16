#!/bin/bash
# Stop: lembra de destilar a sessão para o vault quando houve várias edições
# (Edit/Write e comandos Bash de escrita) e nenhuma menção a `vault_sync.py`,
# `sb.py sync` ou `sb.py candidate add` no transcript.
#
# Só roda com SECOND_BRAIN_HOOKS=1. Lembra no máximo uma vez por sessão e
# respeita stop_hook_active (nunca prende o Claude em loop).
# Env: SECOND_BRAIN_MIN_EDITS (padrão 5). Sempre exit 0.
# Bash de escrita: sed -i, tee, redirecionamento (> / >>), git commit/mv/rm,
# cp, mv, rm, install, chmod, python/python3 -, patch.

[[ "${SECOND_BRAIN_HOOKS:-0}" == "1" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
vault="${SECOND_BRAIN_VAULT:-$HOME/obsidian_vault}"
[[ -d "$vault" ]] || exit 0

stop_active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)"
[[ "$stop_active" == "true" ]] && exit 0

transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
transcript="${transcript/#\~/$HOME}"
[[ -f "$transcript" ]] || exit 0

session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9_-')"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude-hooks/second-brain"
marker="$state_dir/${session_id:-unknown}.reminded"
[[ -n "$session_id" && -f "$marker" ]] && exit 0

# Já houve sync (comando real no transcript)? Então nada a fazer.
# Só conta tool_use de Bash: o transcript também guarda o AGENTS.md injetado, que cita esses comandos.
synced="$(jq -R -r 'fromjson? | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and .name == "Bash")
    | (.input.command // "") | select(test("vault_sync\\.py|sb\\.py (sync|candidate add)"))' "$transcript" 2>/dev/null | head -n1)"
[[ -n "$synced" ]] && exit 0

min_edits="${SECOND_BRAIN_MIN_EDITS:-5}"
[[ "$min_edits" =~ ^[0-9]+$ ]] || min_edits=5

bash_write='(^|[;&|[:space:]])(sed[[:space:]]+-[a-zA-Z]*i|tee|git[[:space:]]+(commit|mv|rm)|cp|mv|rm|install|chmod|patch)([[:space:]]|$)|python3?[[:space:]]+-([[:space:]]|$)|[^<>=-]>>?[[:space:]]*[^&[:space:]]'

edits="$(jq -R -r --arg re "$bash_write" 'fromjson? | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")
    | if .name == "Bash" then (if ((.input.command // "") | test($re)) then "BashWrite" else empty end) else .name end' "$transcript" 2>/dev/null \
    | grep -cE '^(Edit|Write|MultiEdit|NotebookEdit|BashWrite)$')"
[[ "$edits" =~ ^[0-9]+$ ]] || exit 0
(( edits >= min_edits )) || exit 0

if [[ -n "$session_id" ]]; then
    mkdir -p "$state_dir" 2>/dev/null && : > "$marker"
    find "$state_dir" -type f -mtime +7 -delete 2>/dev/null
fi

msg="Esta sessão fez ${edits} edições (arquivos e comandos de escrita) e ainda não enfileirou nada para o second brain. Se a tarefa de dev terminou e gerou padrão, decisão ou armadilha reutilizável, acrescente candidatos à fila com sb.py candidate add (não escreva no vault; o usuário promove na revisão). Se não houve nada reutilizável, apenas encerre sem comentar."
jq -cn --arg msg "$msg" '{decision: "block", reason: $msg}'
exit 0
