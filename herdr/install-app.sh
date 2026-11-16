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

echo "destino: $dest"
(( dry )) && echo "(dry-run: nada foi alterado)"
exit 0
