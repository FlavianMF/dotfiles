#!/bin/bash
# Installs the Traycer desktop AppImage into ~/.local/opt/traycer, pinned by sha256.
# It also copies the agent selection guide to ~/.traycer through traycer/install_guide.sh.
# Usage: traycer/install.sh [--dry-run] [--update]
#   --update  download the current "latest" build and rewrite traycer/SHA256, without installing.
#             Review the diff, then run the installer again.
# Upstream publishes no version or checksum, so the pin is the sha256 stored in traycer/SHA256.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
URL="https://github.com/traycerai/traycer/releases/latest/download/traycer-desktop-linux-x86_64.AppImage"
NAME="traycer-desktop-linux-x86_64.AppImage"
DEST="${TRAYCER_HOME:-$HOME/.local/opt/traycer}"
BIN="${TRAYCER_BIN:-$HOME/.local/bin/traycer}"
DRY_RUN=0
UPDATE=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --update) UPDATE=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

# The agent selection guide is a local copy and needs no network, so it runs before the download.
if [[ $UPDATE -eq 0 ]]; then
    guide_args=()
    [[ $DRY_RUN -eq 1 ]] && guide_args=(--dry-run)
    bash "$ROOT/install_guide.sh" "${guide_args[@]}" || echo "WARNING: could not install the agent selection guide." >&2
    # The wrapper needs the Antigravity pack that Traycer downloads, so a missing pack only warns.
    wrapper_args=()
    [[ $DRY_RUN -eq 1 ]] && wrapper_args=(--dry-run)
    bash "$ROOT/install_agy_wrapper.sh" "${wrapper_args[@]}" || echo "WARNING: could not install the agy_acp_server wrapper." >&2
fi

[[ "$(uname -m)" == x86_64 ]] || { echo "Traycer ships x86_64 builds only (this is $(uname -m))" >&2; exit 1; }

has_libfuse2() { /sbin/ldconfig -p 2>/dev/null | grep -q 'libfuse\.so\.2'; }
# Ubuntu 24.04+ and Debian 13+ renamed libfuse2 to libfuse2t64.
fuse_pkg() { if apt-cache show libfuse2t64 >/dev/null 2>&1; then echo libfuse2t64; else echo libfuse2; fi; }

if [[ $DRY_RUN -eq 1 ]]; then
    if [[ $UPDATE -eq 1 ]]; then
        echo "[dry-run] download $URL and write $ROOT/SHA256"
    else
        echo "[dry-run] download $URL, verify against $ROOT/SHA256"
        has_libfuse2 || echo "[dry-run] sudo apt-get install -y $(fuse_pkg)"
        echo "[dry-run] install $DEST/traycer.AppImage and wrapper $BIN"
    fi
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT
echo "Downloading Traycer AppImage..."
curl -fsSL -o "$tmp/$NAME" "$URL"
actual="$(sha256sum "$tmp/$NAME" | cut -d' ' -f1)"

if [[ $UPDATE -eq 1 ]]; then
    printf '%s  %s\n' "$actual" "$NAME" > "$ROOT/SHA256"
    echo "Wrote $ROOT/SHA256 ($actual). Review git diff, then rerun traycer/install.sh."
    exit 0
fi

[[ -r "$ROOT/SHA256" ]] || { echo "Missing $ROOT/SHA256; run traycer/install.sh --update" >&2; exit 1; }
expected="$(cut -d' ' -f1 < "$ROOT/SHA256")"
if [[ "$actual" != "$expected" ]]; then
    echo "sha256 mismatch for $NAME" >&2
    echo "  pinned: $expected" >&2
    echo "  actual: $actual" >&2
    echo "Upstream changed the build. Review it, then run traycer/install.sh --update." >&2
    exit 1
fi

# The AppImage mounts itself through libfuse.so.2. Install it when apt is available.
if ! has_libfuse2 && command -v apt-get >/dev/null 2>&1; then
    pkg="$(fuse_pkg)"
    echo "Installing $pkg (libfuse.so.2, needed to mount the AppImage)..."
    if [[ $EUID -eq 0 ]]; then apt-get install -y "$pkg"; else sudo apt-get install -y "$pkg"; fi \
        || echo "WARNING: could not install $pkg; the launcher falls back to extract-and-run." >&2
fi

mkdir -p "$DEST" "$(dirname "$BIN")"
install -m 755 "$tmp/$NAME" "$DEST/traycer.AppImage"
cat > "$BIN" <<'WRAP'
#!/bin/bash
# Launcher for the pinned Traycer AppImage. The AppImage runtime mounts itself through libfuse.so.2
# (package libfuse2, libfuse2t64 on Ubuntu 24.04+). fusermount3 alone is not enough. Without that
# library or /dev/fuse, the AppImage extracts itself and runs instead.
app="${TRAYCER_HOME:-$HOME/.local/opt/traycer}/traycer.AppImage"
if [[ ! -e /dev/fuse ]] || ! /sbin/ldconfig -p 2>/dev/null | grep -q 'libfuse\.so\.2'; then
    export APPIMAGE_EXTRACT_AND_RUN=1
fi
exec "$app" "$@"
WRAP
chmod 755 "$BIN"
echo "Installed Traycer to $DEST, launcher at $BIN"

if ! has_libfuse2; then
    echo "NOTE: libfuse.so.2 is still missing, so the launcher extracts the AppImage on every run (slower start)." >&2
    echo "To mount it instead, run: sudo apt-get install -y $(fuse_pkg 2>/dev/null || echo libfuse2t64)" >&2
fi

if [[ "$(cat /proc/1/comm 2>/dev/null)" != systemd ]]; then
    echo "WARNING: systemd is not PID 1. Traycer's host needs it." >&2
    echo "Add \"[boot]\" and \"systemd=true\" to /etc/wsl.conf, then run: wsl --shutdown" >&2
fi
