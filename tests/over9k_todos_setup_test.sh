#!/bin/bash
# Testes do botão "Let agents keep these lists" (over9k-todos): setup.sh todo on|off
# num HOME temporário, com ~/.claude e ~/.codex como symlinks.
# Uso: bash tests/over9k_todos_setup_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODS="$ROOT/herdr/app/mods"
SETUP="$MODS/over9k-options/setup.sh"
tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT
fail=0
ok() { [[ "$2" == "$3" ]] || { echo "FALHA: $1 (obtido '$3', esperado '$2')"; fail=1; }; }

command -v jq >/dev/null || { echo "SKIP: jq ausente"; exit 0; }

mkdir -p "$tmp/real" "$tmp/home/.claude" "$tmp/home/.codex"
echo "# base" >"$tmp/real/CLAUDE.md"; echo "# agents" >"$tmp/real/AGENTS.md"; echo '{}' >"$tmp/real/settings.json"
ln -s "$tmp/real/CLAUDE.md" "$tmp/home/.claude/CLAUDE.md"
ln -s "$tmp/real/AGENTS.md" "$tmp/home/.codex/AGENTS.md"
ln -s "$tmp/real/settings.json" "$tmp/home/.claude/settings.json"
rule() { grep -c '<!-- over9k:todo -->' "$1"; }
# O botão passa o setup.sh por `sh -c` (não por arquivo), como o mod faz no WSL.
run() { HOME="$tmp/home" sh -c "$(cat "$SETUP")" sh todo "$1" "$MODS"; }

run on; ok "exit do on" 0 $?
ok "regra no CLAUDE.md real" 1 "$(rule "$tmp/real/CLAUDE.md")"
ok "regra no AGENTS.md real" 1 "$(rule "$tmp/real/AGENTS.md")"
[[ -L "$tmp/home/.claude/CLAUDE.md" ]] && s=symlink || s=arquivo; ok "CLAUDE.md segue symlink" symlink "$s"
[[ -L "$tmp/home/.codex/AGENTS.md" ]] && s=symlink || s=arquivo; ok "AGENTS.md segue symlink" symlink "$s"
ok "hook no settings real" 1 "$(jq '[.hooks.UserPromptSubmit[]?.hooks[]?.command | select(contains("todo-hook.sh"))] | length' "$tmp/real/settings.json")"
ok "wrapper todo criado" 1 "$([[ -x "$tmp/home/.local/bin/todo" ]] && echo 1 || echo 0)"
HOME="$tmp/home" sh -c 'grep -q "<!-- over9k:todo -->" "$HOME/.claude/CLAUDE.md"'; ok "checkRule vê a regra" 0 $?

run on; ok "segundo on não duplica" 1 "$(rule "$tmp/real/CLAUDE.md")"
run off; ok "exit do off" 0 $?
ok "off remove a regra" 0 "$(rule "$tmp/real/CLAUDE.md")"
ok "off remove o wrapper" 0 "$([[ -e "$tmp/home/.local/bin/todo" ]] && echo 1 || echo 0)"

# CLAUDE.md que importa o AGENTS.md (`@...AGENTS.md`): só o AGENTS.md recebe a regra.
printf '@%s\n# base\n' "$tmp/real/AGENTS.md" >"$tmp/real/CLAUDE.md"
run on; ok "import: exit do on" 0 $?
ok "import: CLAUDE.md sem a regra" 0 "$(rule "$tmp/real/CLAUDE.md")"
ok "import: AGENTS.md com a regra" 1 "$(rule "$tmp/real/AGENTS.md")"
HOME="$tmp/home" sh -c 'grep -q "<!-- over9k:todo -->" "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md" 2>/dev/null'; ok "import: checkRule vê a regra" 0 $?
run off
ok "import: off remove a regra do AGENTS.md" 0 "$(rule "$tmp/real/AGENTS.md")"

((fail)) && exit 1
echo "ok: over9k_todos_setup_test"
