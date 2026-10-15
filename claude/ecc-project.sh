#!/bin/bash
# Liga/desliga o plugin ECC (ecc@ecc) num projeto, sem mexer no git dele.
#
# Uso: claude/ecc-project.sh on|off|status|auto [dir] [--no-common] [--packs a,b] [--no-rules] [--short]
#
# on:  enabledPlugins["ecc@ecc"]=true em <dir>/.claude/settings.local.json e link
#      <dir>/.claude/rules/ecc-upstream -> vendor/ecc/upstream/rules (rules do ECC no
#      mesmo pin). --no-common linka só os packs de linguagem (sem rules/common, que carrega
#      sempre e manda delegar a agents ecc:*); --packs a,b linka só esses packs; --no-rules não
#      linka rules (só o plugin). Os caminhos entram no info/exclude do diretório git comum.
#      Remove o marcador .claude/ecc.off.
# off: remove a chave e o link e cria o marcador .claude/ecc.off (o `auto` respeita); o resto
#      do settings.local.json fica.
# status: estado efetivo (local > projeto > usuário); --short imprime uma linha para o SessionStart.
# auto: liga o ECC só se o projeto for web, C ou backend Node (claude/ecc-detect.sh) e o usuário
#      não decidiu antes. Age na raiz do repositório git. Silencioso e sem efeito se: houver
#      .claude/ecc.off, a chave ecc@ecc já existir em settings.local.json ou settings.json do
#      projeto (true ou false), o tipo não estiver em `kinds=` de claude/ecc-auto.conf, o caminho
#      casar com `exclude=` (ou não casar com `include=`, se houver), ou o projeto for este repo.
#      Web liga os packs detectados; C e Node ligam só o plugin (sem rules do ECC).
# Globalmente o plugin fica instalado e desligado (claude/settings.json). Nunca usa o CLI de
# plugin (ele reescreve o settings.json symlinkado): escreve direto no settings.local.json.
set -euo pipefail
# Um GIT_DIR herdado (hook de git) faria o git agir no repo errado.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULES_SRC="$REPO_DIR/vendor/ecc/upstream/rules"
DETECT="$REPO_DIR/claude/ecc-detect.sh"
AUTO_CONF="${ECC_AUTO_CONF:-$REPO_DIR/claude/ecc-auto.conf}"
PLUGIN="ecc@ecc"
USER_SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

usage() { echo "Uso: $0 on|off|status|auto [dir] [--no-common] [--packs a,b] [--no-rules] [--short]" >&2; exit 1; }

action="${1:-}"; shift || true
dir="."; no_common=0; short=0; no_rules=0; packs=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-common) no_common=1 ;;
        --no-rules) no_rules=1 ;;
        --short) short=1 ;;
        --packs) shift; [[ $# -gt 0 ]] || usage; packs="$1" ;;
        -*) usage ;;
        *) dir="$1" ;;
    esac
    shift
done
[[ "$action" =~ ^(on|off|status|auto)$ ]] || usage
command -v jq >/dev/null 2>&1 || { echo "jq não encontrado" >&2; exit 1; }
[[ -d "$dir" ]] || { [[ "$action" == auto ]] && exit 0; echo "Diretório não existe: $dir" >&2; exit 1; }
dir="$(cd "$dir" && pwd)"

logical_dir="$dir"
if [[ "$action" == auto ]]; then
    # Raiz do repositório git: é de lá que o Claude Code lê .claude/ (verificado também em subpastas).
    # Fora de um work tree (sem git, dentro de .git) o auto não age: não há projeto a configurar.
    top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || exit 0
    dir="$(cd "$top" && pwd)"
    [[ ! -e "$dir/.claude" || -d "$dir/.claude" ]] || exit 0
fi
if [[ "$action" == status ]]; then
    # O Claude Code lê .claude/ da raiz do git: numa subpasta, o estado é o da raiz.
    if top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"; then dir="$(cd "$top" && pwd)"; fi
elif [[ "$dir" == "$REPO_DIR" ]]; then
    [[ "$action" == auto ]] && exit 0
    echo "Não ligue o ECC no próprio dotfiles (o link das rules apontaria para dentro dele)" >&2; exit 1
fi

settings="$dir/.claude/settings.local.json"
rules_link="$dir/.claude/rules/ecc-upstream"
off_marker="$dir/.claude/ecc.off"

exclude_add() {
    local exclude git_dir
    # Diretório comum: num worktree, --absolute-git-dir seria .git/worktrees/<w>, que o git não lê para o exclude.
    git_dir="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 0
    exclude="$git_dir/info/exclude"
    mkdir -p "$(dirname "$exclude")"
    touch "$exclude"
    # Sem \n final, o primeiro `>>` colaria a entrada na última linha do usuário.
    [[ -s "$exclude" && -n "$(tail -c1 "$exclude")" ]] && echo >> "$exclude"
    for entry in /.claude/settings.local.json /.claude/rules/ecc-upstream /.claude/ecc.off; do
        grep -qxF "$entry" "$exclude" || echo "$entry" >> "$exclude"
    done
}

# Valor de enabledPlugins["ecc@ecc"] num arquivo: true, false ou vazio (ausente/arquivo inválido).
plugin_value() {
    [[ -f "$1" ]] || return 0
    jq -r --arg p "$PLUGIN" '.enabledPlugins[$p] | if . == null then empty else tostring end' "$1" 2>/dev/null || true
}

# settings.local.json ausente ou vazio vale `{}`; qualquer outra coisa precisa ser um objeto JSON.
valid_settings() {
    [[ ! -s "$settings" ]] || jq -e 'type == "object"' "$settings" >/dev/null 2>&1
}

# write_settings <filtro jq> [args do jq]: reescreve o settings.local.json preservando symlink e modo.
write_settings() {
    local current="{}" new
    [[ -s "$settings" ]] && current="$(cat "$settings")"
    new="$(printf '%s' "$current" | jq "${@:2}" "$1")" || { echo "settings.local.json com formato inesperado: $settings" >&2; exit 1; }
    mkdir -p "$dir/.claude"
    printf '%s\n' "$new" > "$settings"
}

link_rules() { # link_rules <nomes dos packs...>  (vazio = nenhum)
    if [[ -e "$rules_link" && ! -L "$rules_link" && ! -d "$rules_link" ]]; then
        echo "$rules_link existe e não é link; não mexi nas rules" >&2; return
    fi
    # Valida antes de mexer em qualquer coisa: nome vazio, com ../ ou inexistente é ignorado.
    local valid=() pack
    for pack in "$@"; do
        [[ -n "$pack" ]] || continue
        if [[ "$pack" =~ ^[A-Za-z0-9_-]+$ && -d "$RULES_SRC/$pack" ]]; then valid+=("$pack")
        else echo "pack ECC inválido ou desconhecido, ignorado: $pack" >&2; fi
    done
    remove_rules_link
    [[ ${#valid[@]} -gt 0 ]] || return 0
    mkdir -p "$dir/.claude/rules"
    [[ -d "$rules_link.tmp" ]] && rm -r "$rules_link.tmp"
    mkdir "$rules_link.tmp"
    for pack in "${valid[@]}"; do ln -s "$RULES_SRC/$pack" "$rules_link.tmp/$pack"; done
    mv -T "$rules_link.tmp" "$rules_link"
}

remove_rules_link() {
    if [[ -L "$rules_link" ]]; then
        rm -f "$rules_link"
    elif [[ -d "$rules_link" ]]; then
        find "$rules_link" -mindepth 1 -maxdepth 1 -type l -delete
        rmdir "$rules_link" 2>/dev/null || echo "$rules_link tem arquivos que não são links; deixei" >&2
    fi
}

do_on() {
    [[ -f "$RULES_SRC/.ecc-sha" ]] || { echo "Rules ausentes; rode vendor/ecc/fetch-upstream.sh" >&2; exit 1; }
    valid_settings || { echo "settings.local.json inválido (não é um objeto JSON): $settings" >&2; exit 1; }
    write_settings '.enabledPlugins[$p] = true' --arg p "$PLUGIN"
    rm -f "$off_marker"

    local names=()
    if [[ $no_rules -eq 1 ]]; then
        :
    elif [[ -n "$packs" ]]; then
        IFS=, read -ra names <<<"$packs"
    elif [[ $no_common -eq 1 ]]; then
        local pack
        for pack in "$RULES_SRC"/*/; do
            [[ "$(basename "$pack")" == common ]] || names+=("$(basename "$pack")")
        done
    else
        # Rules completas: link único para o diretório (inclui rules/common).
        mkdir -p "$dir/.claude/rules"
        if [[ -e "$rules_link" && ! -L "$rules_link" && ! -d "$rules_link" ]]; then
            echo "$rules_link existe e não é link; não mexi nas rules" >&2
        else
            remove_rules_link; ln -s "$RULES_SRC" "$rules_link"
        fi
        exclude_add; return 0
    fi
    link_rules "${names[@]+"${names[@]}"}"
    exclude_add
}

do_off() {
    valid_settings || { echo "settings.local.json inválido (não é um objeto JSON): $settings" >&2; exit 1; }
    if [[ -s "$settings" ]]; then
        write_settings 'del(.enabledPlugins[$p]) | if .enabledPlugins == {} then del(.enabledPlugins) else . end' --arg p "$PLUGIN"
    fi
    remove_rules_link
    mkdir -p "$dir/.claude"
    : > "$off_marker"
    exclude_add
}

# Valor de uma chave do ecc-auto.conf (última ocorrência vence); lista separada por vírgula.
conf_value() {
    [[ -f "$AUTO_CONF" ]] || return 0
    sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$AUTO_CONF" | tail -n 1 | sed 's/[[:space:]]*$//'
}

matches_any() { # matches_any <caminho> <globs separados por vírgula>
    local path="$1" glob globs
    IFS=, read -ra globs <<<"$2"
    for glob in "${globs[@]+"${globs[@]}"}"; do
        glob="${glob#"${glob%%[![:space:]]*}"}"; glob="${glob%"${glob##*[![:space:]]}"}"
        glob="${glob/#\~/$HOME}"
        [[ -n "$glob" ]] || continue
        # shellcheck disable=SC2254
        case "$path" in $glob) return 0 ;; esac
    done
    return 1
}

# Um ecc-project por vez por repositório (duas sessões abrindo juntas disputariam o link das rules).
if [[ "$action" != status ]] && command -v flock >/dev/null 2>&1; then
    common="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
    if [[ -n "$common" && -d "$common" ]]; then exec 9>"$common/ecc-project.lock"; flock 9; fi
fi

case "$action" in
    on)
        do_on
        echo "ECC ligado em $dir @ $(cut -c1-7 "$RULES_SRC/.ecc-sha")$([[ $no_rules -eq 1 ]] && echo ' (só o plugin)'; [[ -n "$packs" ]] && echo " (packs: $packs)"; [[ $no_common -eq 1 && -z "$packs" && $no_rules -eq 0 ]] && echo ' (sem rules/common)'). Reinicie o Claude Code nesse projeto."
        ;;
    off)
        do_off
        echo "ECC desligado em $dir (marcador .claude/ecc.off criado; o auto não religa). Reinicie o Claude Code nesse projeto."
        ;;
    auto)
        [[ -e "$off_marker" ]] && exit 0
        [[ -z "$(plugin_value "$settings")" && -z "$(plugin_value "$dir/.claude/settings.json")" ]] || exit 0
        # Casa o caminho físico (raiz do git) e o digitado (pode passar por symlink).
        exclude_globs="$(conf_value exclude)"; include_globs="$(conf_value include)"
        if matches_any "$dir" "$exclude_globs" || matches_any "$logical_dir" "$exclude_globs"; then exit 0; fi
        if [[ -n "$include_globs" ]]; then
            matches_any "$dir" "$include_globs" || matches_any "$logical_dir" "$include_globs" || exit 0
        fi
        kinds="$(conf_value kinds | tr -d '[:space:]')"; kinds="${kinds:-web,c,node}"
        read -r kind kind_packs <<<"$("$DETECT" "$dir")"
        [[ "$kind" != none && ",$kinds," == *",$kind,"* ]] || exit 0
        valid_settings || { echo "ECC automático ignorado: $settings não é um objeto JSON válido" >&2; exit 0; }
        case "$kind" in
            web) packs="$kind_packs"; no_rules=0 ;;
            *) packs=""; no_rules=1 ;;
        esac
        do_on
        what="$kind: só o plugin"; [[ -n "$packs" ]] && what="$kind: $packs"
        printf 'ECC ligado automaticamente (%s). Desfazer: make ecc-off DIR=%q (ou touch %q).\n' "$what" "$dir" "$off_marker"
        ;;
    status)
        # Precedência do Claude Code: local > projeto > usuário. Chave ausente = herda.
        state="desligado"; scope="padrão"
        for candidate in "$settings:local" "$dir/.claude/settings.json:projeto" "$USER_SETTINGS:usuário"; do
            value="$(plugin_value "${candidate%:*}")"
            [[ -n "$value" ]] || continue
            [[ "$value" == true ]] && state="ligado"
            scope="${candidate##*:}"
            break
        done
        rules="sem rules"
        if [[ -L "$rules_link" ]]; then rules="rules completas"
        elif [[ -d "$rules_link" ]]; then
            pack_names="$(find "$rules_link" -mindepth 1 -maxdepth 1 -type l -printf '%f,' 2>/dev/null | sed 's/,$//')"
            if [[ -d "$rules_link/common" ]]; then rules="rules completas"
            else rules="rules: ${pack_names:-nenhuma}"; fi
        fi
        marker=""; [[ -e "$off_marker" ]] && marker=", ecc.off"
        if [[ $short -eq 1 ]]; then
            echo "ECC $state ($scope)."
        else
            echo "$dir: ECC $state ($scope), $rules$marker (pin $(cut -c1-7 "$RULES_SRC/.ecc-sha" 2>/dev/null || echo '?'))"
        fi
        ;;
esac
