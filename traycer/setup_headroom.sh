#!/bin/bash
# Configures Headroom proxy environment variables and provider overrides for Traycer.
# Usage: traycer/setup_headroom.sh [--dry-run]
set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

HEADROOM_URL="http://127.0.0.1:8787"
PROVIDER_OVERRIDES="${TRAYCER_PROVIDER_OVERRIDES:-$HOME/.traycer/host/config/provider-overrides.json}"

# 1. Global env overrides via Traycer CLI if available
if command -v traycer >/dev/null 2>&1; then
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[dry-run] traycer config env set --key ANTHROPIC_BASE_URL --value $HEADROOM_URL"
        echo "[dry-run] traycer config env set --key GOOGLE_GEMINI_BASE_URL --value $HEADROOM_URL"
    else
        traycer config env set --key ANTHROPIC_BASE_URL --value "$HEADROOM_URL"
        traycer config env set --key GOOGLE_GEMINI_BASE_URL --value "$HEADROOM_URL"
        echo "Configured Traycer global env overrides for Headroom ($HEADROOM_URL)"
    fi
else
    echo "NOTE: traycer CLI not found; skipping CLI config env set."
fi

# 2. Update provider-overrides.json when present
if [[ -f "$PROVIDER_OVERRIDES" ]]; then
    if command -v jq >/dev/null 2>&1; then
        if jq empty "$PROVIDER_OVERRIDES" 2>/dev/null; then
            updated_json="$(jq \
                --arg url "$HEADROOM_URL" '
                .providers = (.providers // {}) |
                .providers["claude-code"] = (.providers["claude-code"] // {}) |
                .providers["claude-code"].envOverrides = ((.providers["claude-code"].envOverrides // {}) + {"ANTHROPIC_BASE_URL": $url}) |
                .providers["antigravity"] = (.providers["antigravity"] // {}) |
                .providers["antigravity"].envOverrides = ((.providers["antigravity"].envOverrides // {}) + {"GOOGLE_GEMINI_BASE_URL": $url})
                ' "$PROVIDER_OVERRIDES")"

            if [[ $DRY_RUN -eq 1 ]]; then
                echo "[dry-run] update $PROVIDER_OVERRIDES with Headroom envOverrides"
            else
                tmp_file="$(mktemp "${PROVIDER_OVERRIDES}.tmp.XXXXXX")"
                echo "$updated_json" > "$tmp_file"
                mv "$tmp_file" "$PROVIDER_OVERRIDES"
                echo "Updated provider overrides in $PROVIDER_OVERRIDES"
            fi
        else
            echo "WARNING: $PROVIDER_OVERRIDES is not valid JSON; skipping update." >&2
        fi
    else
        echo "WARNING: jq not found; skipping update of $PROVIDER_OVERRIDES." >&2
    fi
else
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[dry-run] $PROVIDER_OVERRIDES not found; skipping"
    else
        echo "NOTE: $PROVIDER_OVERRIDES not found; skipping."
    fi
fi
