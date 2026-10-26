#!/bin/bash
# Poda de saída de ferramenta (RFC-002). PostToolUse(Bash|Grep|Glob): repassa o JSON do
# hook (stdin) a `sb.py prune hook`, que imprime nada (sem poda) ou um JSON
# hookSpecificOutput.updatedToolOutput com a saída reduzida. A saída integral vai para
# spill em ~/.local/state/second-brain/spill/.
#
# Só roda com SECOND_BRAIN_HOOKS=1. Desliga com SB_PRUNE=0. Sempre exit 0.

[[ "${SECOND_BRAIN_HOOKS:-0}" == "1" ]] || exit 0
case "${SB_PRUNE:-}" in 0|false|off|no) exit 0 ;; esac

vault="${SECOND_BRAIN_VAULT:-$HOME/obsidian_vault}"
sb="$vault/00_META/skills/second-brain-sync/scripts/sb.py"
[[ -f "$sb" ]] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

timeout 3 python3 "$sb" prune hook 2>/dev/null
exit 0
