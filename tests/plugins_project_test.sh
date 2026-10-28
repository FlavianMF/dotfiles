#!/bin/bash
# Testes de claude/plugins-project.sh (camada de carga). Uso: bash tests/plugins_project_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PP="$ROOT/claude/plugins-project.sh"
tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -r "$tmp"' EXIT
fail=0
P="figma@claude-plugins-official"

export PLUGINS_AUTO_CONF="$tmp/plugins.conf"
printf '# comentário\n%s=web\n' "$P" >"$PLUGINS_AUTO_CONF"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null

expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
val() { jq -r --arg p "$P" '.enabledPlugins[$p] | if . == null then "ausente" else tostring end' "$1/.claude/settings.local.json" 2>/dev/null || echo "sem-arquivo"; }
newrepo() { git init -q "$tmp/$1"; git -C "$tmp/$1" commit -q --allow-empty -m i; echo "$tmp/$1"; }
web() { echo '{"dependencies":{"react":"18"}}' >"$1/package.json"; }

# 1. projeto comum: desliga o figma, lista o que gerencia, git limpo.
d="$(newrepo plain)"; echo x >"$d/README.md"; git -C "$d" add -A; git -C "$d" commit -qm r
out="$("$PP" auto "$d")"
expect "comum desliga" "$(val "$d")" false
expect "aviso" "$(grep -c 'Plugins desligados neste projeto (tipo none): figma' <<<"$out")" 1
expect "git limpo" "$(git -C "$d" status --porcelain)" ""
expect "status gerenciado" "$("$PP" status "$d" | grep -c 'gerenciado pelo auto')" 1

# 2. idempotente e silencioso.
sum="$(sha256sum "$d/.claude/settings.local.json")"
expect "2ª execução silenciosa" "$("$PP" auto "$d")" ""
expect "2ª execução idêntica" "$(sha256sum "$d/.claude/settings.local.json")" "$sum"

# 3. o projeto vira web: o auto apaga a chave que gravou e preserva o resto.
jq '.permissions.allow = ["Bash(ls)"]' "$d/.claude/settings.local.json" >"$tmp/x" && mv "$tmp/x" "$d/.claude/settings.local.json"
web "$d"
expect "web silencioso" "$("$PP" auto "$d")" ""
expect "web apaga a chave" "$(val "$d")" ausente
expect "web preserva o resto" "$(jq -r '.permissions.allow[0]' "$d/.claude/settings.local.json")" "Bash(ls)"
expect "web desfaz a posse" "$([[ -e "$d/.claude/plugins.auto" ]] && echo yes || echo no)" no

# 4. web desde o início: não escreve nada.
d="$(newrepo web)"; web "$d"
expect "web silencioso" "$("$PP" auto "$d")" ""
expect "web sem arquivo" "$(val "$d")" sem-arquivo

# 5. decisão do usuário vence (true em settings.local.json; false em settings.json do projeto).
d="$(newrepo user_true)"; mkdir "$d/.claude"
echo "{\"enabledPlugins\":{\"$P\":true}}" >"$d/.claude/settings.local.json"
expect "true do usuário silencioso" "$("$PP" auto "$d")" ""
expect "true do usuário intacto" "$(val "$d")" true
d="$(newrepo user_proj)"; mkdir "$d/.claude"
echo "{\"enabledPlugins\":{\"$P\":true}}" >"$d/.claude/settings.json"
"$PP" auto "$d" >/dev/null
expect "settings.json do projeto vence" "$(val "$d")" sem-arquivo

# 6. plugins.off, settings inválido, fora do git e o próprio dotfiles.
d="$(newrepo off)"; mkdir "$d/.claude"; : >"$d/.claude/plugins.off"
expect "plugins.off respeitado" "$("$PP" auto "$d")" ""
expect "plugins.off sem arquivo" "$(val "$d")" sem-arquivo
d="$(newrepo bad)"; mkdir "$d/.claude"; echo '[1]' >"$d/.claude/settings.local.json"
expect "settings inválido silencioso" "$("$PP" auto "$d" 2>&1)" ""
mkdir "$tmp/nogit"
expect "fora do git silencioso" "$("$PP" auto "$tmp/nogit" 2>&1)" ""
expect "dotfiles ignorado" "$("$PP" auto "$ROOT" 2>&1)" ""

[[ $fail -eq 0 ]] && echo "ok" || exit 1
