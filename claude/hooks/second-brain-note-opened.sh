#!/bin/bash
# PostToolUse (matcher Read): registra as notas do vault que o agente abriu na sessão.
#
# Só roda com SECOND_BRAIN_HOOKS=1. Escreve o caminho relativo da nota (sem repetir) em
# ${SECOND_BRAIN_STATE_DIR:-~/.local/state/second-brain}/<session_id>.opened (0600); a linha de
# status conta esse arquivo ("abertas"). Ignora subagentes, arquivos fora do vault, não-.md e os
# manifests (abrir o índice não é abrir uma nota). Sempre exit 0, sem escrever no contexto.

[[ "${SECOND_BRAIN_HOOKS:-0}" == "1" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

vault="${SECOND_BRAIN_VAULT:-$HOME/obsidian_vault}"
vault="${vault%/}"

IFS=$'\t' read -r session file agent < <(
    jq -r '[(.session_id // ""), (.tool_input.file_path // ""), (.agent_id // "")] | @tsv' 2>/dev/null
)
[[ -n "$agent" ]] && exit 0
session="${session//[^A-Za-z0-9_-]/}"
[[ -n "$session" && "$file" == "$vault"/*.md ]] || exit 0

rel="${file#"$vault"/}"
[[ "$rel" == *..* || "$rel" == 00_META/manifests/* ]] && exit 0

state_dir="${SECOND_BRAIN_STATE_DIR:-$HOME/.local/state/second-brain}"
(umask 077; mkdir -p "$state_dir") 2>/dev/null || exit 0
opened="$state_dir/$session.opened"
grep -qxF -- "$rel" "$opened" 2>/dev/null && exit 0
(umask 077; printf '%s\n' "$rel" >>"$opened") 2>/dev/null
exit 0
