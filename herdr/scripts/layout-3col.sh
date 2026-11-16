#!/usr/bin/env bash
# Layout de 3 colunas para o Herdr: lateral (25%) | centro largo (50%) | lateral (25%)
# Equivalente ao ~/.tmux/scripts/layout-3col.sh
# Uso: layout-3col.sh new|apply [side_percent]
set -euo pipefail

mode="${1:-new}"
side="${2:-25}"

if (( side < 10 || side > 45 )); then
    echo "layout-3col: side deve ser entre 10 e 45 (padrão 25)" >&2
    exit 1
fi

# Localiza o pane enfocado ou o atual
get_focused_pane() {
    local pane
    pane=$(herdr pane layout 2>/dev/null | jq -r '.result.layout.focused_pane_id // empty' 2>/dev/null || true)
    if [[ -z "$pane" ]]; then
        pane="${HERDR_PANE_ID:-}"
    fi
    if [[ -z "$pane" ]]; then
        pane=$(herdr pane current 2>/dev/null | jq -r '.result.pane.pane_id // empty' 2>/dev/null || true)
    fi
    printf '%s' "$pane"
}

case "$mode" in
new)
    target_pane="$(get_focused_pane)"
    pane_arg=()
    if [[ -n "$target_pane" ]]; then
        pane_arg=("$target_pane")
    else
        pane_arg=(--current)
    fi

    # 1. Primeiro split vertical à direita
    # ratio1 = (100 - side) / 100
    ratio1=$(awk "BEGIN { printf \"%.4f\", (100 - $side) / 100 }")
    res1=$(herdr pane split "${pane_arg[@]}" --direction right --ratio "$ratio1" 2>/dev/null || true)
    right_pane=$(jq -r '.result.pane.pane_id // .result.pane_id // empty' <<< "$res1" 2>/dev/null || true)

    # 2. Divide a seção direita para separar centro e lateral direita
    # ratio2 = side / (100 - side)
    ratio2=$(awk "BEGIN { printf \"%.4f\", $side / (100 - $side) }")
    if [[ -n "$right_pane" ]]; then
        herdr pane split "$right_pane" --direction right --ratio "$ratio2" >/dev/null 2>&1 || true
        # Foca no pane central
        herdr pane focus --pane "$right_pane" >/dev/null 2>&1 || true
    else
        herdr pane split --current --direction right --ratio "$ratio2" >/dev/null 2>&1 || true
        herdr pane focus --direction left --current >/dev/null 2>&1 || true
    fi
    ;;
apply)
    # Rebalanceia se a aba atual possuir exatamente 3 panes
    layout_json=$(herdr pane layout 2>/dev/null || true)
    pane_count=$(jq -r '.result.layout.panes | length // 0' <<< "$layout_json" 2>/dev/null || echo 0)

    if (( pane_count != 3 )); then
        herdr notification send "layout-3col" "A aba precisa ter exatamente 3 panes para aplicar (tem $pane_count)" --level warning >/dev/null 2>&1 || true
        echo "layout-3col: a aba precisa ter exatamente 3 panes (tem $pane_count)" >&2
        exit 0
    fi

    # Identifica os 3 panes ordenados horizontalmente (x crescente)
    mapfile -t ordered_panes < <(jq -r '.result.layout.panes | sort_by(.rect.x) | .[].pane_id' <<< "$layout_json")
    total_width=$(jq -r '.result.layout.area.width // 0' <<< "$layout_json")

    if (( total_width > 0 )); then
        target_side_cols=$(( total_width * side / 100 ))
        left_width=$(jq -r --arg id "${ordered_panes[0]}" '.result.layout.panes[] | select(.pane_id == $id) | .rect.width' <<< "$layout_json")
        right_width=$(jq -r --arg id "${ordered_panes[2]}" '.result.layout.panes[] | select(.pane_id == $id) | .rect.width' <<< "$layout_json")

        diff_left=$(( target_side_cols - left_width ))
        if (( diff_left > 0 )); then
            herdr pane resize --pane "${ordered_panes[0]}" --direction right --amount "$diff_left" >/dev/null 2>&1 || true
        elif (( diff_left < 0 )); then
            herdr pane resize --pane "${ordered_panes[0]}" --direction left --amount "$((-diff_left))" >/dev/null 2>&1 || true
        fi

        diff_right=$(( target_side_cols - right_width ))
        if (( diff_right > 0 )); then
            herdr pane resize --pane "${ordered_panes[2]}" --direction left --amount "$diff_right" >/dev/null 2>&1 || true
        elif (( diff_right < 0 )); then
            herdr pane resize --pane "${ordered_panes[2]}" --direction right --amount "$((-diff_right))" >/dev/null 2>&1 || true
        fi
    fi
    ;;
*)
    echo "uso: $0 new|apply [side_percent]" >&2
    exit 1
    ;;
esac
