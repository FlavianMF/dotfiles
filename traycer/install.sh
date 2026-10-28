#!/bin/bash
# Installs the Traycer desktop AppImage into ~/.local/opt/traycer, pinned by sha256.
# It also copies the agent selection guide to ~/.traycer through traycer/install_guide.sh
# and pre-populates the local speech-to-text model (parakeet-tdt-0.6b-v3) from GitHub Releases.
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
STT_MODEL="parakeet-tdt-0.6b-v3"
STT_ARCHIVE="sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"
STT_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${STT_ARCHIVE}.tar.bz2"
STT_SHA256="${TRAYCER_STT_SHA256:-5793d0fd397c5778d2cf2126994d58e9d56b1be7c04d13c7a15bb1b4eafb16bf}"
STT_DIR="$HOME/.traycer/models/stt/$STT_MODEL"
STT_FILES=(encoder.int8.onnx decoder.int8.onnx joiner.int8.onnx tokens.txt)
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
fi

[[ "$(uname -m)" == x86_64 ]] || { echo "Traycer ships x86_64 builds only (this is $(uname -m))" >&2; exit 1; }

has_libfuse2() { /sbin/ldconfig -p 2>/dev/null | grep -q 'libfuse\.so\.2'; }
# Ubuntu 24.04+ and Debian 13+ renamed libfuse2 to libfuse2t64.
fuse_pkg() { if apt-cache show libfuse2t64 >/dev/null 2>&1; then echo libfuse2t64; else echo libfuse2; fi; }

has_stt_model() {
    local f
    for f in "${STT_FILES[@]}"; do
        [[ -s "$STT_DIR/$f" ]] || return 1
    done
}

# Traycer downloads parakeet-tdt-0.6b-v3 from huggingface.co on the first dictation.
# Some networks block or SSL-intercept huggingface.co, for example the FortiGuard
# "Artificial Intelligence Technology" filter. There Node's fetch in ai.traycer.host.service fails with
# "unable to verify the first certificate". This function copies the model from the upstream
# sherpa-onnx GitHub release instead. The caller runs it after "||", so set -e is off in the body:
# every step that can fail needs its own "|| return 1".
install_stt_model() {
    if has_stt_model; then
        echo "Traycer STT model already installed: $STT_DIR"
        return 0
    fi
    local archive="$tmp/${STT_ARCHIVE}.tar.bz2" stage="$tmp/stt-stage" actual f
    local -a members=()
    echo "Downloading Traycer STT model ($STT_MODEL)..."
    curl -fsSL -o "$archive" "$STT_URL" || return 1
    actual="$(sha256sum "$archive" | cut -d' ' -f1)"
    if [[ "$actual" != "$STT_SHA256" ]]; then
        echo "sha256 mismatch for ${STT_ARCHIVE}.tar.bz2" >&2
        echo "  pinned: $STT_SHA256" >&2
        echo "  actual: $actual" >&2
        return 1
    fi
    mkdir -p "$stage" || return 1
    for f in "${STT_FILES[@]}"; do
        members+=("$STT_ARCHIVE/$f")
    done
    tar -xjf "$archive" -C "$stage" --strip-components=1 "${members[@]}" || return 1
    for f in "${STT_FILES[@]}"; do
        [[ -s "$stage/$f" ]] || return 1
    done
    mkdir -p "$STT_DIR" || return 1
    for f in "${STT_FILES[@]}"; do
        mv -f "$stage/$f" "$STT_DIR/$f" || return 1
    done
    echo "Installed Traycer STT model ($STT_MODEL) to $STT_DIR"
}

if [[ $DRY_RUN -eq 1 ]]; then
    if [[ $UPDATE -eq 1 ]]; then
        echo "[dry-run] download $URL and write $ROOT/SHA256"
    else
        echo "[dry-run] download $URL, verify against $ROOT/SHA256"
        has_libfuse2 || echo "[dry-run] sudo apt-get install -y $(fuse_pkg)"
        echo "[dry-run] install $DEST/traycer.AppImage and wrapper $BIN"
        if has_stt_model; then
            echo "Traycer STT model already installed: $STT_DIR"
        else
            echo "[dry-run] download $STT_URL, verify sha256 and extract $STT_MODEL to $STT_DIR"
        fi
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

install_stt_model || echo "WARNING: could not install Traycer STT model ($STT_MODEL); voice dictation will try to download it at runtime." >&2

if ! has_libfuse2; then
    echo "NOTE: libfuse.so.2 is still missing, so the launcher extracts the AppImage on every run (slower start)." >&2
    echo "To mount it instead, run: sudo apt-get install -y $(fuse_pkg 2>/dev/null || echo libfuse2t64)" >&2
fi

if [[ "$(cat /proc/1/comm 2>/dev/null)" != systemd ]]; then
    echo "WARNING: systemd is not PID 1. Traycer's host needs it." >&2
    echo "Add \"[boot]\" and \"systemd=true\" to /etc/wsl.conf, then run: wsl --shutdown" >&2
fi
