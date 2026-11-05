#!/bin/bash
# Testes de .github/scripts/next-version.sh. Uso: bash tests/next_version_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEXT="$ROOT/.github/scripts/next-version.sh"
tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -r "$tmp"' EXIT
fail=0
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
has() { if ! grep -q -- "$2" <<<"$3"; then echo "FALHA: $1 (faltou '$2' em: $3)"; fail=1; fi; }
# newrepo <nome> [sem-tag]: repo com um commit base e, por padrão, a tag v1.0.0.
newrepo() {
    git init -q -b master "$tmp/$1"
    git -C "$tmp/$1" commit -q --allow-empty -m "chore: base"
    [[ "${2:-}" == sem-tag ]] || git -C "$tmp/$1" tag v1.0.0
    echo "$tmp/$1"
}
commit() { git -C "$1" commit -q --allow-empty -m "$2"; }
next() { (cd "$1" && shift && bash "$NEXT" "$@"); }

# 1. Sem commit versionável: saída vazia.
d="$(newrepo none)"
commit "$d" "docs: x"; commit "$d" "chore: y"; commit "$d" "merge: z"; commit "$d" "Merge pull request #1 from a/b"; commit "$d" "sem tipo"
expect "só docs/chore/merge" "$(next "$d")" ""

# 2. fix => patch.
d="$(newrepo fix)"; commit "$d" "fix: a"
expect "fix" "$(next "$d")" "v1.0.1"

# 3. fix + feat => minor.
d="$(newrepo feat)"; commit "$d" "fix: a"; commit "$d" "feat(x): b"
expect "fix+feat" "$(next "$d")" "v1.1.0"

# 4. perf e refactor => patch.
d="$(newrepo perf)"; commit "$d" "perf: a"; commit "$d" "refactor(x): b"
expect "perf/refactor" "$(next "$d")" "v1.0.1"

# 5. Breaking por "!" e por corpo.
d="$(newrepo bang)"; commit "$d" "feat!: a"
expect "feat!" "$(next "$d")" "v2.0.0"
d="$(newrepo body)"; commit "$d" "feat: a

BREAKING CHANGE: muda tudo"
expect "BREAKING CHANGE no corpo" "$(next "$d")" "v2.0.0"

# 6. Maior bump vence com a tag anterior diferente de 1.0.0.
d="$(newrepo minor)"; commit "$d" "chore: c"; git -C "$d" tag v1.4.2; commit "$d" "feat: a"
expect "minor zera patch" "$(next "$d")" "v1.5.0"

# 7. --notes.
d="$(newrepo notes)"; commit "$d" "feat: novo recurso"; commit "$d" "fix: conserta"
out="$(next "$d" --notes "$tmp/notes.md")"
expect "notes: tag" "$out" "v1.1.0"
notes="$(cat "$tmp/notes.md")"
has "notes: Features" "Features" "$notes"
has "notes: assunto feat" "feat: novo recurso" "$notes"
has "notes: Fixes" "Fixes" "$notes"

# 8. Sem tag v*: falha com mensagem.
d="$(newrepo notag sem-tag)"; commit "$d" "feat: a"
err="$(next "$d" 2>&1)"; rc=$?
expect "sem tag: código" "$([[ $rc -ne 0 ]] && echo nonzero || echo zero)" "nonzero"
has "sem tag: mensagem" "v1.0.0" "$err"

[[ $fail -eq 0 ]] && echo "next_version_test: ok"
exit $fail
