#!/bin/bash
# Testes de claude/skills-project.sh. Uso: bash tests/skills_project_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SP="$ROOT/claude/skills-project.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0

export SKILLS_AUTO_CONF="$tmp/skills.conf" SKILLS_AUTO_SRC="$tmp/src"
mkdir -p "$tmp/src/taste" "$tmp/src/other"
printf '# comentário\ntaste=web\nother=web\nmissing=web\n' >"$SKILLS_AUTO_CONF"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null

expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
linked() { [[ -L "$1/.claude/skills/$2" ]] && echo yes || echo no; }
newrepo() { git init -q "$tmp/$1"; git -C "$tmp/$1" commit -q --allow-empty -m i; echo "$tmp/$1"; }
web() { echo '{"dependencies":{"react":"18"}}' >"$1/package.json"; }

# 1. projeto comum: nada é ligado.
d="$(newrepo plain)"
expect "comum silencioso" "$("$SP" auto "$d")" ""
expect "comum sem link" "$(linked "$d" taste)" no

# 2. projeto web: liga as skills que existem, ignora a ausente, git limpo.
d="$(newrepo web)"; web "$d"; git -C "$d" add -A; git -C "$d" commit -qm w
out="$("$SP" auto "$d")"
expect "web liga taste" "$(linked "$d" taste)" yes
expect "web liga other" "$(linked "$d" other)" yes
expect "web ignora ausente" "$(linked "$d" missing)" no
expect "aviso" "$(grep -c 'Skills ligadas neste projeto (tipo web): 2' <<<"$out")" 1
expect "git limpo" "$(git -C "$d" status --porcelain)" ""
expect "2ª execução silenciosa" "$("$SP" auto "$d")" ""
expect "status gerenciado" "$("$SP" status "$d" | grep -c 'gerenciada pelo auto')" 2

# 3. o projeto deixa de ser web: o auto apaga só o que criou.
rm "$d/package.json"
mkdir -p "$d/.claude/skills/mine"
"$SP" auto "$d" >/dev/null
expect "remove link do auto" "$(linked "$d" taste)" no
expect "preserva skill do projeto" "$([[ -d "$d/.claude/skills/mine" ]] && echo yes || echo no)" yes
expect "desfaz a posse" "$([[ -e "$d/.claude/skills.auto" ]] && echo yes || echo no)" no

# 4. skill do projeto com o mesmo nome vence.
d="$(newrepo own)"; web "$d"; mkdir -p "$d/.claude/skills/taste"
"$SP" auto "$d" >/dev/null
expect "skill do projeto intacta" "$([[ -L "$d/.claude/skills/taste" ]] && echo link || echo dir)" dir

# 5. skills.off, fora do git e o próprio dotfiles.
d="$(newrepo off)"; web "$d"; mkdir "$d/.claude"; : >"$d/.claude/skills.off"
expect "skills.off respeitado" "$("$SP" auto "$d")" ""
expect "skills.off sem link" "$(linked "$d" taste)" no
mkdir "$tmp/nogit"
expect "fora do git silencioso" "$("$SP" auto "$tmp/nogit" 2>&1)" ""
expect "dotfiles ignorado" "$("$SP" auto "$ROOT" 2>&1)" ""

# 6. tipo manual: o auto não liga; add liga sem posse e o auto não apaga.
printf 'taste=web\nmanual1=manual\n' >"$SKILLS_AUTO_CONF"; mkdir -p "$tmp/src/manual1"
d="$(newrepo manual)"; web "$d"
"$SP" auto "$d" >/dev/null
expect "manual não é ligada pelo auto" "$(linked "$d" manual1)" no
"$SP" add manual1 "$d" >/dev/null
expect "add liga" "$(linked "$d" manual1)" yes
expect "add sem posse" "$(grep -c manual1 "$d/.claude/skills.auto" 2>/dev/null)" 0
rm "$d/package.json"; "$SP" auto "$d" >/dev/null
expect "auto preserva a manual" "$(linked "$d" manual1)" yes
expect "add inexistente falha" "$("$SP" add nope "$d" >/dev/null 2>&1; echo $?)" 1

[[ $fail -eq 0 ]] && echo "ok" || exit 1
