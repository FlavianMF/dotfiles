#!/bin/bash
# PostToolUse (todas as ferramentas): log de metadados de tool calls para o observer do second brain.
# Stop (arg `stop`): resume o log da sessão e enfileira candidatos (`sb observe summarize`).
#
# Só roda com SECOND_BRAIN_HOOKS=1. Determinístico: sem modelo, sem processo em background, funciona
# com o ECC ligado ou desligado. Grava só tool, caminho e tamanho (nunca conteúdo nem comando);
# nunca escreve no vault nem no contexto. Desligue com SB_OBSERVE=0. Sempre exit 0.

[[ "${SECOND_BRAIN_HOOKS:-0}" == "1" ]] || exit 0
case "${SB_OBSERVE:-}" in 0|false|off|no) exit 0 ;; esac

vault="${SECOND_BRAIN_VAULT:-$HOME/obsidian_vault}"
sb="$vault/00_META/skills/second-brain-sync/scripts/sb.py"
[[ -f "$sb" ]] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

if [[ "${1:-}" == "stop" ]]; then
    command -v jq >/dev/null 2>&1 || exit 0
    IFS=$'\t' read -r session transcript < <(
        jq -r '[(.session_id // ""), (.transcript_path // "")] | @tsv' 2>/dev/null
    )
    session="${session//[^A-Za-z0-9_-]/}"
    [[ -n "$session" ]] || exit 0
    args=(observe summarize --session "$session")
    [[ -n "$transcript" ]] && args+=(--transcript "$transcript")
    timeout 5 python3 "$sb" "${args[@]}" >/dev/null 2>&1
    exit 0
fi

timeout 2 python3 "$sb" observe record >/dev/null 2>&1
exit 0
