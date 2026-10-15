#!/bin/bash
# Testes do hook second-brain-note-opened.sh. Uso: bash tests/second_brain_note_opened_test.sh
set -u
HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/claude/hooks/second-brain-note-opened.sh"
tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT
vault="$tmp/vault"; state="$tmp/state"
mkdir -p "$vault/20_Permanent_Notes" "$vault/00_META/manifests"
fail=0

fire() { # fire <json> [env...]
    local json="$1"; shift
    printf '%s' "$json" | env SECOND_BRAIN_HOOKS=1 SECOND_BRAIN_VAULT="$vault" SECOND_BRAIN_STATE_DIR="$state" "$@" bash "$HOOK"
}
count() { [[ -f "$state/$1.opened" ]] && wc -l <"$state/$1.opened" | tr -d ' ' || echo 0; }
expect() { # expect <nome> <obtido> <esperado>
    if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido $2, esperado $3)"; fail=1; fi
}
read_json() { printf '{"session_id":"%s","tool_name":"Read","tool_input":{"file_path":"%s"}%s}' "$1" "$2" "${3:-}"; }

fire "$(read_json s1 "$vault/20_Permanent_Notes/A B — x.md")"; expect "abre nota (acento, espaço)" "$(count s1)" 1
fire "$(read_json s1 "$vault/20_Permanent_Notes/A B — x.md")"; expect "não repete" "$(count s1)" 1
fire "$(read_json s1 "$vault/20_Permanent_Notes/outra.md")"; expect "segunda nota" "$(count s1)" 2
fire "$(read_json s1 "$vault/00_META/manifests/index.md")"; expect "ignora manifests" "$(count s1)" 2
fire "$(read_json s1 "$vault/20_Permanent_Notes/x.txt")"; expect "ignora não-.md" "$(count s1)" 2
fire "$(read_json s1 "$tmp/outro/nota.md")"; expect "ignora fora do vault" "$(count s1)" 2
fire "$(read_json s1 "$vault/../escape.md")"; expect "ignora .. no caminho" "$(count s1)" 2
fire "$(read_json s1 "${vault}2/nota.md")"; expect "irmão com mesmo prefixo" "$(count s1)" 2
fire "$(read_json s2 "$vault/a.md" ',"agent_id":"sub1"')"; expect "ignora subagente" "$(count s2)" 0
fire "$(read_json "../../evil" "$vault/a.md")"; [[ ! -e "$tmp/evil.opened" ]] || { echo "FALHA: session_id escapou"; fail=1; }
fire "$(read_json s3 "$vault/a.md")" SECOND_BRAIN_HOOKS=0; expect "desligado sem a variável" "$(count s3)" 0
fire 'não é json'; expect "entrada inválida é silenciosa" "$?" 0
expect "permissão do arquivo" "$(stat -c %a "$state/s1.opened")" 600
expect "permissão do diretório" "$(stat -c %a "$state")" 700

[[ $fail -eq 0 ]] && echo "ok" || exit 1
