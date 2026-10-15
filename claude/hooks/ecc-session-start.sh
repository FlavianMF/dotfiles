#!/bin/bash
# SessionStart: estado do ECC no projeto (para o modelo e para a linha de status).
#
# 1. Imprime no contexto `ECC ligado|desligado (escopo).` (~20 tokens) e, se o ECC está desligado
#    num projeto web/C/Node (claude/ecc-detect.sh) sem .claude/ecc.off, uma linha pedindo que o
#    agente sugira `make ecc-on`. Independe do second brain.
# 2. Grava o snapshot da sessão em ${CLAUDE_SESSION_STATE_DIR:-~/.local/state/claude-session}/<sid>.ecc
#    (0600; linhas: estado, escopo, second brain on|off, raiz do projeto). A linha de status compara
#    o snapshot com o disco para avisar quando o estado mudou depois da abertura. O snapshot só é
#    regravado em startup/resume (quando o Claude Code relê os plugins); compact/clear não recarregam.
#
# ECC_STATUS_HOOK=0 desliga. Sempre exit 0; nunca bloqueia.

[[ "${ECC_STATUS_HOOK:-1}" != 0 ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
IFS=$'\x1f' read -r cwd session source_kind < <(
    printf '%s' "$input" | jq -r '[(.cwd // ""), (.session_id // ""), (.source // "")] | join("\u001f")' 2>/dev/null
)
[[ -d "$cwd" ]] || cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
session="${session//[^A-Za-z0-9_-]/}"

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
ecc_script="$here/../ecc-project.sh"
root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")"

line="$(timeout 2 bash "$ecc_script" status "$root" --short 2>/dev/null)"   # "ECC ligado (local)."
[[ -n "$line" ]] || exit 0
printf '%s Só o usuário muda (make ecc-on|ecc-off DIR=...).\n' "$line"

state="${line#ECC }"; state="${state%% *}"
scope="${line#*(}"; scope="${scope%%)*}"

# Snapshot da sessão para a linha de status.
if [[ -n "$session" ]]; then
    dir="${CLAUDE_SESSION_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-session}"
    snap="$dir/$session.ecc"
    if (umask 077; mkdir -p "$dir") 2>/dev/null && { [[ ! -f "$snap" ]] || [[ "$source_kind" == startup || "$source_kind" == resume ]]; }; then
        sb=off; [[ "${SECOND_BRAIN_HOOKS:-0}" == 1 ]] && sb=on
        (umask 077; printf '%s\n%s\n%s\n%s\n' "$state" "$scope" "$sb" "$root" >"$snap") 2>/dev/null
    fi
    find "$dir" -maxdepth 1 -type f -mtime +7 -delete 2>/dev/null
fi

# Desligado num projeto web/C/Node: o wrapper `claude` do zsh liga antes de abrir; sessões abertas
# fora dele (IDE) recebem a sugestão. Respeita .claude/ecc.off e ignora o repo de dotfiles.
if [[ "$state" == desligado ]]; then
    dotfiles="$(cd "$here/../.." 2>/dev/null && pwd -P)"
    if [[ ! -e "$root/.claude/ecc.off" && "$(cd "$root" 2>/dev/null && pwd -P)" != "$dotfiles" ]]; then
        read -r kind _ <<<"$(timeout 2 bash "$here/../ecc-detect.sh" "$root" 2>/dev/null)"
        case "$kind" in
            web|c|node)
                printf 'O projeto parece %s e o ECC está desligado. Se a tarefa se beneficiar, sugira ao usuário: make ecc-on DIR=%q (vale na próxima sessão).\n' \
                    "$([[ "$kind" == node ]] && echo 'backend Node' || echo "$kind")" "$root"
                ;;
        esac
    fi
fi
exit 0
