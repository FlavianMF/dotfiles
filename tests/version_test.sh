#!/bin/bash
# Testes de bin/dotfiles-version. Uso: bash tests/version_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VER="$ROOT/bin/dotfiles-version"
tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -r "$tmp"' EXIT
fail=0
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export DOTFILES_VERSION_TIMEOUT=5

expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
has() { if ! grep -q -- "$2" <<<"$3"; then echo "FALHA: $1 (faltou '$2' em: $3)"; fail=1; fi; }
ver() { DOTFILES_DIR="$1" bash "$VER"; }
first() { head -n1 <<<"$1"; }

# Remoto bare + clone "a" com um commit e a tag v1.0.0 já publicados.
git init -q --bare -b master "$tmp/remote.git"
git clone -q "$tmp/remote.git" "$tmp/a" 2>/dev/null
echo base >"$tmp/a/f"; git -C "$tmp/a" add f
git -C "$tmp/a" commit -q -m "feat: base"; git -C "$tmp/a" tag v1.0.0
git -C "$tmp/a" push -q origin master v1.0.0 2>/dev/null

# 1. Tag exata na master.
expect "tag exata" "$(ver "$tmp/a")" "v1.0.0"

# 2. Commit à frente da tag: sem +N.
git -C "$tmp/a" commit -q --allow-empty -m "fix: a"
expect "à frente da tag" "$(ver "$tmp/a")" "v1.0.0"

# 3. Branch, dirty e arquivo não rastreado.
git -C "$tmp/a" checkout -q -b feat/x
expect "branch" "$(ver "$tmp/a")" "v1.0.0-feat/x"
echo novo >"$tmp/a/untracked"
expect "untracked não suja" "$(ver "$tmp/a")" "v1.0.0-feat/x"
echo mudou >>"$tmp/a/f"
expect "dirty" "$(ver "$tmp/a")" "v1.0.0-feat/x-dirty"
git -C "$tmp/a" checkout -q -- f; rm "$tmp/a/untracked"

# 4. Detached.
git -C "$tmp/a" checkout -q --detach
expect "detached" "$(ver "$tmp/a")" "v1.0.0-HEAD"
git -C "$tmp/a" checkout -q master

# 5. Atrás de origin/master: outro clone empurra um commit.
git -C "$tmp/a" push -q origin master 2>/dev/null
git clone -q "$tmp/remote.git" "$tmp/b" 2>/dev/null
git -C "$tmp/b" commit -q --allow-empty -m "feat: remoto"
git -C "$tmp/b" push -q origin master 2>/dev/null
out="$(ver "$tmp/a")"
expect "atrás: versão" "$(first "$out")" "v1.0.0"
has "atrás: aviso" "aviso:" "$out"
has "atrás: contagem" "1 commits" "$out"
git -C "$tmp/a" pull -q --ff-only origin master 2>/dev/null
expect "em dia: sem aviso" "$(ver "$tmp/a")" "v1.0.0"

# 6. Tag criada só no remoto aparece após o fetch.
git -C "$tmp/b" pull -q --ff-only origin master 2>/dev/null
git -C "$tmp/b" tag v1.1.0; git -C "$tmp/b" push -q origin v1.1.0 2>/dev/null
git -C "$tmp/a" pull -q --ff-only origin master 2>/dev/null
expect "tag remota" "$(first "$(ver "$tmp/a")")" "v1.1.0"

# 7. Offline: origin inválido.
git -C "$tmp/a" remote set-url origin /nao/existe
expect "offline" "$(first "$(ver "$tmp/a")")" "v1.1.0 (offline)"

# 8. Sem origin também é offline.
git init -q -b master "$tmp/solo"; git -C "$tmp/solo" commit -q --allow-empty -m "chore: i"
# 9. Sem tags.
expect "sem tags, sem origin" "$(ver "$tmp/solo")" "sem-tag (offline)"
git clone -q "$tmp/remote.git" "$tmp/c" 2>/dev/null
git -C "$tmp/c" tag -d v1.0.0 v1.1.0 >/dev/null 2>&1
git -C "$tmp/remote.git" tag -d v1.0.0 v1.1.0 >/dev/null 2>&1
expect "sem tags" "$(ver "$tmp/c")" "sem-tag"

# 10. Ajuda.
has "ajuda" "Uso:" "$(bash "$VER" --help)"

[[ $fail -eq 0 ]] && echo "version_test: ok"
exit $fail
