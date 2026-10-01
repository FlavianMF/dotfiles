#!/bin/bash
# Liga/desliga o plugin ECC (ecc@ecc) num projeto, sem mexer no git dele.
#
# Uso: claude/ecc-project.sh on|off|status [dir] [--no-common]
#
# on:  enabledPlugins["ecc@ecc"]=true em <dir>/.claude/settings.local.json e link
#      <dir>/.claude/rules/ecc-upstream -> vendor/ecc/upstream/rules (rules do ECC no
#      mesmo pin). Com --no-common, linka só os packs de linguagem (sem rules/common,
#      que carrega sempre e manda delegar a agents ecc:*). Os dois caminhos entram em
#      .git/info/exclude.
# off: remove a chave e o link; o resto do settings.local.json fica.
# Globalmente o plugin fica instalado e desligado (claude/settings.json).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULES_SRC="$REPO_DIR/vendor/ecc/upstream/rules"
PLUGIN="ecc@ecc"

usage() { echo "Uso: $0 on|off|status [dir] [--no-common]" >&2; exit 1; }

action="${1:-}"; shift || true
dir="."; no_common=0
for arg in "$@"; do
    case "$arg" in
        --no-common) no_common=1 ;;
        -*) usage ;;
        *) dir="$arg" ;;
    esac
done
[[ "$action" =~ ^(on|off|status)$ ]] || usage
command -v jq >/dev/null 2>&1 || { echo "jq não encontrado" >&2; exit 1; }
[[ -d "$dir" ]] || { echo "Diretório não existe: $dir" >&2; exit 1; }
dir="$(cd "$dir" && pwd)"
[[ "$dir" == "$REPO_DIR" ]] && { echo "Não ligue o ECC no próprio dotfiles (o link das rules apontaria para dentro dele)" >&2; exit 1; }

settings="$dir/.claude/settings.local.json"
rules_link="$dir/.claude/rules/ecc-upstream"

exclude_add() {
    local exclude git_dir
    git_dir="$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null)" || return 0
    exclude="$git_dir/info/exclude"
    mkdir -p "$(dirname "$exclude")"
    touch "$exclude"
    for entry in /.claude/settings.local.json /.claude/rules/ecc-upstream; do
        grep -qxF "$entry" "$exclude" || echo "$entry" >> "$exclude"
    done
}

case "$action" in
    on)
        [[ -f "$RULES_SRC/.ecc-sha" ]] || { echo "Rules ausentes; rode vendor/ecc/fetch-upstream.sh" >&2; exit 1; }
        mkdir -p "$dir/.claude/rules"
        [[ -f "$settings" ]] || echo '{}' > "$settings"
        tmp="$(mktemp)"
        jq --arg p "$PLUGIN" '.enabledPlugins[$p] = true' "$settings" > "$tmp" && mv "$tmp" "$settings"

        if [[ -e "$rules_link" && ! -L "$rules_link" ]]; then
            echo "$rules_link existe e não é link; não mexi nas rules" >&2
        else
            rm -f "$rules_link"
            if [[ $no_common -eq 1 ]]; then
                mkdir "$rules_link.tmp"
                for pack in "$RULES_SRC"/*/; do
                    [[ "$(basename "$pack")" == common ]] && continue
                    ln -s "${pack%/}" "$rules_link.tmp/$(basename "$pack")"
                done
                mv "$rules_link.tmp" "$rules_link"
            else
                ln -s "$RULES_SRC" "$rules_link"
            fi
        fi
        exclude_add
        echo "ECC ligado em $dir @ $(cut -c1-7 "$RULES_SRC/.ecc-sha")$([[ $no_common -eq 1 ]] && echo ' (sem rules/common)'). Reinicie o Claude Code nesse projeto."
        ;;
    off)
        if [[ -f "$settings" ]]; then
            tmp="$(mktemp)"
            jq --arg p "$PLUGIN" 'del(.enabledPlugins[$p]) | if .enabledPlugins == {} then del(.enabledPlugins) else . end' \
                "$settings" > "$tmp" && mv "$tmp" "$settings"
        fi
        if [[ -L "$rules_link" ]]; then
            rm -f "$rules_link"
        elif [[ -d "$rules_link" ]]; then
            # --no-common: diretório só com links para os packs
            find "$rules_link" -mindepth 1 -maxdepth 1 -type l -delete
            rmdir "$rules_link" 2>/dev/null || echo "$rules_link tem arquivos que não são links; deixei" >&2
        fi
        echo "ECC desligado em $dir. Reinicie o Claude Code nesse projeto."
        ;;
    status)
        state="desligado"
        [[ -f "$settings" ]] && [[ "$(jq -r --arg p "$PLUGIN" '.enabledPlugins[$p] // false' "$settings")" == true ]] && state="ligado"
        rules="sem rules"
        if [[ -L "$rules_link" ]]; then rules="rules completas"
        elif [[ -d "$rules_link" ]]; then rules="rules sem common"; fi
        echo "$dir: ECC $state, $rules (pin $(cut -c1-7 "$RULES_SRC/.ecc-sha" 2>/dev/null || echo '?'))"
        ;;
esac
