#!/bin/bash
# Pacote de contexto da sessão (RFC-002 D1). Uso: sb-ctxpack.sh <read|finding|render>
#   read    PostToolUse(Read): grava caminho e sha256 (nunca conteúdo).
#   finding SubagentStop: grava a conclusão do subagente (descartada se o scan achar segredo).
#   render  SubagentStart: imprime o additionalContext JSON com o pacote (ou nada).
#
# Só roda com SECOND_BRAIN_HOOKS=1. Modo via SB_CTXPACK: shadow (padrão desde a E3 da RFC-002), active, 0. Sempre exit 0.

[[ "${SECOND_BRAIN_HOOKS:-0}" == "1" ]] || exit 0
case "${SB_CTXPACK:-}" in 0|false|off|no) exit 0 ;; esac

case "${1:-}" in
    read) action=record-read ;;
    finding) action=record-finding ;;
    render) action=render ;;
    *) exit 0 ;;
esac

vault="${SECOND_BRAIN_VAULT:-$HOME/obsidian_vault}"
sb="$vault/00_META/skills/second-brain-sync/scripts/sb.py"
[[ -f "$sb" ]] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

timeout 3 python3 "$sb" ctx "$action" 2>/dev/null
exit 0
