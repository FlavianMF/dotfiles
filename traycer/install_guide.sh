#!/bin/bash
# Copies traycer/agent-selection-guide.md to ~/.traycer/agent-selection-guide.md (a copy, never a symlink).
# The Traycer app may rewrite that file, so a link could turn into a plain file or change the repo.
# Needs no network. Does not touch ~/.traycer/.agent-selection-guide.meta.json.
# Usage: traycer/install_guide.sh [--dry-run]
#   If the destination exists and differs (or is a symlink), a dated backup is kept next to it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/agent-selection-guide.md"
DEST="$HOME/.traycer/agent-selection-guide.md"
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

[[ -r "$SRC" ]] || { echo "Missing $SRC" >&2; exit 1; }

backup=""
if [[ -L "$DEST" ]] || { [[ -e "$DEST" ]] && ! cmp -s "$SRC" "$DEST"; }; then
    backup="$DEST.bak.$(date +%Y%m%d-%H%M%S)"
elif [[ -e "$DEST" ]]; then
    echo "Traycer agent selection guide already up to date: $DEST"
    exit 0
fi

if [[ $DRY_RUN -eq 1 ]]; then
    [[ -n "$backup" ]] && echo "[dry-run] back up $DEST to $backup"
    echo "[dry-run] copy $SRC to $DEST"
    exit 0
fi

mkdir -p "$(dirname "$DEST")"
if [[ -n "$backup" ]]; then
    mv "$DEST" "$backup"
    echo "Backed up previous guide to $backup"
fi
cp "$SRC" "$DEST"
echo "Installed Traycer agent selection guide to $DEST"
