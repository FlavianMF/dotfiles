#!/usr/bin/env bash
# Hook post-save-layout do tmux-resurrect: troca o comando salvo de cada pane
# com `claude` interativo por `claude --resume <sessionId>`.
# Uso: claude-resume-save.sh <arquivo_de_save>
set -euo pipefail

file=${1:?arquivo de save ausente}
sessions_dir="$HOME/.claude/sessions"
[ -f "$file" ] && [ -d "$sessions_dir" ] || exit 0

# pid do `claude` interativo entre os descendentes de $1 (vazio se nao houver)
find_session_id() {
    local queue=("$1") pid f kind
    while [ ${#queue[@]} -gt 0 ]; do
        pid=${queue[0]}
        queue=("${queue[@]:1}")
        f="$sessions_dir/$pid.json"
        if [ -r "$f" ]; then
            kind=$(jq -r '.kind // ""' "$f" 2>/dev/null || true)
            if [ "$kind" != "bg" ]; then
                jq -r '.sessionId // empty' "$f" 2>/dev/null || true
                return 0
            fi
        fi
        mapfile -t -O "${#queue[@]}" queue < <(pgrep -P "$pid" 2>/dev/null || true)
    done
}

declare -A resume
while IFS=$'\t' read -r session window pane pid; do
    id=$(find_session_id "$pid")
    [ -n "$id" ] && resume["$session	$window	$pane"]=$id
done < <(tmux list-panes -a -F $'#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_pid}')

[ ${#resume[@]} -gt 0 ] || exit 0

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
while IFS= read -r line; do
    IFS=$'\t' read -ra f <<<"$line"
    if [ "${f[0]}" = "pane" ] && [ "${#f[@]}" -ge 11 ] && [ "${f[9]}" = "claude" ]; then
        id=${resume["${f[1]}	${f[2]}	${f[5]}"]:-}
        [ -n "$id" ] && f[10]=":claude --resume $id"
        line=$(IFS=$'\t'; echo "${f[*]}")
    fi
    printf '%s\n' "$line"
done <"$file" >"$tmp"
cat "$tmp" >"$file"
