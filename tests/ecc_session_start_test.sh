#!/bin/bash
# Testes do hook ecc-session-start.sh (linha de estado, sugestão e snapshot). Uso: bash tests/ecc_session_start_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/claude/hooks/ecc-session-start.sh"
ECC="$ROOT/claude/ecc-project.sh"
tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -r "$tmp"' EXIT
fail=0

export CLAUDE_CONFIG_DIR="$tmp/userconf"; mkdir -p "$CLAUDE_CONFIG_DIR"
echo '{"enabledPlugins":{"ecc@ecc":false}}' >"$CLAUDE_CONFIG_DIR/settings.json"
export ECC_AUTO_CONF="$tmp/auto.conf"; echo 'kinds=web,c,node' >"$ECC_AUTO_CONF"
export GIT_CONFIG_GLOBAL=/dev/null
export CLAUDE_SESSION_STATE_DIR="$tmp/sess"

expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
repo() { git init -q "$tmp/$1"; echo "$tmp/$1"; }
hook() { printf '{"cwd":"%s","session_id":"%s","source":"%s"}' "$1" "${2:-s}" "${3:-startup}" | SECOND_BRAIN_HOOKS="${SB:-1}" bash "$HOOK"; }

d="$(repo web)"; echo '{"dependencies":{"react":"18"}}' >"$d/package.json"
out="$(hook "$d")"
expect "web desligado: linha de estado" "$(grep -c '^ECC desligado' <<<"$out")" 1
expect "web desligado: sugestão" "$(grep -c 'O projeto parece web e o ECC está desligado' <<<"$out")" 1
expect "sugestão traz o comando" "$(grep -c 'make ecc-on DIR=' <<<"$out")" 1

"$ECC" on "$d" --no-rules >/dev/null
out="$(hook "$d")"
expect "web ligado: sem sugestão" "$(grep -c 'parece' <<<"$out")" 0
expect "web ligado: linha de estado" "$(grep -c '^ECC ligado' <<<"$out")" 1

"$ECC" off "$d" >/dev/null
expect "ecc.off: sem sugestão" "$(hook "$d" | grep -c 'parece')" 0

d="$(repo cproj)"; : >"$d/Makefile"; : >"$d/main.c"
expect "C: sugestão" "$(hook "$d" | grep -c 'parece c e')" 1
d="$(repo nodeb)"; echo '{"dependencies":{"express":"4"}}' >"$d/package.json"
expect "Node: sugestão" "$(hook "$d" | grep -c 'parece backend Node')" 1
d="$(repo plain)"; echo x >"$d/README.md"
expect "projeto comum: sem sugestão" "$(hook "$d" | grep -c 'parece')" 0
mkdir -p "$d/sub"; expect "subpasta usa a raiz" "$(hook "$d/sub" | grep -c 'parece')" 0
d="$(repo websub)"; echo '{"dependencies":{"vue":"3"}}' >"$d/package.json"; mkdir "$d/sub"
expect "subpasta de web sugere" "$(hook "$d/sub" | grep -c 'parece web')" 1
expect "dotfiles: sem sugestão" "$(hook "$ROOT" | grep -c 'parece')" 0

# Snapshot da sessão: estado, escopo, second brain, raiz; 0600.
d="$(repo snap)"; echo '{"dependencies":{"react":"18"}}' >"$d/package.json"; mkdir "$d/sub"
hook "$d/sub" sid1 startup >/dev/null
expect "snapshot: conteúdo" "$(paste -sd'|' "$tmp/sess/sid1.ecc")" "desligado|usuário|on|$d"
expect "snapshot: permissão do arquivo" "$(stat -c %a "$tmp/sess/sid1.ecc")" 600
expect "snapshot: permissão do diretório" "$(stat -c %a "$tmp/sess")" 700
"$ECC" on "$d" --no-rules >/dev/null
hook "$d" sid1 compact >/dev/null
expect "compact não regrava o snapshot" "$(head -n 1 "$tmp/sess/sid1.ecc")" desligado
hook "$d" sid1 resume >/dev/null
expect "resume regrava o snapshot" "$(sed -n 1,2p "$tmp/sess/sid1.ecc" | paste -sd'|' -)" "ligado|local"
SB=0 hook "$d" sid2 startup >/dev/null
expect "snapshot registra second brain off" "$(sed -n 3p "$tmp/sess/sid2.ecc")" off
hook "$d" "../../evil" startup >/dev/null
expect "session_id não escapa" "$(find "$tmp" -name 'evil*' -not -path "$tmp/sess/*" | wc -l | tr -d ' ')" 0
expect "sem session_id não grava" "$(printf '{"cwd":"%s"}' "$d" | bash "$HOOK" | grep -c '^ECC ligado')" 1
expect "ECC_STATUS_HOOK=0 é mudo" "$(ECC_STATUS_HOOK=0 hook "$d")" ""
expect "entrada inválida é silenciosa e rc 0" "$(printf 'lixo' | bash "$HOOK" >/dev/null 2>&1; echo $?)" 0
expect "independe do second brain" "$(SB=0 hook "$d" sid3 | grep -c '^ECC ligado')" 1

[[ $fail -eq 0 ]] && echo "ok" || exit 1
