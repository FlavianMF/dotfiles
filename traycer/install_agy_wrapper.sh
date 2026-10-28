#!/bin/bash
# Installs the agy_acp_server wrapper (traycer/agy-acp-wrapper) so Traycer lists the Claude and
# GPT-OSS models of the Antigravity provider. It does not touch ~/.traycer/host/providers.
# The wrapper goes to $TRAYCER_AGY_WRAPPER_DIR (default ~/.local/bin) as `agy_acp_server`, with a
# `localharness_external` symlink beside it, which Traycer requires of a PATH install.
# Rerun after Traycer installs a new Antigravity pack, to repoint the symlink.
# Usage: traycer/install_agy_wrapper.sh [--dry-run]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${TRAYCER_AGY_WRAPPER_DIR:-$HOME/.local/bin}"
PACK="${TRAYCER_HOME_DIR:-$HOME/.traycer}/host/providers/antigravity/linux-x64"
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

command -v python3 >/dev/null 2>&1 || { echo "python3 is required by the wrapper" >&2; exit 1; }

version=""
if [[ -r "$PACK/current.json" ]]; then
    version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$PACK/current.json" 2>/dev/null || true)"
fi
companion="$PACK/$version/localharness_external"

if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] install $ROOT/agy-acp-wrapper to $DEST/agy_acp_server"
    echo "[dry-run] link $DEST/localharness_external to $companion"
    exit 0
fi

if [[ -z "$version" || ! -e "$companion" ]]; then
    echo "Antigravity pack not found under $PACK." >&2
    echo "Open Traycer and install Antigravity from Settings → Providers, then rerun." >&2
    exit 1
fi

mkdir -p "$DEST"
install -m 755 "$ROOT/agy-acp-wrapper" "$DEST/agy_acp_server"
ln -sfn "$companion" "$DEST/localharness_external"
echo "Installed the agy_acp_server wrapper to $DEST (pack $version)."
case ":$PATH:" in
    *":$DEST:"*) ;;
    *) echo "WARNING: $DEST is not on PATH, so Traycer will not find the wrapper." >&2 ;;
esac
echo "Next: in Traycer, open Settings → Providers → Antigravity, select the PATH install, and restart the host."
