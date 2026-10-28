#!/bin/bash
# SessionStart: injeta o índice de artifacts do épico Traycer atual.
#
# Só roda dentro do Traycer (TRAYCER_EPIC_ID definido). Lê apenas o frontmatter
# (title, kind, status) de ~/.traycer/epics/<id>/artifacts/*/index.md e dos filhos
# diretos (*/*/index.md). Não lê o corpo nem .comments/. Imprime no máximo 10
# artifacts, um por linha: `título (kind, status) — caminho relativo — atualizado AAAA-MM-DD`.
# A data é o mtime do index.md (`date -r`, ou `stat -f` no macOS); se os dois falharem, omite o trecho.
# Silencioso se não houver artifacts. Desligue com TRAYCER_EPIC_HOOK=0. Sempre exit 0.

[[ "${TRAYCER_EPIC_HOOK:-1}" == "0" ]] && exit 0
epic="${TRAYCER_EPIC_ID:-}"
[[ -n "$epic" ]] || exit 0
# O id vira parte de um caminho: recusa qualquer coisa fora de [A-Za-z0-9_-].
[[ "$epic" =~ ^[A-Za-z0-9_-]+$ ]] || exit 0

root="$HOME/.traycer/epics/$epic/artifacts"
[[ -d "$root" ]] || exit 0

max=10
lines=""
count=0
shopt -s nullglob
for file in "$root"/*/index.md "$root"/*/*/index.md; do
    [[ -f "$file" ]] || continue
    rel="${file#"$root"/}"
    # Frontmatter: só o bloco entre a primeira linha `---` e o próximo `---`.
    meta="$(awk '
        NR == 1 { if ($0 != "---") exit; next }
        $0 == "---" { exit }
        /^(title|kind|status):/ {
            key = $0; sub(/:.*/, "", key)
            val = $0; sub(/^[^:]*:[ \t]*/, "", val)
            gsub(/^["\x27]|["\x27][ \t]*$/, "", val)
            print key "\t" val
        }
    ' "$file" 2>/dev/null | head -n 3)"
    title="" kind="" status=""
    while IFS=$'\t' read -r key val; do
        case "$key" in
            title) title="$val" ;;
            kind) kind="$val" ;;
            status) status="$val" ;;
        esac
    done <<<"$meta"
    [[ -n "$title" ]] || title="$(basename "$(dirname "$rel")")"
    label="${kind:-?}"
    [[ -n "$status" ]] && label="$label, $status"
    mtime="$(date -r "$file" +%F 2>/dev/null || stat -f %Sm -t %F "$file" 2>/dev/null)"
    line="$title ($label) — $rel"
    [[ "$mtime" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && line+=" — atualizado $mtime"
    lines+="$line"$'\n'
    ((++count >= max)) && break
done

[[ -n "$lines" ]] || exit 0
printf 'Traycer: artifacts do épico atual (leia o índice antes do transcript de outro agente):\n%s' "$lines"
exit 0
