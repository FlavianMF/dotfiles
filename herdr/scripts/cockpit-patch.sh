#!/usr/bin/env bash
# Reaplica os patches do layout multiproject no mod cockpit do Herdr app.
# O `cockpit update` recopia o mod inteiro do upstream e apaga os patches: este script os devolve.
# Idempotente: arquivo que já tem o marcador "ADAPTADO para dotfiles" fica como está.
# Se o upstream mudou e um patch não aplica, não mexe no arquivo, avisa e sai com 2.
# Uso: cockpit-patch.sh [--quiet]
set -euo pipefail

quiet=0
[[ "${1:-}" == "--quiet" ]] && quiet=1
say() { (( quiet )) || echo "$@"; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="${HERDR_APP_HOME:-}"
if [[ -z "$dest" ]]; then
    for d in /mnt/c/Users/*/.config/herdr-app; do
        [[ -d "$d" ]] && { dest="$d"; break; }
    done
fi
[[ -n "$dest" ]] || dest="$HOME/.config/herdr-app"
mod="$dest/mods/cockpit"
[[ -d "$mod" ]] || exit 0   # sem o app ou sem o mod: nada a fazer

marker="ADAPTADO para dotfiles"
stamp="$(date +%Y%m%d-%H%M%S)"
status=0
work="$(mktemp -d)"
trap 'find "$work" -mindepth 1 -delete 2>/dev/null; rmdir "$work" 2>/dev/null || true' EXIT

for f in activity sidebar; do
    file="$mod/$f.js"
    patch_file="$here/patches/cockpit-multiproject-$f.patch"
    [[ -f "$file" ]] || continue
    if grep -q "$marker" "$file"; then
        say "igual:   $file"
        continue
    fi
    mkdir -p "$work/$f/mods/cockpit"
    cp "$file" "$work/$f/mods/cockpit/$f.js"
    if ! (cd "$work/$f" && patch -p1 --forward -s < "$patch_file") >/dev/null 2>&1; then
        echo "cockpit-patch: o patch de $f.js não aplica (o upstream mudou). Refaça o patch e gere $patch_file de novo." >&2
        status=2
        continue
    fi
    cp -p "$file" "$file.bak.$stamp"
    cp "$work/$f/mods/cockpit/$f.js" "$file.new" && mv "$file.new" "$file"
    say "patch:   $file"
done
exit "$status"
