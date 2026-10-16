#!/bin/bash
# Camada de carga do router de tokens: desliga por projeto os plugins que o tipo do projeto não usa.
#
# Uso: claude/plugins-project.sh auto|status [dir]
#
# auto:   para cada linha `plugin=tipos` de claude/plugins-auto.conf, grava enabledPlugins[plugin]=false
#         em <raiz do git>/.claude/settings.local.json quando o tipo do projeto (claude/ecc-detect.sh)
#         não está na lista; quando está, apaga a chave que o próprio auto gravou (herda o escopo
#         de usuário). Só mexe em chave que ele gravou (lista em .claude/plugins.auto) ou que está
#         ausente: decisão do usuário em settings.local.json ou settings.json do projeto vence.
#         Silencioso e sem efeito se houver .claude/plugins.off ou se o projeto for este repo.
# status: mostra o que o auto gerencia no projeto.
# O estado só vale em sessão nova. Nunca usa o CLI de plugin (ele reescreve o settings.json symlinkado).
set -euo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECT="$REPO_DIR/claude/ecc-detect.sh"
CONF="${PLUGINS_AUTO_CONF:-$REPO_DIR/claude/plugins-auto.conf}"

action="${1:-}"; shift || true
dir="${1:-.}"
[[ "$action" =~ ^(auto|status)$ ]] || { echo "Uso: $0 auto|status [dir]" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { [[ "$action" == auto ]] && exit 0; echo "jq não encontrado" >&2; exit 1; }
[[ -d "$dir" ]] || { [[ "$action" == auto ]] && exit 0; echo "Diretório não existe: $dir" >&2; exit 1; }
dir="$(cd "$dir" && pwd)"
top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || { [[ "$action" == auto ]] && exit 0; echo "Fora de um repositório git" >&2; exit 1; }
dir="$(cd "$top" && pwd)"
[[ "$action" == auto && "$dir" == "$REPO_DIR" ]] && exit 0
[[ -f "$CONF" ]] || exit 0

settings="$dir/.claude/settings.local.json"
project_settings="$dir/.claude/settings.json"
owned_file="$dir/.claude/plugins.auto"
off_marker="$dir/.claude/plugins.off"

# Linhas `plugin=tipos` sem comentário nem espaço.
entries() { sed -E 's/[[:space:]]+//g; /^(#|$)/d; /^[^=]+=[^=]+$/!d' "$CONF"; }

plugin_value() { # plugin_value <plugin> <arquivo>: true, false ou vazio
    [[ -f "$2" ]] || return 0
    jq -r --arg p "$1" '.enabledPlugins[$p] | if . == null then empty else tostring end' "$2" 2>/dev/null || true
}
is_owned() { grep -qxF -- "$1" "$owned_file" 2>/dev/null; }

write_settings() { # write_settings <filtro jq> [args]: preserva symlink e modo
    local current="{}" new
    [[ -s "$settings" ]] && current="$(cat "$settings")"
    new="$(printf '%s' "$current" | jq "${@:2}" "$1")" || { echo "settings.local.json com formato inesperado: $settings" >&2; exit 1; }
    mkdir -p "$dir/.claude"
    printf '%s\n' "$new" > "$settings"
}

exclude_add() {
    local git_dir exclude entry
    git_dir="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 0
    exclude="$git_dir/info/exclude"
    mkdir -p "$(dirname "$exclude")"; touch "$exclude"
    [[ -s "$exclude" && -n "$(tail -c1 "$exclude")" ]] && echo >> "$exclude"
    for entry in /.claude/settings.local.json /.claude/plugins.auto /.claude/plugins.off; do
        grep -qxF "$entry" "$exclude" || echo "$entry" >> "$exclude"
    done
}

disown() { # disown <plugin>
    [[ -f "$owned_file" ]] || return 0
    local keep; keep="$(grep -vxF -- "$1" "$owned_file" || true)"
    if [[ -n "$keep" ]]; then printf '%s\n' "$keep" > "$owned_file"; else rm -f "$owned_file"; fi
}

case "$action" in
    status)
        read -r kind _ <<<"$("$DETECT" "$dir")"
        echo "$dir: tipo $kind"
        while IFS="=" read -r plugin kinds; do
            value="$(plugin_value "$plugin" "$settings")"
            mark="herda"; is_owned "$plugin" && mark="gerenciado pelo auto"
            echo "  $plugin (ligado em: $kinds): ${value:-herda} [$mark]"
        done < <(entries)
        [[ -e "$off_marker" ]] && echo "  plugins.off presente"
        ;;
    auto)
        [[ -e "$off_marker" ]] && exit 0
        [[ ! -s "$settings" ]] || jq -e 'type == "object"' "$settings" >/dev/null 2>&1 || exit 0
        [[ ! -e "$dir/.claude" || -d "$dir/.claude" ]] || exit 0
        if command -v flock >/dev/null 2>&1; then
            common="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
            if [[ -n "$common" && -d "$common" ]]; then exec 9>"$common/ecc-project.lock"; flock 9; fi
        fi
        read -r kind _ <<<"$("$DETECT" "$dir")"
        changed=()
        while IFS="=" read -r plugin kinds; do
            if ! is_owned "$plugin" && [[ -n "$(plugin_value "$plugin" "$settings")$(plugin_value "$plugin" "$project_settings")" ]]; then
                continue  # decisão do usuário
            fi
            if [[ ",$kinds," == *",$kind,"* ]]; then
                if is_owned "$plugin"; then
                    write_settings 'del(.enabledPlugins[$p]) | if .enabledPlugins == {} then del(.enabledPlugins) else . end' --arg p "$plugin"
                    disown "$plugin"
                fi
            elif [[ "$(plugin_value "$plugin" "$settings")" != false ]] || ! is_owned "$plugin"; then
                write_settings '.enabledPlugins[$p] = false' --arg p "$plugin"
                mkdir -p "$dir/.claude"
                is_owned "$plugin" || printf '%s\n' "$plugin" >> "$owned_file"
                changed+=("${plugin%@*}")
            fi
        done < <(entries)
        if [[ ${#changed[@]} -gt 0 ]]; then
            exclude_add
            printf 'Plugins desligados neste projeto (tipo %s): %s. Desfazer: touch %q e apague a chave em settings.local.json.\n' \
                "$kind" "$(IFS=,; echo "${changed[*]}")" "$off_marker"
        fi
        ;;
esac
