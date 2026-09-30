#!/bin/bash
# Claude Code statusline: modelo | cwd | branch + estado git | % de contexto restante | badge caveman
# Lê o JSON de status do stdin (https://code.claude.com/docs/en/statusline).
# Nunca falha: qualquer campo ausente vira segmento vazio.

input="$(cat)"

jqr() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

model="$(jqr '.model.display_name // .model.id // "?"')"
[[ -z "$model" ]] && model="?"
cwd="$(jqr '.workspace.current_dir // .cwd // empty')"
[[ -z "$cwd" ]] && cwd="$PWD"
remaining="$(jqr '.context_window.remaining_percentage // empty')"

C_RESET=$'\033[0m'
C_DIM=$'\033[2m'
C_CYAN=$'\033[36m'
C_BLUE=$'\033[34m'
C_YELLOW=$'\033[33m'
C_GREEN=$'\033[32m'
C_RED=$'\033[31m'

short_cwd="${cwd/#$HOME/\~}"

git_seg=""
if branch="$(git -C "$cwd" symbolic-ref --short -q HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)" && [[ -n "$branch" ]]; then
    dirty=""
    if [[ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null | head -1)" ]]; then
        dirty="${C_YELLOW}*${C_RESET}"
    fi
    git_seg=" ${C_DIM}|${C_RESET} ${C_BLUE}${branch}${C_RESET}${dirty}"
fi

ctx_seg=""
if [[ -n "$remaining" && "$remaining" != "null" ]]; then
    pct="${remaining%%.*}"
    color="$C_GREEN"
    if [[ "$pct" =~ ^[0-9]+$ ]]; then
        (( pct <= 40 )) && color="$C_YELLOW"
        (( pct <= 20 )) && color="$C_RED"
    fi
    ctx_seg=" ${C_DIM}|${C_RESET} ${color}ctx ${pct}%${C_RESET}"
fi

# Badge do caveman: o diretório de cache muda de hash a cada versão do plugin,
# então localiza o script dinamicamente e usa o mais recente.
caveman_seg=""
# shellcheck disable=SC2012 # plugin cache paths are hash/version names, no odd chars
caveman_script="$(ls -t "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/caveman/*/*/src/hooks/caveman-statusline.sh 2>/dev/null | head -1)"
if [[ -n "$caveman_script" && -f "$caveman_script" ]]; then
    badge="$(bash "$caveman_script" 2>/dev/null </dev/null)"
    [[ -n "$badge" ]] && caveman_seg=" $badge"
fi

printf '%s\n' "${C_CYAN}${model}${C_RESET} ${C_DIM}|${C_RESET} ${short_cwd}${git_seg}${ctx_seg}${caveman_seg}"
