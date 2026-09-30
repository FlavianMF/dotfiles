#!/bin/bash
# PostToolUse: conta tool calls por sessão e sugere compactar ao passar do limite.
#
# Contador por session_id (lido do stdin) em ${XDG_STATE_HOME:-~/.local/state}/claude-hooks/compact/.
# Env:
#   COMPACT_SUGGEST_THRESHOLD  primeira sugestão (padrão 50)
#   COMPACT_SUGGEST_INTERVAL   repete a cada N calls depois disso (padrão 25)
# Sempre exit 0; nunca bloqueia.

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9_-')"
[[ -z "$session_id" ]] && exit 0

# Subagentes têm contexto próprio; só conta a sessão principal.
agent_id="$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)"
[[ -n "$agent_id" ]] && exit 0

threshold="${COMPACT_SUGGEST_THRESHOLD:-50}"
interval="${COMPACT_SUGGEST_INTERVAL:-25}"
[[ "$threshold" =~ ^[0-9]+$ ]] || threshold=50
[[ "$interval" =~ ^[0-9]+$ && "$interval" -gt 0 ]] || interval=25

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude-hooks/compact"
mkdir -p "$state_dir" 2>/dev/null || exit 0
counter_file="$state_dir/$session_id"

count=0
[[ -f "$counter_file" ]] && count="$(cat "$counter_file" 2>/dev/null)"
[[ "$count" =~ ^[0-9]+$ ]] || count=0
count=$((count + 1))
printf '%s' "$count" > "$counter_file" 2>/dev/null

# Limpeza oportunista de contadores com mais de 7 dias.
if (( count == 1 )); then
    find "$state_dir" -type f -mtime +7 -delete 2>/dev/null
fi

if (( count >= threshold )) && (( (count - threshold) % interval == 0 )); then
    msg="Sessão com ${count} tool calls. Na próxima fronteira de fase (etapa concluída, antes de começar outra), sugira ao usuário rodar /compact — ou registre o estado e siga em sessão nova. Não compacte no meio de uma edição em vários arquivos."
    jq -cn --arg msg "$msg" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}'
fi

exit 0
