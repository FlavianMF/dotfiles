#!/bin/bash
# Camada de carga das skills soltas: liga por projeto as skills que o tipo do projeto usa.
#
# Uso: claude/skills-project.sh auto|status [dir]
#
# auto:   para cada linha `skill=tipos` de claude/skills-auto.conf, cria o link
#         <raiz do git>/.claude/skills/<skill> -> ~/.agents/skills/<skill> quando o tipo do projeto
#         (claude/ecc-detect.sh) está na lista; senão apaga o link que o próprio auto criou
#         (lista em .claude/skills.auto). Nunca toca em skill do projeto que o auto não criou.
#         Silencioso e sem efeito se houver .claude/skills.off ou se o projeto for este repo.
# status: mostra o que o auto gerencia no projeto.
# O estado só vale em sessão nova.
set -euo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECT="$REPO_DIR/claude/ecc-detect.sh"
CONF="${SKILLS_AUTO_CONF:-$REPO_DIR/claude/skills-auto.conf}"
SRC="${SKILLS_AUTO_SRC:-$HOME/.agents/skills}"

action="${1:-}"; shift || true
dir="${1:-.}"
[[ "$action" =~ ^(auto|status)$ ]] || { echo "Uso: $0 auto|status [dir]" >&2; exit 1; }
[[ -d "$dir" ]] || { [[ "$action" == auto ]] && exit 0; echo "Diretório não existe: $dir" >&2; exit 1; }
dir="$(cd "$dir" && pwd)"
top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || { [[ "$action" == auto ]] && exit 0; echo "Fora de um repositório git" >&2; exit 1; }
dir="$(cd "$top" && pwd)"
[[ "$action" == auto && "$dir" == "$REPO_DIR" ]] && exit 0
[[ -f "$CONF" ]] || exit 0

skills_dir="$dir/.claude/skills"
owned_file="$dir/.claude/skills.auto"
off_marker="$dir/.claude/skills.off"

# Linhas `skill=tipos` sem comentário nem espaço.
entries() { sed -E 's/[[:space:]]+//g; /^(#|$)/d; /^[^=]+=[^=]+$/!d' "$CONF"; }
is_owned() { grep -qxF -- "$1" "$owned_file" 2>/dev/null; }

disown() { # disown <skill>
    [[ -f "$owned_file" ]] || return 0
    local keep; keep="$(grep -vxF -- "$1" "$owned_file" || true)"
    if [[ -n "$keep" ]]; then printf '%s\n' "$keep" > "$owned_file"; else rm -f "$owned_file"; fi
}

exclude_add() { # exclude_add <entrada>...
    local git_dir exclude entry
    git_dir="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 0
    exclude="$git_dir/info/exclude"
    mkdir -p "$(dirname "$exclude")"; touch "$exclude"
    [[ -s "$exclude" && -n "$(tail -c1 "$exclude")" ]] && echo >> "$exclude"
    for entry in "$@"; do
        grep -qxF "$entry" "$exclude" || echo "$entry" >> "$exclude"
    done
}

case "$action" in
    status)
        read -r kind _ <<<"$("$DETECT" "$dir")"
        echo "$dir: tipo $kind"
        while IFS="=" read -r skill kinds; do
            mark="ausente"
            if [[ -L "$skills_dir/$skill" ]]; then mark="ligada"; is_owned "$skill" && mark="ligada, gerenciada pelo auto"; fi
            echo "  $skill (ligada em: $kinds): $mark"
        done < <(entries)
        [[ -e "$off_marker" ]] && echo "  skills.off presente"
        ;;
    auto)
        [[ -e "$off_marker" ]] && exit 0
        [[ ! -e "$dir/.claude" || -d "$dir/.claude" ]] || exit 0
        [[ ! -e "$skills_dir" || -d "$skills_dir" ]] || exit 0
        read -r kind _ <<<"$("$DETECT" "$dir")"
        added=()
        while IFS="=" read -r skill kinds; do
            if [[ ",$kinds," == *",$kind,"* ]]; then
                [[ -d "$SRC/$skill" ]] || continue
                [[ -e "$skills_dir/$skill" || -L "$skills_dir/$skill" ]] && continue  # já existe: do projeto ou do auto
                mkdir -p "$skills_dir"
                ln -s "$SRC/$skill" "$skills_dir/$skill"
                printf '%s\n' "$skill" >> "$owned_file"
                exclude_add "/.claude/skills/$skill"
                added+=("$skill")
            elif is_owned "$skill"; then
                [[ -L "$skills_dir/$skill" ]] && rm -f "$skills_dir/$skill"
                disown "$skill"
            fi
        done < <(entries)
        if [[ ${#added[@]} -gt 0 ]]; then
            exclude_add /.claude/skills.auto /.claude/skills.off
            printf 'Skills ligadas neste projeto (tipo %s): %s. Desfazer: touch %q e apague os links.\n' \
                "$kind" "${#added[@]}" "$off_marker"
        fi
        ;;
esac
