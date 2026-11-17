#!/bin/bash
# Testes do espelho do to-do do over9k para o cockpit (todo.sh mirror), num HOME temporário.
# Uso: bash tests/over9k_todos_mirror_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TODO="$ROOT/herdr/app/mods/over9k-todos/todo.sh"
tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT
fail=0
ok() { [[ "$2" == "$3" ]] || { echo "FALHA: $1 (obtido '$3', esperado '$2')"; fail=1; }; }

mkdir -p "$tmp/home/.config/cockpit" "$tmp/pa" "$tmp/pb"
git -C "$tmp/pa" init -q; git -C "$tmp/pb" init -q
out="$tmp/home/.config/cockpit/todo.md"
t() { (cd "$1" && shift && HOME="$tmp/home" sh "$TODO" "$@" >/dev/null); }
lines() { tail -n +2 "$out"; }

# Um todo.md que não é do espelho vai para backup.
echo '- [ ] velho do cockpit' >"$out"
t "$tmp/pa" add "item A1"
ok "backup do todo.md antigo" 1 "$(ls "$tmp/home/.config/cockpit" | grep -c '^todo.md.bak')"
ok "marca do espelho" 1 "$(head -n 1 "$out" | grep -c 'over9k-mirror:')"

# Vários projetos, com o projeto no fim da linha.
t "$tmp/pa" add "item A2"
t "$tmp/pb" add "item B1"
ok "três itens abertos" 3 "$(lines | grep -c '^- \[ \] ')"
ok "projeto no fim da linha" 1 "$(lines | grep -c 'item B1 · pb$')"

# Prazo como @data, com e sem hora; sem prazo não leva @.
t "$tmp/pa" add --due "2026-11-20 15:00" "com hora"
t "$tmp/pa" add --due "2026-11-21" "so data"
ok "prazo com hora" 1 "$(lines | grep -c 'com hora @2026-11-20 15:00 · pa$')"
ok "prazo só com data" 1 "$(lines | grep -c 'so data @2026-11-21 · pa$')"
ok "sem prazo, sem @" 0 "$(lines | grep 'item A1' | grep -c '@')"
ok "sem comentário html" 0 "$(lines | grep -c '<!--')"

# Item feito hoje entra marcado, e rm sai do espelho.
t "$tmp/pa" done 1
ok "feito hoje marcado" 1 "$(lines | grep -c '^- \[x\] item A1 · pa$')"
t "$tmp/pa" rm 2
ok "rm tira o item" 0 "$(lines | grep -c 'item A2')"

# COCKPIT_TODO_MIRROR=off não grava.
before="$(cat "$out")"
(cd "$tmp/pa" && HOME="$tmp/home" COCKPIT_TODO_MIRROR=off sh "$TODO" add "nao espelha" >/dev/null)
ok "off não espelha" "$before" "$(cat "$out")"

((fail)) && exit 1
echo "ok: over9k_todos_mirror_test"
