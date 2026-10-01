#!/bin/bash
# Espelha rules/** do ECC num commit fixado em vendor/ecc/upstream/rules/.
#
# Uso: vendor/ecc/fetch-upstream.sh [sha]   (padrão: o pin de vendor/ecc/SOURCE.md)
#
# Sem edição manual: é cópia fiel do upstream, exceto o README e os */hooks.md (descrevem hooks
# do runtime do ECC que não instalamos). Linkado por projeto via claude/ecc-project.sh.
# Revise com: git diff --stat vendor/ecc/upstream && git diff vendor/ecc/upstream
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="affaan-m/ECC"
SHA="${1:-$(grep -oE '[0-9a-f]{40}' "$DIR/SOURCE.md" | head -1)}"
DEST="$DIR/upstream/rules"

[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "SHA inválido: '$SHA' (use o hash completo)" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq não encontrado" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl não encontrado" >&2; exit 1; }

tree_url="https://api.github.com/repos/$REPO/git/trees/$SHA?recursive=1"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    tree="$(gh api "repos/$REPO/git/trees/$SHA?recursive=1")"
else
    tree="$(curl -fsSL "$tree_url")"
fi
[[ "$(jq -r '.truncated' <<< "$tree")" == false ]] || { echo "Árvore truncada pela API do GitHub" >&2; exit 1; }

mapfile -t files < <(jq -r '.tree[] | select(.type == "blob") | .path
    | select(startswith("rules/") and endswith(".md") and (endswith("/hooks.md") | not) and . != "rules/README.md")' <<< "$tree")
[[ ${#files[@]} -gt 0 ]] || { echo "Nenhuma rule encontrada em $SHA" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for path in "${files[@]}"; do
    mkdir -p "$tmp/$(dirname "$path")"
    curl -fsSL "https://raw.githubusercontent.com/$REPO/$SHA/$path" -o "$tmp/$path"
done
printf '%s\n' "$SHA" > "$tmp/rules/.ecc-sha"

rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
mv "$tmp/rules" "$DEST"
echo "Gravado $DEST (${#files[@]} arquivos @ ${SHA:0:7})"
