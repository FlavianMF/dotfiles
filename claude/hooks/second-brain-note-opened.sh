#!/bin/bash
# PostToolUse (matcher Read|Bash|Grep): registra o uso do vault pelo agente na sessão.
#
# Só roda com SECOND_BRAIN_HOOKS=1. Dois arquivos em ${SECOND_BRAIN_STATE_DIR:-~/.local/state/second-brain}
# (0600), sem repetir linha e sem escrever no contexto:
#   <session_id>.opened  caminho relativo das notas abertas pelo tool Read. A linha de status e o ranker
#                        (vault_rank.sh) leem este arquivo: o formato e o conjunto não mudam.
#   <session_id>.used    medição do uso, uma linha "<tipo>\t<alvo>": read (nota aberta por Read ou por
#                        cat/head/tail/sed/bat/less/rg/grep com o caminho da nota no Bash) e search
#                        (sb search, rg/grep/find/fd/ag sobre o vault, tool Grep com path no vault; o alvo
#                        é o tool).
# Ignora subagentes, arquivos fora do vault, não-.md e os manifests (abrir o índice não é abrir uma
# nota). Sempre exit 0.

[[ "${SECOND_BRAIN_HOOKS:-0}" == "1" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

vault="${SECOND_BRAIN_VAULT:-$HOME/obsidian_vault}"
vault="${vault%/}"

input="$(cat)"
IFS=$'\t' read -r session tool file agent < <(
    printf '%s' "$input" | jq -r '[(.session_id // "-"), (.tool_name // "-"), ((.tool_input.file_path // .tool_input.path // "-") | gsub("[\t\n]"; " ")), (.agent_id // "-")] | @tsv' 2>/dev/null
)
# "-" marca campo ausente: com IFS de tab, campos vazios seriam fundidos e o agent_id mudaria de posição.
[[ "$agent" == "-" ]] && agent=""
[[ -n "$agent" ]] && exit 0
session="${session//[^A-Za-z0-9_-]/}"
[[ -n "$session" ]] || exit 0

state_dir="${SECOND_BRAIN_STATE_DIR:-$HOME/.local/state/second-brain}"
opened="$state_dir/$session.opened"
used="$state_dir/$session.used"

# append_once <arquivo> <linha>: cria o diretório 0700 e o arquivo 0600; não repete a linha.
append_once() {
    (umask 077; mkdir -p "$state_dir") 2>/dev/null || return 0
    grep -qxF -- "$2" "$1" 2>/dev/null && return 0
    (umask 077; printf '%s\n' "$2" >>"$1") 2>/dev/null
}

# note_rel <caminho absoluto>: imprime o caminho relativo se for nota .md do vault que não seja manifest.
note_rel() {
    local rel
    [[ "$1" == "$vault"/*.md ]] || return 1
    rel="${1#"$vault"/}"
    [[ "$rel" == *..* || "$rel" == 00_META/manifests/* ]] && return 1
    printf '%s' "$rel"
}

case "$tool" in
Read)
    rel="$(note_rel "$file")" || exit 0
    append_once "$opened" "$rel"
    append_once "$used" "read	$rel"
    ;;
Grep)
    [[ "$file" == "$vault" || "$file" == "$vault"/* ]] && append_once "$used" "search	Grep"
    ;;
Bash)
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)"
    [[ -n "$cmd" ]] || exit 0
    # Formas com que o comando cita o vault: caminho absoluto, ~/ e $HOME/ (com ou sem chaves).
    esc() { printf '%s' "$1" | sed 's/[][\.*^$+?(){}|/]/\\&/g'; }
    alts="$(esc "$vault")"
    if [[ "$vault" == "$HOME"/* ]]; then
        sub="$(esc "${vault#"$HOME"/}")"
        alts="$alts|~/$sub|\\\$HOME/$sub|\\\$\\{HOME\\}/$sub"
    fi
    if printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_])(cat|head|tail|sed|bat|less|more|nl|awk|rg|grep)([[:space:]]|$)'; then
        while IFS= read -r hit; do
            [[ -n "$hit" ]] || continue
            case "$hit" in
            "$vault"/*) abs="$hit" ;;
            "~/"*) abs="$HOME/${hit#\~/}" ;;
            "\$HOME/"*) abs="$HOME/${hit#\$HOME/}" ;;
            "\${HOME}/"*) abs="$HOME/${hit#\$\{HOME\}/}" ;;
            *) continue ;;
            esac
            rel="$(note_rel "$abs")" || continue
            append_once "$used" "read	$rel"
        done < <(printf '%s' "$cmd" | grep -oP "(?:$alts)/[^\"'\`;|&<>\n]*?\.md(?![A-Za-z0-9_])" 2>/dev/null)
    fi
    if printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_])sb(\.py)?[[:space:]]+search([[:space:]]|$)'; then
        append_once "$used" "search	sb"
    elif printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_])(rg|grep|find|fd|ag)([[:space:]]|$)' &&
        printf '%s' "$cmd" | grep -qE "($alts)([/[:space:]\"']|$)"; then
        append_once "$used" "search	shell"
    fi
    ;;
esac
exit 0
