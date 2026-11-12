#!/bin/bash
# agy PostToolUse (todas as ferramentas): registra o uso do vault pelo agente na sessão.
#
# Equivalente agy de claude/hooks/second-brain-note-opened.sh, com o mesmo formato de saída em
# ${SECOND_BRAIN_STATE_DIR:-~/.local/state/second-brain} (0600), sem repetir linha:
#   <conversationId>.opened  caminho relativo das notas abertas por view_file.
#   <conversationId>.used    uma linha "<tipo>\t<alvo>": read (view_file, ou cat/head/tail/sed/bat/
#                            less/rg/grep com o caminho da nota no run_command) e search (sb search,
#                            ou rg/grep/find/fd/ag sobre o vault).
# Ignora arquivos fora do vault, não-.md e os manifests. Liga por padrão; SECOND_BRAIN_HOOKS=0
# desliga. Responde `{}` e sempre exit 0.

done_() { echo '{}'; exit 0; }

[[ "${SECOND_BRAIN_HOOKS:-1}" == "0" ]] && done_
command -v jq >/dev/null 2>&1 || done_

vault="${SECOND_BRAIN_VAULT:-$HOME/obsidian_vault}"
vault="${vault%/}"

input="$(cat)"
IFS=$'\t' read -r session tool file < <(
    printf '%s' "$input" | jq -r '[(.conversationId // "-"), (.toolCall.name // "-"), ((.toolCall.args.AbsolutePath // .toolCall.args.absolute_path // "-") | gsub("[\t\n]"; " "))] | @tsv' 2>/dev/null
)
session="${session//[^A-Za-z0-9_-]/}"
[[ -n "$session" ]] || done_

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
view_file)
    rel="$(note_rel "$file")" || done_
    append_once "$opened" "$rel"
    append_once "$used" "read	$rel"
    ;;
run_command)
    cmd="$(printf '%s' "$input" | jq -r '.toolCall.args.CommandLine // ""' 2>/dev/null)"
    [[ -n "$cmd" ]] || done_
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
done_
