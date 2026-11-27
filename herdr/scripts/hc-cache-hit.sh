#!/usr/bin/env bash
# Display and attach to herdr-core (hc) / herdr-app agents with live cache-hit telemetry.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: hc-cache-hit [--watch [SECS]] [--pick] [--json] [--refresh] [--all] [--help]

Options:
  --watch [SECS]  Refresh the terminal view every SECS seconds (default: 5)
  --pick          Fuzzy-pick an agent with fzf (preview via hc read) and attach via hc attach
  --json          Print merged hc + cache-hit telemetry as JSON
  --refresh       Force a fresh scan via herdr-cache-hit watch.sh before reading
  --all           Include non-agent shell terminals in the table
  -h, --help      Show this help
EOF
}

MODE="table"
WATCH_SECS=5
FORCE_REFRESH=0
SHOW_ALL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --watch)
            MODE="watch"
            if [[ "${2:-}" =~ ^[0-9]+$ ]]; then
                WATCH_SECS="$2"
                shift
            fi
            ;;
        --pick) MODE="pick" ;;
        --json) MODE="json" ;;
        --refresh) FORCE_REFRESH=1 ;;
        --all) SHOW_ALL=1 ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "hc-cache-hit: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

command -v hc >/dev/null 2>&1 || { echo "hc-cache-hit: hc not found in PATH" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "hc-cache-hit: jq not found in PATH" >&2; exit 1; }

find_plugin_root() {
    local d root
    for d in /mnt/c/Users/*/.config/herdr-app/mods/cache-hit/plugin-root; do
        if [[ -f "$d" ]]; then
            root=$(tr -d '\r\n' < "$d")
            [[ -d "$root" ]] && { printf '%s\n' "$root"; return 0; }
        fi
    done
    if [[ -d "$HOME/.local/share/herdr-cache-hit" ]]; then
        printf '%s\n' "$HOME/.local/share/herdr-cache-hit"
        return 0
    fi
    for d in "$HOME"/.config/herdr/plugins/github-installations/cache-hit-*/*/checkout; do
        [[ -d "$d" ]] && { printf '%s\n' "$d"; return 0; }
    done
    return 1
}

find_win_home() {
    local d
    if [[ -n "${HERDR_APP_HOME:-}" ]]; then
        # e.g. /mnt/c/Users/User/.config/herdr-app -> /mnt/c/Users/User
        printf '%s\n' "${HERDR_APP_HOME%/.config/herdr-app}"
        return 0
    fi
    for d in /mnt/c/Users/*/.local/state/herdr/plugins/cache-hit-app/app-metadata; do
        if [[ -d "$d" ]]; then
            printf '%s\n' "${d%/.local/state/herdr/plugins/cache-hit-app/app-metadata}"
            return 0
        fi
    done
    printf '%s\n' "$HOME"
}

PLUGIN_ROOT="$(find_plugin_root || true)"
WIN_HOME="$(find_win_home)"
STATE_DIR="$WIN_HOME/.local/state/herdr/plugins/cache-hit-app"
CONFIG_DIR="$WIN_HOME/.config/herdr/plugins/config/cache-hit-app"
META_DIR="$STATE_DIR/app-metadata"

is_meta_stale() {
    local now newest=0 mtime f
    now=$(date +%s)
    [[ -d "$META_DIR" ]] || return 0
    for f in "$META_DIR"/*.json; do
        [[ -f "$f" ]] || continue
        mtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)
        (( mtime > newest )) && newest=$mtime
    done
    (( now - newest >= 15 ))
}

run_scan() {
    [[ -n "$PLUGIN_ROOT" && -f "$PLUGIN_ROOT/watch.sh" && -x "$PLUGIN_ROOT/scripts/herdr-app-shim.sh" ]] || return 0
    HERDR_BIN_PATH="$PLUGIN_ROOT/scripts/herdr-app-shim.sh" \
        HERDR_NO_TIMER=1 \
        HERDR_CACHE_DISPLAY_ONLY=1 \
        HERDR_PLUGIN_STATE_DIR="$STATE_DIR" \
        HERDR_PLUGIN_CONFIG_DIR="$CONFIG_DIR" \
        bash "$PLUGIN_ROOT/watch.sh" >/dev/null 2>&1 || true
}

collect_json() {
    local hc_json now_s now_ms meta_json="[]"
    local -a files=()
    hc_json=$(hc ls --json 2>/dev/null || echo '{"terminals":[]}')
    now_s=$(date +%s)
    now_ms=$((now_s * 1000))

    if [[ -d "$META_DIR" ]]; then
        shopt -s nullglob
        files=("$META_DIR"/*.json)
        shopt -u nullglob
        if (( ${#files[@]} > 0 )); then
            meta_json=$(jq -s 'map({key: .pane, value: .}) | from_entries' "${files[@]}" 2>/dev/null || echo '{}')
        else
            meta_json='{}'
        fi
    else
        meta_json='{}'
    fi

    jq -c --argjson now_s "$now_s" --argjson now_ms "$now_ms" --argjson meta "$meta_json" --argjson show_all "$SHOW_ALL" '
      def fmt_left($secs):
        if $secs <= 0 then "expired"
        elif $secs < 60 then "<1m"
        else "\(($secs / 60) | floor)m"
        end;
      [
        .terminals[]
        | select(.state == "live")
        | select($show_all == 1 or ((.agent // "") != "zsh" and (.agent // "") != "bash" and (.agent // "") != "sh"))
        | .address as $id
        | ($meta[$id] // null) as $m
        | (if ($m != null and ($m.expires_ms // 0) > $now_ms) then ($m.tokens // {}) else {} end) as $tok
        | ($tok.cache_deadline // "" | tonumber? // 0) as $dl
        | (if $dl > 0 then ($dl - $now_s) else ($tok.cache_remaining_secs // "" | tonumber? // 0) end) as $left
        | ($tok.cache_state // "unknown") as $raw_state
        | (if $raw_state == "unknown" or $raw_state == "" then "unknown"
           elif $left <= 0 then "cold"
           elif $left < 300 then "expiring"
           else "hot" end) as $state
        | {
            address: $id,
            where: (.where // .cwd // "-"),
            agent: (.agent // "-"),
            agent_status: (.status // .state // "-"),
            cache_state: $state,
            left_secs: (if $state == "hot" or $state == "expiring" then ($left | floor) else null end),
            left_human: (if $state == "unknown" then "-" elif $state == "cold" then "expired" else fmt_left($left) end),
            cache_pct: ($tok.cache_pct_num // "-"),
            cache_tokens: ($tok.cache_tokens // $tok.cache_details // "-"),
            cache_summary: ($tok.cache // "-")
          }
      ]
      | sort_by(
          if .cache_state == "expiring" then 0
          elif .cache_state == "hot" then 1
          elif .cache_state == "cold" then 2
          else 3 end,
          (.left_secs // 999999999),
          .address
        )
    ' <<< "$hc_json"
}

render_table() {
    local data=$1
    if [[ "$(jq 'length' <<< "$data")" -eq 0 ]]; then
        echo "No live herdr-core agents found."
        return 0
    fi
    {
        printf 'ID\tWHERE\tAGENT\tSTATUS\tCACHE\tLEFT\tHIT%%\tTOKENS\n'
        jq -r '.[] | [.address, .where, .agent, .agent_status, .cache_state, .left_human, (if .cache_pct == "-" then "-" else "\(.cache_pct)%" end), .cache_tokens] | @tsv' <<< "$data"
    } | column -t -s $'\t'
}

if (( FORCE_REFRESH )) || is_meta_stale; then
    run_scan
fi

case "$MODE" in
    json)
        collect_json | jq .
        ;;
    table)
        render_table "$(collect_json)"
        ;;
    watch)
        while true; do
            is_meta_stale && run_scan
            printf '\033[H\033[2J'
            printf 'hc-cache-hit (%s) — Ctrl+C to quit\n\n' "$(date +%H:%M:%S)"
            render_table "$(collect_json)"
            sleep "$WATCH_SECS"
        done
        ;;
    pick)
        command -v fzf >/dev/null 2>&1 || { echo "hc-cache-hit: fzf not found in PATH" >&2; exit 1; }
        entries=$(collect_json | jq -r '.[] | [.address, .where, .agent, .cache_state, .left_human, (if .cache_pct == "-" then "-" else "\(.cache_pct)%" end), .cache_tokens] | @tsv')
        if [[ -z "$entries" ]]; then
            echo "No live herdr-core agents found."
            exit 0
        fi
        selected=$(
            printf '%s\n' "$entries" | fzf \
                --delimiter=$'\t' \
                --with-nth=1,2,3,4,5,6,7 \
                --header='Enter: hc attach (ctrl+\ to detach) | Esc: close' \
                --preview='hc read --lines 60 {1}' \
                --preview-window='right:55%:wrap'
        ) || exit 0
        target=$(cut -f1 <<< "$selected")
        exec hc attach "$target"
        ;;
esac
