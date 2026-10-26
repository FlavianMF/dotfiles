#!/bin/bash
# Installs Claude Code Router pinned to ccr/VERSION into ~/.local (npm).
# Usage: ccr/install.sh [--dry-run] [--update X.Y.Z]
#   --update X.Y.Z  rewrite ccr/VERSION first, then install that version
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${CCR_PREFIX:-$HOME/.local}"
DRY_RUN=0
UPDATE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --update) UPDATE="${2:-}"; shift ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

run() {
    if [[ $DRY_RUN -eq 1 ]]; then echo "[dry-run] $*"; else "$@"; fi
}

if [[ -n "$UPDATE" ]]; then
    [[ "$UPDATE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid version: $UPDATE" >&2; exit 2; }
    run bash -c 'printf "%s\n" "$1" > "$2"' _ "$UPDATE" "$ROOT/VERSION"
    VERSION="$UPDATE"
else
    VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
fi

command -v npm >/dev/null 2>&1 || { echo "npm not found; install Node 22+ (component node, or nvm)" >&2; exit 1; }
NODE_MAJOR="$(node -v 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/')"
if [[ -z "$NODE_MAJOR" || "$NODE_MAJOR" -lt 22 ]]; then
    echo "CCR $VERSION needs Node 22+ (found: ${NODE_MAJOR:-none})" >&2
    exit 1
fi

INSTALLED="$(npm ls -g --prefix "$PREFIX" --depth=0 --json 2>/dev/null | jq -r '.dependencies["@musistudio/claude-code-router"].version // empty' || true)"
if [[ "$INSTALLED" == "$VERSION" ]]; then
    echo "CCR $VERSION already installed in $PREFIX, skipping"
    exit 0
fi
echo "Installing @musistudio/claude-code-router@$VERSION into $PREFIX (was: ${INSTALLED:-none})..."
run npm install -g --prefix "$PREFIX" "@musistudio/claude-code-router@$VERSION"
