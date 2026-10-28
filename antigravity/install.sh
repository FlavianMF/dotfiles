#!/bin/bash
# Installs the Antigravity CLI (`agy`) into ~/.local/bin.
# Usage: antigravity/install.sh [--dry-run] [--force]
#   --force  reinstall even if agy already exists
# Same steps as https://antigravity.google/cli/install.sh (platform manifest, sha512 check,
# extract, copy), minus its final `agy install` step: that step appends a PATH export to
# ~/.zshrc and ~/.bashrc, and ~/.zshrc here is a symlink into this repo.
# agy updates itself in the background, so the manifest version is not a pin.
set -euo pipefail
BASE_URL="${AGY_DOWNLOAD_BASE:-https://antigravity-cli-auto-updater-974169037036.us-central1.run.app}"
DEST="${AGY_BIN_DIR:-$HOME/.local/bin}"
BIN="$DEST/agy"
DRY_RUN=0
FORCE=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --force) FORCE=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

if [[ -f "$BIN" && $FORCE -eq 0 ]]; then
    echo "agy already installed at $BIN (it self-updates; use --force to reinstall), skipping"
    exit 0
fi

case "$(uname -s)" in
    Linux) os=linux ;;
    Darwin) os=darwin ;;
    *) echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
    x86_64|amd64) arch=amd64 ;;
    arm64|aarch64) arch=arm64 ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
platform="${os}_${arch}"
if [[ $os == linux ]] && { [[ -f /lib/libc.musl-x86_64.so.1 || -f /lib/libc.musl-aarch64.so.1 ]] || ldd /bin/ls 2>&1 | grep -q musl; }; then
    platform="${platform}_musl"
fi

if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] fetch $BASE_URL/manifests/$platform.json, verify sha512, install $BIN"
    exit 0
fi

command -v jq >/dev/null 2>&1 || { echo "jq not found (required package)" >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT
echo "Fetching Antigravity CLI manifest ($platform)..."
curl -fsSL -o "$tmp/manifest.json" "$BASE_URL/manifests/$platform.json"
version="$(jq -r '.version // empty' "$tmp/manifest.json")"
url="$(jq -r '.url // empty' "$tmp/manifest.json")"
sha512="$(jq -r '.sha512 // empty' "$tmp/manifest.json")"
[[ -n "$url" && -n "$sha512" ]] || { echo "Malformed manifest from $BASE_URL" >&2; exit 1; }

echo "Downloading agy ${version:-unknown}..."
curl -fsSL -o "$tmp/payload" "$url"
if command -v sha512sum >/dev/null 2>&1; then
    actual="$(sha512sum "$tmp/payload" | cut -d' ' -f1)"
else
    actual="$(shasum -a 512 "$tmp/payload" | cut -d' ' -f1)"
fi
if [[ "$actual" != "$sha512" ]]; then
    echo "sha512 mismatch for the agy payload; install aborted" >&2
    echo "  manifest: $sha512" >&2
    echo "  actual:   $actual" >&2
    exit 1
fi

case "$url" in
    *.tar.gz*)
        tar -xzf "$tmp/payload" -C "$tmp" antigravity
        src="$tmp/antigravity" ;;
    *) src="$tmp/payload" ;;
esac
mkdir -p "$DEST"
install -m 755 "$src" "$BIN"
echo "Installed $BIN (${version:-unknown})"
