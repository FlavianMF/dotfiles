#!/bin/bash
# agy PostToolUse (todas as ferramentas): log de metadados de tool calls para o observer do second brain.
#
# Converte o payload do agy (`conversationId`, `toolCall:{name,args}`) para o contrato de
# `sb.py observe record` (`session_id`, `tool_name`, `tool_input`). Repassa só o caminho do arquivo,
# nunca comando nem conteúdo. Responde `{}`.
# Liga por padrão (o agy não tem `env` em settings); SECOND_BRAIN_HOOKS=0 ou SB_OBSERVE=0 desliga.
# Sempre exit 0.

done_() { echo '{}'; exit 0; }

[[ "${SECOND_BRAIN_HOOKS:-1}" == "0" ]] && done_
case "${SB_OBSERVE:-}" in 0|false|off|no) done_ ;; esac

vault="${SECOND_BRAIN_VAULT:-$HOME/obsidian_vault}"
sb="$vault/00_META/skills/second-brain-sync/scripts/sb.py"
[[ -f "$sb" ]] || done_
command -v python3 >/dev/null 2>&1 || done_
command -v jq >/dev/null 2>&1 || done_

payload="$(jq -c '{
    session_id: (.conversationId // ""),
    tool_name: (.toolCall.name // ""),
    tool_input: {file_path: (.toolCall.args.Path // .toolCall.args.path // .toolCall.args.AbsolutePath // .toolCall.args.TargetFile // "")}
}' 2>/dev/null)"
[[ -n "$payload" ]] || done_

printf '%s' "$payload" | timeout 2 python3 "$sb" observe record >/dev/null 2>&1
done_
