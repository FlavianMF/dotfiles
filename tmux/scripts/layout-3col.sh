#!/usr/bin/env bash
# Layout de 3 colunas: lateral | centro largo | lateral.
# Uso: layout-3col.sh new|apply <pane_id>
set -euo pipefail

mode="${1:-}"
pane="${2:-}"
if [[ ! "$mode" =~ ^(new|apply)$ || -z "$pane" ]]; then
    echo "uso: $0 new|apply <pane_id>" >&2
    exit 1
fi

# Largura das laterais em % (opção @layout3_side, padrão 25)
side=$(tmux show -gqv @layout3_side)
side="${side:-25}"
if [[ ! "$side" =~ ^[0-9]+$ ]] || ((side < 10 || side > 45)); then
    tmux display-message "layout-3col: @layout3_side inválido ('$side'), use inteiro de 10 a 45"
    exit 1
fi

case "$mode" in
new)
    dir=$(tmux display-message -p -t "$pane" '#{pane_current_path}')
    # Divide: [P | R], depois R em [centro | direita]
    right=$(tmux split-window -h -t "$pane" -l "$((100 - side))%" -c "$dir" -P -F '#{pane_id}')
    tmux split-window -h -t "$right" -l "$((side * 100 / (100 - side)))%" -c "$dir"
    tmux select-pane -t "$right"
    ;;
apply)
    mapfile -t panes < <(tmux list-panes -t "$pane" -F '#{pane_id}')
    if ((${#panes[@]} != 3)); then
        tmux display-message "layout-3col: a janela precisa ter exatamente 3 panes (tem ${#panes[@]})"
        exit 0
    fi
    # Largura em colunas a partir da janela (descontando 2 bordas)
    width=$(tmux display-message -p -t "$pane" '#{window_width}')
    cols=$(((width - 2) * side / 100))
    tmux select-layout -t "$pane" even-horizontal
    tmux resize-pane -t "${panes[0]}" -x "$cols"
    tmux resize-pane -t "${panes[2]}" -x "$cols"
    ;;
esac
