#!/bin/bash
# Stop: lembra de destilar a sessão para o vault quando houve várias edições
# e nenhuma menção a vault_sync.py no transcript.
#
# Só roda com SECOND_BRAIN_HOOKS=1. Lembra no máximo uma vez por sessão e
# respeita stop_hook_active (nunca prende o Claude em loop).
# Env: SECOND_BRAIN_MIN_EDITS (padrão 5). Sempre exit 0.

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

# Já houve sync (ou o lembrete já entrou no transcript)? Então nada a fazer.
grep -q 'vault_sync\.py' "$transcript" 2>/dev/null && exit 0

min_edits="${SECOND_BRAIN_MIN_EDITS:-5}"
[[ "$min_edits" =~ ^[0-9]+$ ]] || min_edits=5

edits="$(jq -R -r 'fromjson? | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | .name' "$transcript" 2>/dev/null \
    | grep -cE '^(Edit|Write|MultiEdit|NotebookEdit)$')"
[[ "$edits" =~ ^[0-9]+$ ]] || exit 0
(( edits >= min_edits )) || exit 0

if [[ -n "$session_id" ]]; then
    mkdir -p "$state_dir" 2>/dev/null && : > "$marker"
    find "$state_dir" -type f -mtime +7 -delete 2>/dev/null
fi

msg="Esta sessão fez ${edits} edições e ainda não destilou nada para o second brain. Se a tarefa de dev terminou e gerou padrão, decisão ou armadilha reutilizável, use a skill second-brain-sync (vault_sync.py) para registrar no vault antes de encerrar. Se não houve nada reutilizável, apenas encerre sem comentar."
jq -cn --arg msg "$msg" '{hookSpecificOutput: {hookEventName: "Stop", additionalContext: $msg}}'
exit 0
