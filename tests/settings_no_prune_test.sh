#!/bin/bash
# Garante que nenhum hook registra sb-prune.sh (decisão 21: o arquivo fica, o registro sai).
# Uso: bash tests/settings_no_prune_test.sh   (SETTINGS=<arquivo> aponta a outro settings.json)
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS="${SETTINGS:-$ROOT/claude/settings.json}"
tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT
fail=0
expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }

if ! command -v jq >/dev/null; then echo "FALHA: jq não está no PATH"; exit 1; fi

# check <arquivo>: imprime "registrado", "limpo" ou "erro". Varre todo campo command sob .hooks.
check() {
    local f="$1" out
    [[ -f "$f" ]] || { echo "erro"; return; }
    out="$(jq -r 'if (.hooks | type) != "object" then error("hooks não é objeto")
        else [.hooks | .. | objects | .command? // empty | select(type == "string" and contains("sb-prune"))] | length end' "$f" 2>/dev/null)" || { echo "erro"; return; }
    if [[ "$out" =~ ^[0-9]+$ ]] && (( out > 0 )); then echo "registrado"; elif [[ "$out" == "0" ]]; then echo "limpo"; else echo "erro"; fi
}

fixture() { # fixture <nome> <json>; imprime o caminho
    printf '%s\n' "$2" >"$tmp/$1.json"
    echo "$tmp/$1.json"
}
hook() { # hook <evento> <matcher> <comando>
    printf '{"hooks":{"%s":[{"matcher":"%s","hooks":[{"type":"command","command":%s}]}]}}' "$1" "$2" "$(jq -n --arg c "$3" '$c')"
}

# Controles positivos: toda forma de registrar o hook é pega.
expect "bloco original" "$(check "$(fixture a "$(hook PostToolUse 'Bash|Grep|Glob' 'bash "$HOME/.claude/hooks/sb-prune.sh"')")")" "registrado"
expect "evento Stop" "$(check "$(fixture b "$(hook Stop '' 'bash "$HOME/.claude/hooks/sb-prune.sh"')")")" "registrado"
expect "evento PreToolUse, outro matcher" "$(check "$(fixture c "$(hook PreToolUse 'Read' 'bash "$HOME/.claude/hooks/sb-prune.sh"')")")" "registrado"
expect "evento UserPromptSubmit" "$(check "$(fixture d "$(hook UserPromptSubmit '' 'bash "$HOME/.claude/hooks/sb-prune.sh"')")")" "registrado"
expect "caminho absoluto" "$(check "$(fixture e "$(hook PostToolUse 'Bash' '/home/x/.claude/hooks/sb-prune.sh')")")" "registrado"
expect "bash sb-prune.sh" "$(check "$(fixture f "$(hook PostToolUse 'Bash' 'bash sb-prune.sh')")")" "registrado"
expect "sem aspas" "$(check "$(fixture g "$(hook PostToolUse 'Bash' 'sb-prune.sh')")")" "registrado"
expect "sem extensão" "$(check "$(fixture h "$(hook PostToolUse 'Bash' 'bash ~/.claude/hooks/sb-prune')")")" "registrado"
nested='{"hooks":{"PostToolUse":[{"matcher":"Read","hooks":[{"hooks":[{"type":"command","command":"sb-prune.sh"}]}]}]}}'
expect "hooks aninhado" "$(check "$(fixture i "$nested")")" "registrado"

# Controle negativo e bordas.
expect "description não conta" "$(check "$(fixture j '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"true","description":"sem sb-prune"}]}]}}')")" "limpo"
expect "hooks vazio" "$(check "$(fixture k '{"hooks":{}}')")" "limpo"
expect "arquivo inexistente" "$(check "$tmp/nao-existe.json")" "erro"
expect "JSON inválido" "$(check "$(fixture l '{"hooks": ')")" "erro"
expect ".hooks ausente" "$(check "$(fixture m '{"env":{}}')")" "erro"
expect ".hooks string" "$(check "$(fixture n '{"hooks":"sb-prune"}')")" "erro"
expect ".hooks array" "$(check "$(fixture o '{"hooks":[{"command":"sb-prune"}]}')")" "erro"
mkdir "$tmp/vazio"
expect "jq fora do PATH" "$(PATH="$tmp/vazio" check "$tmp/a.json")" "erro"

# Alvo real.
expect "settings real: sem sb-prune" "$(check "$SETTINGS")" "limpo"
[[ -f "$ROOT/claude/hooks/sb-prune.sh" ]] || { echo "FALHA: claude/hooks/sb-prune.sh sumiu (a decisão 21 manda manter)"; fail=1; }

if (( fail == 0 )); then echo "settings_no_prune_test: ok"; fi
exit "$fail"
