#!/bin/bash
# Claude Code statusline, duas linhas (o indicador de modo aparece logo abaixo da última):
#   1. modelo | cwd | branch + estado git | % de contexto restante | badge caveman
#   2. ECC ligado (local) · SB 3 notas · 1 aberta
# Lê o JSON de status do stdin (https://code.claude.com/docs/en/statusline).
# Nunca falha: qualquer campo ausente vira segmento vazio. NO_COLOR desliga as cores; com
# COLUMNS < 40 a linha 2 usa a forma curta (ECC+ · SB3).
#
# Linha 2 (sem fork no caso comum): o estado do ECC é o snapshot gravado no SessionStart
# (claude/hooks/ecc-session-start.sh); se o disco mudou depois, mostra `*` e "reinicie". "SB n
# notas" = notas injetadas no contexto (<sid>.injected); "n aberta" = abertas pelo agente
# (<sid>.opened, hook second-brain-note-opened.sh).

input="$(cat)"

IFS=$'\x1f' read -r model cwd remaining sid < <(
    printf '%s' "$input" | jq -r '[(.model.display_name // .model.id // "?"), (.workspace.current_dir // .cwd // ""), (.context_window.remaining_percentage // ""), (.session_id // "")] | map(tostring) | join("\u001f")' 2>/dev/null
)
[[ -z "$model" ]] && model="?"
[[ -z "$cwd" ]] && cwd="$PWD"
sid="${sid//[^A-Za-z0-9_-]/}"

C_RESET=$'\033[0m'
C_DIM=$'\033[2m'
C_CYAN=$'\033[36m'
C_BLUE=$'\033[34m'
C_YELLOW=$'\033[33m'
C_GREEN=$'\033[32m'
C_RED=$'\033[31m'

if [[ -n "${NO_COLOR:-}" ]]; then
    C_RESET=""; C_DIM=""; C_CYAN=""; C_BLUE=""; C_YELLOW=""; C_GREEN=""; C_RED=""
fi

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

# --- Linha 2: ECC e second brain ---------------------------------------------------------
sb_dir="${SECOND_BRAIN_STATE_DIR:-$HOME/.local/state/second-brain}"
sess_dir="${CLAUDE_SESSION_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-session}"
narrow=0; [[ "${COLUMNS:-}" =~ ^[0-9]+$ && "$COLUMNS" -lt 40 ]] && narrow=1

ecc_state=""; ecc_scope=""; sb_flag=""; root=""
if [[ -n "$sid" && -r "$sess_dir/$sid.ecc" ]]; then
    mapfile -t snap <"$sess_dir/$sid.ecc"
    ecc_state="${snap[0]:-}"; ecc_scope="${snap[1]:-}"; sb_flag="${snap[2]:-}"; root="${snap[3]:-}"
fi

# Estado do ECC no disco (cache por mtime dos settings; um fork só quando algo mudou).
stale=""
if [[ -n "$ecc_state" && -n "$root" ]]; then
    disk_cache="$sess_dir/$sid.ecc-disk"
    user_settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
    if [[ -r "$disk_cache" && ! "$root/.claude/settings.local.json" -nt "$disk_cache" \
        && ! "$root/.claude/settings.json" -nt "$disk_cache" && ! "$user_settings" -nt "$disk_cache" ]]; then
        read -r disk_state <"$disk_cache"
    else
        disk_line="$(timeout 2 bash "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/ecc-project.sh" status "$root" --short 2>/dev/null)"
        disk_state="${disk_line#ECC }"; disk_state="${disk_state%% *}"
        [[ -n "$disk_state" ]] && (umask 077; printf '%s\n' "$disk_state" >"$disk_cache") 2>/dev/null
    fi
    [[ -n "$disk_state" && "$disk_state" != "$ecc_state" ]] && stale="*"
fi

case "$ecc_state" in
    ligado)
        if [[ $narrow -eq 1 ]]; then ecc_seg="${C_GREEN}ECC+${stale}${C_RESET}"
        else ecc_seg="${C_GREEN}ECC ligado${ecc_scope:+ ($ecc_scope)}${C_RESET}"; fi ;;
    desligado)
        if [[ $narrow -eq 1 ]]; then ecc_seg="${C_DIM}ECC-${C_RESET}"
        else ecc_seg="${C_DIM}ECC desligado${C_RESET}"; fi ;;
    *) ecc_seg="${C_DIM}ECC ?${C_RESET}" ;;
esac
if [[ -n "$stale" ]]; then
    if [[ $narrow -eq 1 ]]; then ecc_seg="${ecc_seg%${C_RESET}}${C_YELLOW}*${C_RESET}"
    else ecc_seg="${ecc_seg%${C_RESET}}${C_YELLOW}*${C_RESET} ${C_YELLOW}reinicie${C_RESET}"; fi
fi

injected=0; opened=0
if [[ -n "$sid" ]]; then
    if [[ -r "$sb_dir/$sid.injected" ]]; then mapfile -t _i <"$sb_dir/$sid.injected"; injected=${#_i[@]}; fi
    if [[ -r "$sb_dir/$sid.opened" ]]; then mapfile -t _o <"$sb_dir/$sid.opened"; opened=${#_o[@]}; fi
fi
if [[ "$sb_flag" == off ]]; then
    if [[ $narrow -eq 1 ]]; then sb_seg="${C_DIM}SB-${C_RESET}"; else sb_seg="${C_DIM}SB off${C_RESET}"; fi
elif [[ -z "$sb_flag" && $injected -eq 0 && $opened -eq 0 ]]; then
    if [[ $narrow -eq 1 ]]; then sb_seg="${C_DIM}SB-${C_RESET}"; else sb_seg="${C_DIM}SB —${C_RESET}"; fi
elif [[ $narrow -eq 1 ]]; then
    sb_seg="${C_CYAN}SB${injected}${C_RESET}"
else
    noun="notas"; [[ $injected -eq 1 ]] && noun="nota"
    sb_seg="${C_CYAN}SB ${injected} ${noun}${C_RESET}"
    if [[ $opened -gt 0 ]]; then
        open_noun="abertas"; [[ $opened -eq 1 ]] && open_noun="aberta"
        sb_seg+=" ${C_DIM}·${C_RESET} ${C_CYAN}${opened} ${open_noun}${C_RESET}"
    fi
fi

printf '%s\n' "${C_CYAN}${model}${C_RESET} ${C_DIM}|${C_RESET} ${short_cwd}${git_seg}${ctx_seg}${caveman_seg}"
printf '%s\n' "${ecc_seg} ${C_DIM}·${C_RESET} ${sb_seg}"
