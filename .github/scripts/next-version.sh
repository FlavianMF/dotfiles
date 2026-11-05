#!/usr/bin/env bash
set -euo pipefail

show_help() {
    cat <<'EOT'
Uso: next-version.sh [--notes ARQUIVO]

Calcula a próxima tag semver a partir dos Conventional Commits desde a última tag v*.
Rode na raiz do repo. Imprime a tag (ex.: v1.3.0), ou nada se não houver commit versionável.
Com --notes, grava a lista de commits agrupada em ARQUIVO.

Regras: "!:" ou "BREAKING CHANGE" => major, feat => minor, fix/perf/refactor => patch.
Os demais tipos (docs, chore, test, merge) e commits sem tipo não geram release.
EOT
}

notes=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --notes) notes="${2:?erro: --notes pede um arquivo}"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "erro: argumento desconhecido '$1'" >&2; exit 2 ;;
    esac
done

last="$(git describe --tags --abbrev=0 --match 'v[0-9]*' HEAD 2>/dev/null || true)"
if [[ -z "$last" ]]; then
    echo "erro: crie a tag v1.0.0 antes" >&2
    exit 1
fi
if [[ ! "$last" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "erro: a tag '$last' não é semver vX.Y.Z" >&2
    exit 1
fi
major="${BASH_REMATCH[1]}"; minor="${BASH_REMATCH[2]}"; patch="${BASH_REMATCH[3]}"

bump=0 # 0 nenhum, 1 patch, 2 minor, 3 major
breaking=""; features=""; fixes=""

while IFS= read -r -d $'\x1e' record; do
    record="${record#$'\n'}"
    [[ -n "$record" ]] || continue
    hash="${record%%$'\x1f'*}"; rest="${record#*$'\x1f'}"
    subject="${rest%%$'\x1f'*}"; body="${rest#*$'\x1f'}"
    line="- $subject (${hash:0:7})"
    if [[ "$subject" =~ ^[a-z]+(\(.+\))?!: ]] || grep -qE '^BREAKING[ -]CHANGE' <<<"$body"; then
        bump=3; breaking+="$line"$'\n'
    elif [[ "$subject" =~ ^feat(\(.+\))?: ]]; then
        [[ $bump -ge 2 ]] || bump=2
        features+="$line"$'\n'
    elif [[ "$subject" =~ ^(fix|perf|refactor)(\(.+\))?: ]]; then
        [[ $bump -ge 1 ]] || bump=1
        fixes+="$line"$'\n'
    fi
done < <(git log --format='%H%x1f%s%x1f%b%x1e' "$last..HEAD")

case $bump in
    0) exit 0 ;;
    1) patch=$((patch + 1)) ;;
    2) minor=$((minor + 1)); patch=0 ;;
    3) major=$((major + 1)); minor=0; patch=0 ;;
esac

if [[ -n "$notes" ]]; then
    : >"$notes"
    [[ -z "$breaking" ]] || printf '## Breaking\n\n%s\n' "$breaking" >>"$notes"
    [[ -z "$features" ]] || printf '## Features\n\n%s\n' "$features" >>"$notes"
    [[ -z "$fixes" ]] || printf '## Fixes\n\n%s\n' "$fixes" >>"$notes"
fi

echo "v$major.$minor.$patch"
