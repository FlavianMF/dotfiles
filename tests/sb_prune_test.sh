#!/bin/bash
# Testes do hook sb-prune.sh. Uso: bash tests/sb_prune_test.sh
set -u
HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/claude/hooks/sb-prune.sh"
tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT
vault="$tmp/vault"
sbdir="$vault/00_META/skills/second-brain-sync/scripts"
mkdir -p "$sbdir"
fail=0
expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }

stub() { # stub <corpo python>
    printf '%s\n' "import sys" "$1" >"$sbdir/sb.py"
}
fire() { # fire [env...]; imprime stdout, depois rc=N
    local out rc
    out="$(echo '{"tool_name":"Bash"}' | env SECOND_BRAIN_VAULT="$vault" "$@" bash "$HOOK" 2>"$tmp/err")"
    rc=$?
    echo "${out}|rc=${rc}"
}

FIXED='{"hookSpecificOutput":{"hookEventName":"PostToolUse","updatedToolOutput":{"stdout":"X"}}}'
stub "
if sys.argv[1:3] == ['prune', 'hook']:
    sys.stdin.read()
    print('$FIXED')
"
expect "repassa saída do stub" "$(fire SECOND_BRAIN_HOOKS=1)" "$FIXED|rc=0"
expect "sem SECOND_BRAIN_HOOKS=1: nada" "$(fire SECOND_BRAIN_HOOKS=0)" "|rc=0"
expect "SB_PRUNE=0: nada" "$(fire SECOND_BRAIN_HOOKS=1 SB_PRUNE=0)" "|rc=0"
expect "SB_PRUNE=off: nada" "$(fire SECOND_BRAIN_HOOKS=1 SB_PRUNE=off)" "|rc=0"

# stdin chega ao stub
stub "
print(sys.stdin.read().strip())
"
expect "repassa stdin" "$(fire SECOND_BRAIN_HOOKS=1)" '{"tool_name":"Bash"}|rc=0'

rm "$sbdir/sb.py"
expect "sb.py ausente: nada, exit 0" "$(fire SECOND_BRAIN_HOOKS=1)" "|rc=0"

stub "
sys.stderr.write('boom\n')
sys.exit(1)
"
expect "stub falha: stdout vazio, exit 0" "$(fire SECOND_BRAIN_HOOKS=1)" "|rc=0"

stub "
import time
time.sleep(5)
print('tarde')
"
start=$SECONDS
res="$(fire SECOND_BRAIN_HOOKS=1)"
expect "stub lento: cortado, exit 0" "$res" "|rc=0"
if (( SECONDS - start > 4 )); then echo "FALHA: timeout não cortou ($((SECONDS - start))s)"; fail=1; fi

if (( fail == 0 )); then echo "sb_prune_test: ok"; fi
exit "$fail"
