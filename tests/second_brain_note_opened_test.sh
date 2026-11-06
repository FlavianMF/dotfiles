#!/bin/bash
# Testes do hook second-brain-note-opened.sh. Uso: bash tests/second_brain_note_opened_test.sh
set -u
HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/claude/hooks/second-brain-note-opened.sh"
tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -r "$tmp"' EXIT
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

# --- uso via Bash e Grep (.used); .opened continua só com Read ---
used() { [[ -f "$state/$1.used" ]] && wc -l <"$state/$1.used" | tr -d ' ' || echo 0; }
bash_json() { jq -cn --arg s "$1" --arg c "$2" '{session_id:$s,tool_name:"Bash",tool_input:{command:$c}}'; }
home_rel=""; [[ "$vault" == "$HOME"/* ]] && home_rel="${vault#"$HOME"/}"

fire "$(bash_json b1 "cat \"$vault/20_Permanent_Notes/A B — x.md\"")"; expect "cat de nota com espaço" "$(used b1)" 1
fire "$(bash_json b1 "cat \"$vault/20_Permanent_Notes/A B — x.md\"")"; expect "cat repetido não duplica" "$(used b1)" 1
expect "Bash não grava .opened" "$(count b1)" 0
fire "$(bash_json b2 "head -20 $vault/20_Permanent_Notes/a.md | wc -l")"; expect "head com pipe" "$(used b2)" 1
fire "$(bash_json b3 "cat $vault/00_META/manifests/index.md")"; expect "ignora manifest no Bash" "$(used b3)" 0
fire "$(bash_json b3 "rm $vault/20_Permanent_Notes/a.md")"; expect "ignora comando sem verbo de leitura" "$(used b3)" 0
fire "$(bash_json b3 "cat $tmp/outro/nota.md")"; expect "ignora nota fora do vault" "$(used b3)" 0
fire "$(bash_json b3 "cat ${vault}2/nota.md")"; expect "irmão com mesmo prefixo no Bash" "$(used b3)" 0
fire "$(bash_json b4 "python3 scripts/sb.py search -k 3 hook")"; expect "sb.py search" "$(used b4)" 1
fire "$(bash_json b4 "sb search outro")"; expect "sb search repete a mesma linha" "$(used b4)" 1
fire "$(bash_json b5 "rg -l pattern $vault/20_Permanent_Notes")"; expect "rg sobre o vault" "$(used b5)" 1
fire "$(bash_json b6 "rg -l pattern /etc")"; expect "rg fora do vault" "$(used b6)" 0
fire "$(bash_json b7 "ls $vault")"; expect "ls não é busca" "$(used b7)" 0
if [[ -n "$home_rel" ]]; then
    fire "$(bash_json b8 'cat ~/'"$home_rel"'/20_Permanent_Notes/a.md')"; expect "cat com ~/" "$(used b8)" 1
    fire "$(bash_json b9 'cat $HOME/'"$home_rel"'/20_Permanent_Notes/a.md')"; expect "cat com \$HOME/" "$(used b9)" 1
fi
fire "$(jq -cn --arg s g1 --arg p "$vault/20_Permanent_Notes" '{session_id:$s,tool_name:"Grep",tool_input:{pattern:"x",path:$p}}')"; expect "Grep no vault" "$(used g1)" 1
fire "$(jq -cn --arg s g2 --arg p "$tmp/outro" '{session_id:$s,tool_name:"Grep",tool_input:{pattern:"x",path:$p}}')"; expect "Grep fora do vault" "$(used g2)" 0
fire "$(bash_json b10 "cat $vault/a.md" | jq -c '. + {agent_id:"sub1"}')"; expect "Bash de subagente" "$(used b10)" 0
fire "$(read_json u1 "$vault/20_Permanent_Notes/n.md")"; expect "Read grava .used" "$(used u1)" 1; expect "Read mantém .opened" "$(count u1)" 1
expect "permissão do .used" "$(stat -c %a "$state/b1.used")" 600

[[ $fail -eq 0 ]] && echo "ok" || exit 1
