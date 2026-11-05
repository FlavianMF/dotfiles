#!/bin/bash
# Testes das skills flow e phase (submódulo vendor/flows-editor) e do link no install.sh. Uso: bash tests/flows_skills_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -r "$tmp"' EXIT
fail=0
expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
has() { if ! grep -q -- "$2" <<<"$3"; then echo "FALHA: $1 (faltou '$2')"; fail=1; fi; }
INSTALL="$(cat "$ROOT/install.sh")"

# --- install.sh liga as skills só para o Claude Code, a partir do submódulo ---
for name in flow phase; do
    has "link de $name no submódulo" "link_claude_skill $name \"\$FLOWS_EDITOR_DIR/skills/$name\"" "$INSTALL"
    has "backup de ~/.claude/skills/$name" "\"\$HOME/.claude/skills/$name\"" "$INSTALL"
    has "backup de ~/.agents/skills/$name" "\"\$HOME/.agents/skills/$name\"" "$INSTALL"
    has "remove o link antigo de $name" "remove_stale_shared_link $name" "$INSTALL"
    expect "$name fora de link_shared_skill" "$(grep -c "link_shared_skill $name" <<<"$INSTALL")" "0"
done
has "install inicia o submódulo" "submodule update --init vendor/flows-editor" "$INSTALL"
expect ".gitmodules aponta ao repo" "$(git -C "$ROOT" config -f .gitmodules --get submodule.vendor/flows-editor.url)" "https://github.com/FlavianMF/flows-editor.git"

# --- remove_stale_shared_link remove só links de skill dos dotfiles ---
fn="$(awk '/^remove_stale_shared_link\(\) \{/ {p=1} p {print} p && /^\}/ {exit}' "$ROOT/install.sh")"
[[ -n "$fn" ]] || { echo "FALHA: remove_stale_shared_link não achada"; exit 1; }
home="$tmp/home"; skills="$home/.agents/skills"
mkdir -p "$skills/realdir"; echo x > "$skills/realdir/keep.txt"
ln -s "/a/dotfiles/agents/skills/flow" "$skills/flow"
ln -s "/b/dotfiles/agents/skills/phase" "$skills/phase"
ln -s "/elsewhere/foreign" "$skills/foreign"
ln -s "/a/dotfiles/agents/skills/another" "$skills/other"
HOME="$home" bash -c "as_user() { \"\$@\"; }; $fn; for n in flow phase foreign other realdir; do remove_stale_shared_link \"\$n\"; done"
expect "só os links alheios e a pasta ficam" "$(ls "$skills" | sort | tr '\n' ' ')" "foreign other realdir "
[[ -f "$skills/realdir/keep.txt" ]] || { echo "FALHA: pasta real foi apagada"; fail=1; }

# --- skills do submódulo (só se o submódulo estiver baixado) ---
if [[ -f "$ROOT/vendor/flows-editor/skills/flow/SKILL.md" ]]; then
    for name in flow phase; do
        grep -q '^disable-model-invocation: true$' "$ROOT/vendor/flows-editor/skills/$name/SKILL.md" || { echo "FALHA: $name sem disable-model-invocation"; fail=1; }
    done
fi

[[ $fail -eq 0 ]] && echo "flows_skills_test: ok"
exit $fail
