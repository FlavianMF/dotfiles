#!/bin/bash
# Testes da sugestão de ECC no SessionStart. Uso: bash tests/session_start_ecc_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/claude/hooks/second-brain-session-start.sh"
ECC="$ROOT/claude/ecc-project.sh"
tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT
fail=0

export CLAUDE_CONFIG_DIR="$tmp/userconf"; mkdir -p "$CLAUDE_CONFIG_DIR"
echo '{"enabledPlugins":{"ecc@ecc":false}}' >"$CLAUDE_CONFIG_DIR/settings.json"
export ECC_AUTO_CONF="$tmp/auto.conf"; echo 'kinds=web,c,node' >"$ECC_AUTO_CONF"
export GIT_CONFIG_GLOBAL=/dev/null
vault="$tmp/vault"; mkdir -p "$vault/00_META/skills/second-brain-sync/scripts"
printf '#!/bin/bash\nexit 0\n' >"$vault/00_META/skills/second-brain-sync/scripts/session_hint.sh"

expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
repo() { git init -q "$tmp/$1"; echo "$tmp/$1"; }
hook() { printf '{"cwd":"%s","session_id":"s"}' "$1" | SECOND_BRAIN_HOOKS=1 SECOND_BRAIN_VAULT="$vault" SECOND_BRAIN_STATE_DIR="$tmp/state" bash "$HOOK"; }

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

[[ $fail -eq 0 ]] && echo "ok" || exit 1
