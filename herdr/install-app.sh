#!/usr/bin/env bash
# Instala o layout "traycer" e os mods no Herdr app (GUI).
# Copia, nunca cria symlink: o app grava em ~/.config/herdr-app e roda no Windows.
# Se o destino já existir e for diferente, guarda <arquivo>.bak.AAAAMMDD-HHMMSS antes.
# Uso: install-app.sh [--dry-run]
set -euo pipefail

dry=0
[[ "${1:-}" == "--dry-run" ]] && dry=1

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/app"

# Destino: HERDR_APP_HOME, senão o home do Windows visto do WSL, senão o home local.
dest="${HERDR_APP_HOME:-}"
if [[ -z "$dest" ]]; then
    for d in /mnt/c/Users/*/.config/herdr-app; do
        [[ -d "$d" ]] && { dest="$d"; break; }
    done
fi
[[ -n "$dest" ]] || dest="$HOME/.config/herdr-app"
[[ -d "$dest" ]] || { echo "install-app: $dest não existe. Abra o Herdr app uma vez." >&2; exit 1; }

stamp="$(date +%Y%m%d-%H%M%S)"

copy_file() {
    local from="$1" to="$2"
    mkdir -p "$(dirname "$to")"
    if [[ -f "$to" ]] && cmp -s "$from" "$to"; then
        echo "igual:   $to"
        return
    fi
    if [[ -f "$to" ]]; then
        echo "backup:  $to -> $to.bak.$stamp"
        (( dry )) || cp -p "$to" "$to.bak.$stamp"
    fi
    echo "copia:   $to"
    (( dry )) || cp "$from" "$to"
}

while IFS= read -r -d '' f; do
    copy_file "$f" "$dest/${f#"$src"/}"
done < <(find "$src" -type f -print0)

# Teclas por layout: herdr/keys/*.json são mesclados em keys.json (as seções do arquivo entram ou substituem;
# o resto do keys.json fica como está). O app relê o keys.json sozinho.
keys_src="$(dirname "$src")/keys"
if [[ -d "$keys_src" && -f "$dest/keys.json" ]] && command -v jq >/dev/null 2>&1; then
    for k in "$keys_src"/*.json; do
        [[ -f "$k" ]] || continue
        merged="$(jq --slurpfile new "$k" '. * $new[0]' "$dest/keys.json")"
        if [[ "$(jq -c . "$dest/keys.json")" == "$(printf '%s' "$merged" | jq -c .)" ]]; then
            echo "igual:   $dest/keys.json ($(basename "$k"))"
            continue
        fi
        echo "backup:  $dest/keys.json -> $dest/keys.json.bak.$stamp"
        echo "mescla:  $dest/keys.json ($(basename "$k"))"
        if (( ! dry )); then
            cp -p "$dest/keys.json" "$dest/keys.json.bak.$stamp"
            printf '%s\n' "$merged" > "$dest/keys.json.tmp" && mv "$dest/keys.json.tmp" "$dest/keys.json"
        fi
    done
fi

# WSL: o hook e o hub do cockpit chamam `herdr-app`, e o Windows só tem herdr-app.exe. O wrapper vai, por cópia, para ~/.local/bin.
# Sem ele o hook grava pane: null e a lista Agents do sidebar fica vazia.
if command -v herdr-app.exe >/dev/null 2>&1; then
    wrapper="$HOME/.local/bin/herdr-app"
    [[ -L "$wrapper" ]] && { echo "troca:   $wrapper (link vira cópia)"; (( dry )) || rm -f "$wrapper"; }
    copy_file "$(dirname "$src")/bin/herdr-app" "$wrapper"
fi

echo "destino: $dest"
(( dry )) && echo "(dry-run: nada foi alterado)"
exit 0
