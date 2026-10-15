#!/bin/bash
# Testes do hook second-brain-stop.sh. Uso: bash tests/second_brain_stop_test.sh
set -u
HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/claude/hooks/second-brain-stop.sh"
tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT
mkdir -p "$tmp/vault"
fail=0

edit_line='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit"}]}}'

transcript() { # transcript <arquivo> <n edições> [linha extra]
    local file="$1" n="$2" i
    : >"$file"
    for ((i = 0; i < n; i++)); do echo "$edit_line" >>"$file"; done
    [[ -n "${3:-}" ]] && echo "$3" >>"$file"
    return 0
}
fire() { # fire <session> <transcript> [env...]
    local sid="$1" tr="$2"; shift 2
    printf '{"session_id":"%s","transcript_path":"%s"}' "$sid" "$tr" \
        | env SECOND_BRAIN_HOOKS=1 SECOND_BRAIN_VAULT="$tmp/vault" XDG_STATE_HOME="$tmp/state" "$@" bash "$HOOK"
}
expect() { # expect <nome> <obtido> <esperado>
    if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi
}

transcript "$tmp/t1" 5
out="$(fire s1 "$tmp/t1")"
[[ "$out" == *"second brain"* ]] && got=lembra || got=silencio
expect "5 edições sem sync lembram" "$got" lembra
[[ "$out" == *"sb.py sync"* ]] && got=cita || got=nao
expect "o lembrete cita sb.py sync" "$got" cita

out="$(fire s1 "$tmp/t1")"; expect "lembra só uma vez por sessão" "$out" ""

transcript "$tmp/t2" 5 '{"type":"user","message":"rodei python3 sb.py sync --note x"}'
expect "sb.py sync no transcript silencia" "$(fire s2 "$tmp/t2")" ""

transcript "$tmp/t3" 5 '{"type":"user","message":"rodei vault_sync.py --note x"}'
expect "vault_sync.py no transcript silencia" "$(fire s3 "$tmp/t3")" ""

transcript "$tmp/t4" 4
expect "menos de 5 edições silencia" "$(fire s4 "$tmp/t4")" ""

transcript "$tmp/t5" 5
expect "desligado sem a variável" "$(fire s5 "$tmp/t5" SECOND_BRAIN_HOOKS=0)" ""

[[ $fail -eq 0 ]] && echo "ok" || exit 1
