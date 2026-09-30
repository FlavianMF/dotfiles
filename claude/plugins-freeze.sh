#!/bin/bash
# Grava claude/plugins.lock.json: versão de cada plugin instalado e o commit de
# cada marketplace. É um registro para comparar máquinas e revisar updates
# (git diff claude/plugins.lock.json); a fonte declarativa continua sendo
# claude/settings.json (enabledPlugins + extraKnownMarketplaces).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$REPO_DIR/claude/plugins.lock.json"

command -v claude >/dev/null 2>&1 || { echo "claude CLI não encontrado" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq não encontrado" >&2; exit 1; }

plugins="$(claude plugin list --json | jq '[.[] | {id, version, scope, enabled}] | sort_by(.id)')"

marketplaces="[]"
while IFS=$'\t' read -r name repo location; do
    [[ -z "$name" ]] && continue
    commit="$(git -C "$location" rev-parse HEAD 2>/dev/null || echo "")"
    marketplaces="$(jq --arg n "$name" --arg r "$repo" --arg c "$commit" '. + [{name: $n, repo: $r, commit: (if $c == "" then null else $c end)}]' <<< "$marketplaces")"
done < <(claude plugin marketplace list --json | jq -r '.[] | [.name, (.repo // .url // .path // ""), (.installLocation // "")] | @tsv')

jq -n --argjson p "$plugins" --argjson m "$marketplaces" \
    '{marketplaces: ($m | sort_by(.name)), plugins: $p}' > "$LOCK"
echo "Gravado $LOCK ($(jq '.plugins | length' "$LOCK") plugins, $(jq '.marketplaces | length' "$LOCK") marketplaces)"
