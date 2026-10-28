#!/bin/bash
# Renders the Antigravity CLI config files that agy rewrites at runtime, so they are
# merged instead of symlinked into the repo:
#   ~/.gemini/config/mcp_config.json            <- antigravity/mcp_config.base.json
#   ~/.gemini/antigravity-cli/settings.json     <- antigravity/settings.base.json
#   ~/.gemini/config/skills.json                <- antigravity/skills.base.json
#   ~/.gemini/config/hooks.json                 <- antigravity/hooks.base.json
# agy only accepts absolute paths in skills.json ("~" fails), so @HOME@ is expanded here.
# hooks.json points at the scripts in this checkout: @REPO@ becomes the repo root. Run the
# render from the main checkout, not from a worktree that you will delete.
# Base entries win; keys that exist only on this machine (extra MCP servers, model,
# trustedWorkspaces, grants agy persisted) are kept. permissions.* arrays are unioned.
# Usage: antigravity/render_config.sh [--dry-run]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
[[ "${1:-}" == --dry-run ]] && DRY_RUN=1
MCP_TARGET="${AGY_MCP_CONFIG:-$HOME/.gemini/config/mcp_config.json}"
SETTINGS_TARGET="${AGY_SETTINGS:-$HOME/.gemini/antigravity-cli/settings.json}"
SKILLS_TARGET="${AGY_SKILLS:-$HOME/.gemini/config/skills.json}"
HOOKS_TARGET="${AGY_HOOKS:-$HOME/.gemini/config/hooks.json}"

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
skills_base="$(mktemp)"
hooks_base="$(mktemp)"
trap 'rm -f "$settings_base" "$skills_base" "$hooks_base"' EXIT
sed "s|@HOME@|$HOME|g" "$ROOT/settings.base.json" > "$settings_base"
render "$settings_base" "$SETTINGS_TARGET" '
  $cur + {permissions: (($cur.permissions // {}) + (
    $base.permissions | with_entries(.value = ((($cur.permissions[.key] // []) + .value) | unique))
  ))}'

# Older installs symlinked skills.json into the repo, where "~" is not absolute. Drop the link
# so the render below writes a real file instead of overwriting the repo copy.
if [[ -L "$SKILLS_TARGET" && $DRY_RUN -eq 0 ]]; then
    rm "$SKILLS_TARGET"
fi
sed "s|@HOME@|$HOME|g" "$ROOT/skills.base.json" > "$skills_base"
render "$skills_base" "$SKILLS_TARGET" '$cur + {entries: ((($cur.entries // []) + $base.entries) | unique_by(.path))}'

# Same symlink cleanup as skills.json: a link into the repo would make agy rewrite the base file.
if [[ -L "$HOOKS_TARGET" && $DRY_RUN -eq 0 ]]; then
    rm "$HOOKS_TARGET"
fi
sed "s|@REPO@|$(dirname "$ROOT")|g" "$ROOT/hooks.base.json" > "$hooks_base"
render "$hooks_base" "$HOOKS_TARGET" '$cur + $base'
