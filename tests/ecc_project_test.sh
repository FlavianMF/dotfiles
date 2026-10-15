#!/bin/bash
# Testes de claude/ecc-project.sh (on, off, status, auto). Uso: bash tests/ecc_project_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ECC="$ROOT/claude/ecc-project.sh"
tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT
fail=0

export CLAUDE_CONFIG_DIR="$tmp/userconf"; mkdir -p "$CLAUDE_CONFIG_DIR"
echo '{"enabledPlugins":{"ecc@ecc":false}}' >"$CLAUDE_CONFIG_DIR/settings.json"
user_sum="$(sha256sum "$CLAUDE_CONFIG_DIR/settings.json")"
export ECC_AUTO_CONF="$tmp/auto.conf"; echo 'kinds=web,c,node' >"$ECC_AUTO_CONF"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null

expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
has() { [[ -e "$2" ]] && echo yes || echo no; }  # has <nome> <caminho>
local_val() { jq -r '.enabledPlugins["ecc@ecc"] | if . == null then "ausente" else tostring end' "$1/.claude/settings.local.json" 2>/dev/null || echo "sem-arquivo"; }
pack_list() { ls "$1/.claude/rules/ecc-upstream" 2>/dev/null | paste -sd, -; }
newrepo() { git init -q "$tmp/$1"; git -C "$tmp/$1" commit -q --allow-empty -m i; echo "$tmp/$1"; }
web() { echo '{"dependencies":{"react":"18","next":"14"}}' >"$1/package.json"; }
cproj() { : >"$1/Makefile"; : >"$1/main.c"; }

# 1. web: liga, packs certos, sem common, nada sujo no git, usuário intocado.
d="$(newrepo web)"; web "$d"; git -C "$d" add -A; git -C "$d" commit -qm pkg
out="$("$ECC" auto "$d")"
expect "web liga" "$(local_val "$d")" true
expect "web packs" "$(pack_list "$d")" "react,typescript,web"
expect "web sem common" "$(has x "$d/.claude/rules/ecc-upstream/common")" no
expect "web git limpo" "$(git -C "$d" status --porcelain)" ""
[[ "$out" == "ECC ligado automaticamente (web: web,typescript,react)."* ]] || { echo "FALHA: linha do auto: $out"; fail=1; }
expect "usuário intocado" "$(sha256sum "$CLAUDE_CONFIG_DIR/settings.json")" "$user_sum"

# 2. idempotente e silencioso na segunda vez.
sum="$(sha256sum "$d/.claude/settings.local.json")"
expect "2ª execução silenciosa" "$("$ECC" auto "$d")" ""
expect "2ª execução idêntica" "$(sha256sum "$d/.claude/settings.local.json")" "$sum"

# 3. off cria o marcador, remove chave e links; auto não religa; on remove o marcador.
"$ECC" off "$d" >/dev/null
expect "off remove a chave" "$(local_val "$d")" ausente
expect "off remove os links" "$(has x "$d/.claude/rules/ecc-upstream")" no
expect "off cria marcador" "$(has x "$d/.claude/ecc.off")" yes
expect "auto respeita ecc.off" "$("$ECC" auto "$d")" ""
expect "auto não religou" "$(local_val "$d")" ausente
expect "status mostra ecc.off" "$("$ECC" status "$d" | grep -c 'ecc.off')" 1
"$ECC" on "$d" --no-rules >/dev/null
expect "on remove o marcador" "$(has x "$d/.claude/ecc.off")" no
expect "on --no-rules sem links" "$(has x "$d/.claude/rules/ecc-upstream")" no

# 4. escolha explícita vence: false local e chave no settings.json do projeto.
d="$(newrepo explicit_false)"; web "$d"; mkdir "$d/.claude"
echo '{"enabledPlugins":{"ecc@ecc":false},"model":"x"}' >"$d/.claude/settings.local.json"
expect "false explícito vence" "$("$ECC" auto "$d")" ""; expect "false mantido" "$(local_val "$d")" false
d="$(newrepo explicit_proj)"; web "$d"; mkdir "$d/.claude"; echo '{"enabledPlugins":{"ecc@ecc":true}}' >"$d/.claude/settings.json"
expect "settings do projeto vence" "$("$ECC" auto "$d")" ""; expect "sem local criado" "$(has x "$d/.claude/settings.local.json")" no

# 5. C e Node: só o plugin, sem rules; none: não cria nada.
d="$(newrepo cproj)"; cproj "$d"; "$ECC" auto "$d" >/dev/null
expect "C liga" "$(local_val "$d")" true; expect "C sem rules" "$(has x "$d/.claude/rules")" no
d="$(newrepo nodeb)"; echo '{"dependencies":{"express":"4"}}' >"$d/package.json"; "$ECC" auto "$d" >/dev/null
expect "Node liga" "$(local_val "$d")" true; expect "Node sem rules" "$(has x "$d/.claude/rules")" no
d="$(newrepo plain)"; echo "x" >"$d/README.md"; expect "none silencioso" "$("$ECC" auto "$d")" ""
expect "none não cria .claude" "$(has x "$d/.claude")" no

# 6. subpasta: age na raiz do git. Diretório sem git: usa o próprio diretório.
d="$(newrepo sub)"; web "$d"; mkdir -p "$d/a/b"; "$ECC" auto "$d/a/b" >/dev/null
expect "subpasta escreve na raiz" "$(local_val "$d")" true; expect "subpasta sem .claude próprio" "$(has x "$d/a/b/.claude")" no
mkdir "$tmp/nogit"; web "$tmp/nogit"; "$ECC" auto "$tmp/nogit" >/dev/null
expect "sem git usa o diretório" "$(local_val "$tmp/nogit")" true

# 7. worktree e submódulo: o exclude vale e o git fica limpo.
d="$(newrepo wt_main)"; web "$d"; git -C "$d" add -A; git -C "$d" commit -qm pkg
git -C "$d" worktree add -q "$tmp/wt_main-feature" -b feature
"$ECC" auto "$tmp/wt_main-feature" >/dev/null
expect "worktree liga" "$(local_val "$tmp/wt_main-feature")" true
expect "worktree git limpo" "$(git -C "$tmp/wt_main-feature" status --porcelain)" ""
git init -q "$tmp/sub_src"; web "$tmp/sub_src"; git -C "$tmp/sub_src" add -A; git -C "$tmp/sub_src" commit -qm i
sup="$(newrepo sup)"; git -C "$sup" -c protocol.file.allow=always submodule add -q "$tmp/sub_src" mod >/dev/null 2>&1
"$ECC" auto "$sup/mod" >/dev/null
expect "submódulo liga na raiz do submódulo" "$(local_val "$sup/mod")" true
expect "submódulo git limpo" "$(git -C "$sup/mod" status --porcelain)" ""

# 8. config: kinds, exclude, include.
d="$(newrepo conf1)"; cproj "$d"; echo 'kinds=web' >"$ECC_AUTO_CONF"
expect "kinds sem c" "$("$ECC" auto "$d")" ""; expect "kinds nada criado" "$(has x "$d/.claude")" no
printf 'kinds=web,c,node\nexclude=%s/conf2*\n' "$tmp" >"$ECC_AUTO_CONF"
d="$(newrepo conf2)"; cproj "$d"; expect "exclude" "$("$ECC" auto "$d")" ""
printf 'kinds=web,c,node\ninclude=%s/permitido/*\n' "$tmp" >"$ECC_AUTO_CONF"
mkdir "$tmp/permitido"; d="$(newrepo conf3)"; cproj "$d"; expect "include fora" "$("$ECC" auto "$d")" ""
git init -q "$tmp/permitido/p"; cproj "$tmp/permitido/p"; "$ECC" auto "$tmp/permitido/p" >/dev/null
expect "include dentro" "$(local_val "$tmp/permitido/p")" true
echo 'kinds=web,c,node' >"$ECC_AUTO_CONF"

# 9. dotfiles e on manual.
expect "dotfiles é ignorado no auto" "$("$ECC" auto "$ROOT")" ""
"$ECC" on "$ROOT" >/dev/null 2>&1; expect "on recusa o dotfiles" "$?" 1
d="$(newrepo manual)"; "$ECC" on "$d" --packs web,typescript,nao_existe >/dev/null 2>"$tmp/err"
expect "--packs" "$(pack_list "$d")" "typescript,web"; expect "pack desconhecido avisa" "$(grep -c nao_existe "$tmp/err")" 1
"$ECC" on "$d" >/dev/null; expect "on completo é link único" "$(has x "$d/.claude/rules/ecc-upstream/common")" yes
"$ECC" on "$d" --no-common >/dev/null; expect "--no-common sem common" "$(has x "$d/.claude/rules/ecc-upstream/common")" no

# 10. off e on preservam outras chaves do settings.local.json.
d="$(newrepo keys)"; mkdir "$d/.claude"; echo '{"model":"opus","env":{"A":"1"}}' >"$d/.claude/settings.local.json"
"$ECC" on "$d" --no-rules >/dev/null; "$ECC" off "$d" >/dev/null
expect "outras chaves preservadas" "$(jq -c '[.model,.env.A]' "$d/.claude/settings.local.json")" '["opus","1"]'

expect "usuário continua intocado" "$(sha256sum "$CLAUDE_CONFIG_DIR/settings.json")" "$user_sum"
[[ $fail -eq 0 ]] && echo "ok" || exit 1
