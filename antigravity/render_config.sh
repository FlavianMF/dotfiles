#!/bin/bash
# Renders the Antigravity CLI config files that agy rewrites at runtime, so they are
# merged instead of symlinked into the repo:
#   ~/.gemini/config/mcp_config.json            <- antigravity/mcp_config.base.json
#   ~/.gemini/antigravity-cli/settings.json     <- antigravity/settings.base.json
# Base entries win; keys that exist only on this machine (extra MCP servers, model,
# trustedWorkspaces, grants agy persisted) are kept. permissions.* arrays are unioned.
# Usage: antigravity/render_config.sh [--dry-run]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
[[ "${1:-}" == --dry-run ]] && DRY_RUN=1
MCP_TARGET="${AGY_MCP_CONFIG:-$HOME/.gemini/config/mcp_config.json}"
SETTINGS_TARGET="${AGY_SETTINGS:-$HOME/.gemini/antigravity-cli/settings.json}"

command -v jq >/dev/null 2>&1 || { echo "jq not found (required package)" >&2; exit 1; }

# render <base json> <target> <jq filter taking $cur and $base>
render() {
    local base="$1" target="$2" filter="$3" cur="{}" out
    if [[ -s "$target" ]]; then
        jq empty "$target" 2>/dev/null || { echo "$target is not valid JSON; not touching it" >&2; return 1; }
        cur="$(cat "$target")"
    fi
    out="$(jq -n --argjson cur "$cur" --slurpfile base "$base" --arg home "$HOME" "\$base[0] as \$base | $filter")"
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[dry-run] render $target"
        diff -u <(jq -S . <<<"$cur") <(jq -S . <<<"$out") || true
        return 0
    fi
    mkdir -p "$(dirname "$target")"
    # Rewrite the content, not the path: if the target is a symlink, keep it.
    cat <<<"$out" > "$target"
    echo "Rendered $target"
}

render "$ROOT/mcp_config.base.json" "$MCP_TARGET" '$cur + {mcpServers: (($cur.mcpServers // {}) + $base.mcpServers)}'

settings_base="$(mktemp)"
trap 'rm -f "$settings_base"' EXIT
sed "s|@HOME@|$HOME|g" "$ROOT/settings.base.json" > "$settings_base"
render "$settings_base" "$SETTINGS_TARGET" '
  $cur + {permissions: (($cur.permissions // {}) + (
    $base.permissions | with_entries(.value = ((($cur.permissions[.key] // []) + .value) | unique))
  ))}'
