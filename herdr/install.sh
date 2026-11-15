#!/bin/bash
# Installs Herdr pinned by herdr/VERSION and herdr/SHA256 into ~/.local/bin.
# Usage: herdr/install.sh [--dry-run] [--update [x.y.z]]
#   --update  fetch release from herdr.dev / GitHub and rewrite herdr/VERSION and herdr/SHA256
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HERDR_BIN_DIR:-$HOME/.local/bin}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/herdr"
BIN_NAME="herdr"
MANIFEST_URL="https://herdr.dev/latest.json"

DRY_RUN=0
UPDATE=0
UPDATE_VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --update)
            UPDATE=1
            if [[ "${2:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                UPDATE_VERSION="$2"
                shift
            fi
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
    shift
done

run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[dry-run] $*"
    else
        "$@"
    fi
}

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|amd64)   TARGET="linux-x86_64" ;;
    aarch64|arm64)  TARGET="linux-aarch64" ;;
    *)
        echo "herdr: unsupported architecture: $ARCH" >&2
        exit 1
        ;;
esac

if [[ $UPDATE -eq 1 ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[dry-run] query ${UPDATE_VERSION:-latest} from $MANIFEST_URL and update herdr/VERSION and herdr/SHA256"
        exit 0
    fi

    echo "Fetching release metadata..."
    if [[ -n "$UPDATE_VERSION" ]]; then
        API_URL="https://api.github.com/repos/herdrdev/herdr/releases/tags/v${UPDATE_VERSION}"
        curl -fsSL "$API_URL" >/dev/null
        VERSION="$UPDATE_VERSION"
        # Download and calculate hash if not in manifest
        TMP_HASH="$(mktemp -d)"
        trap 'rm -rf "$TMP_HASH"' EXIT
        DL_URL="https://github.com/herdrdev/herdr/releases/download/v${VERSION}/herdr-${TARGET}"
        curl -fsSL "$DL_URL" -o "$TMP_HASH/herdr"
        HASH="$(sha256sum "$TMP_HASH/herdr" | awk '{print $1}')"
        printf '%s\n' "$VERSION" > "$ROOT/VERSION"
        # Update matching target line in SHA256 file
        awk -v t="herdr-$TARGET" -v h="$HASH" '$2 == t { $1 = h } { print }' "$ROOT/SHA256" > "$ROOT/SHA256.tmp"
        mv "$ROOT/SHA256.tmp" "$ROOT/SHA256"
        echo "Pinned Herdr $VERSION ($TARGET: $HASH). Review git diff, then run herdr/install.sh."
        exit 0
    else
        MANIFEST="$(curl -fsSL "$MANIFEST_URL")"
        VERSION="$(jq -r '.version' <<< "$MANIFEST")"
        HASH_X86="$(jq -r '.sha256["linux-x86_64"] // empty' <<< "$MANIFEST")"
        HASH_ARM="$(jq -r '.sha256["linux-aarch64"] // empty' <<< "$MANIFEST")"
        printf '%s\n' "$VERSION" > "$ROOT/VERSION"
        {
            [[ -n "$HASH_X86" ]] && printf '%s  herdr-linux-x86_64\n' "$HASH_X86"
            [[ -n "$HASH_ARM" ]] && printf '%s  herdr-linux-aarch64\n' "$HASH_ARM"
        } > "$ROOT/SHA256"
        echo "Pinned Herdr $VERSION. Review git diff, then run herdr/install.sh."
        exit 0
    fi
fi

[[ -r "$ROOT/VERSION" && -r "$ROOT/SHA256" ]] || {
    echo "Missing $ROOT/VERSION or $ROOT/SHA256; run herdr/install.sh --update" >&2
    exit 1
}

VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
EXPECTED_SHA="$(awk -v t="herdr-$TARGET" '$2 == t { print $1 }' "$ROOT/SHA256")"

if [[ -z "$EXPECTED_SHA" ]]; then
    echo "herdr: no SHA256 checksum pinned for $TARGET in $ROOT/SHA256" >&2
    exit 1
fi

# Check if current installed binary already matches pinned version
CURRENT_VERSION=""
if command -v "$BIN_DIR/$BIN_NAME" >/dev/null 2>&1; then
    CURRENT_VERSION="$("$BIN_DIR/$BIN_NAME" --version 2>/dev/null | awk '{print $2}' || true)"
fi

if [[ "$CURRENT_VERSION" == "$VERSION" ]]; then
    echo "Herdr $VERSION already installed in $BIN_DIR/$BIN_NAME"
else
    DOWNLOAD_URL="https://github.com/herdrdev/herdr/releases/download/v${VERSION}/herdr-${TARGET}"
    echo "Installing Herdr $VERSION ($TARGET) into $BIN_DIR..."

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[dry-run] curl -fsSL $DOWNLOAD_URL -o $BIN_DIR/$BIN_NAME"
        echo "[dry-run] verify sha256: $EXPECTED_SHA"
        echo "[dry-run] chmod +x $BIN_DIR/$BIN_NAME"
    else
        TMP_DIR="$(mktemp -d)"
        trap 'rm -rf "$TMP_DIR"' EXIT
        curl -fsSL --retry 3 --connect-timeout 10 --max-time 120 "$DOWNLOAD_URL" -o "$TMP_DIR/$BIN_NAME"

        ACTUAL_SHA="$(sha256sum "$TMP_DIR/$BIN_NAME" | awk '{print $1}')"
        if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
            echo "ERROR: Checksum mismatch for Herdr $VERSION ($TARGET)!" >&2
            echo "Expected: $EXPECTED_SHA" >&2
            echo "Actual:   $ACTUAL_SHA" >&2
            exit 1
        fi

        mkdir -p "$BIN_DIR"
        mv "$TMP_DIR/$BIN_NAME" "$BIN_DIR/$BIN_NAME"
        chmod +x "$BIN_DIR/$BIN_NAME"
        echo "Herdr $VERSION installed successfully to $BIN_DIR/$BIN_NAME."
    fi
fi

# Configure ~/.config/herdr/config.toml link
if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] link $ROOT/config.toml to $CONFIG_DIR/config.toml"
else
    mkdir -p "$CONFIG_DIR"
    TARGET_CONFIG="$CONFIG_DIR/config.toml"
    SRC_CONFIG="$ROOT/config.toml"

    if [[ -L "$TARGET_CONFIG" ]]; then
        CURRENT_LINK="$(readlink -f "$TARGET_CONFIG")"
        if [[ "$CURRENT_LINK" != "$SRC_CONFIG" ]]; then
            ln -sf "$SRC_CONFIG" "$TARGET_CONFIG"
            echo "Updated link: $TARGET_CONFIG -> $SRC_CONFIG"
        fi
    elif [[ -f "$TARGET_CONFIG" ]]; then
        BACKUP="$TARGET_CONFIG.bak.$(date +%Y%m%d-%H%M%S)"
        echo "Backing up existing $TARGET_CONFIG to $BACKUP"
        mv "$TARGET_CONFIG" "$BACKUP"
        ln -s "$SRC_CONFIG" "$TARGET_CONFIG"
        echo "Created link: $TARGET_CONFIG -> $SRC_CONFIG"
    else
        ln -s "$SRC_CONFIG" "$TARGET_CONFIG"
        echo "Created link: $TARGET_CONFIG -> $SRC_CONFIG"
    fi
fi

# Setup Agent Integrations if available and running for real
if [[ $DRY_RUN -eq 0 ]] && command -v "$BIN_DIR/$BIN_NAME" >/dev/null 2>&1; then
    if command -v claude >/dev/null 2>&1; then
        echo "Setting up Claude Code integration..."
        "$BIN_DIR/$BIN_NAME" integration install claude >/dev/null 2>&1 || true
    fi
    if command -v codex >/dev/null 2>&1; then
        echo "Setting up Codex integration..."
        "$BIN_DIR/$BIN_NAME" integration install codex >/dev/null 2>&1 || true
    fi
    if command -v agy >/dev/null 2>&1 || [[ -d "$HOME/.gemini" ]]; then
        echo "Setting up Antigravity integration..."
        "$BIN_DIR/$BIN_NAME" integration install antigravity-cli >/dev/null 2>&1 || true
    fi
    if command -v opencode >/dev/null 2>&1 || [[ -d "$HOME/.config/opencode" ]]; then
        echo "Setting up OpenCode integration..."
        "$BIN_DIR/$BIN_NAME" integration install opencode >/dev/null 2>&1 || true
    fi

    if [[ -d "$HOME/.agents/skills" ]]; then
        echo "Registering Herdr skill in ~/.agents/skills/herdr..."
        mkdir -p "$HOME/.agents/skills/herdr"
        "$BIN_DIR/$BIN_NAME" --skill > "$HOME/.agents/skills/herdr/SKILL.md" 2>/dev/null || true
    fi
fi

echo "Done."
