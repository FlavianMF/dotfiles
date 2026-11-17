#!/usr/bin/env bash
# Reaplica os patches do plugin cockpit (hooks herdr.ts e sidebar.ts) que ligam a sessão do Claude ao terminal do Herdr app
# e dão a cada sessão o próprio título na lista Agents.
# Sem ele, numa janela remota (machine wsl), HC_TERMINAL_ID vale "t12" e o app lista "wsl/t12": o hook grava
# pane: null e o cockpit não nomeia as abas dos agentes. Um `/plugin update` recopia o hook e apaga o patch.
# Idempotente: arquivo que já tem o marcador "ADAPTADO para dotfiles" fica como está.
# Se o upstream mudou e o patch não aplica, não mexe no arquivo, avisa e sai com 2.
# Uso: cockpit-plugin-patch.sh [--quiet]
set -euo pipefail

quiet=0
[[ "${1:-}" == "--quiet" ]] && quiet=1
say() { (( quiet )) || echo "$@"; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
marker="ADAPTADO para dotfiles"
stamp="$(date +%Y%m%d-%H%M%S)"
status=0
work="$(mktemp -d)"
trap 'find "$work" -mindepth 1 -delete 2>/dev/null; rmdir "$work" 2>/dev/null || true' EXIT

shopt -s nullglob
for name in herdr sidebar; do
    patch_file="$here/patches/cockpit-plugin-$name-ts.patch"
    for file in "$HOME"/.claude/plugins/cache/cockpit/cockpit/*/hooks/$name.ts; do
        if grep -q "$marker" "$file"; then
            say "igual:   $file"
            continue
        fi
        mkdir -p "$work/hooks"
        cp "$file" "$work/hooks/$name.ts"
        if ! (cd "$work" && patch -p1 --forward -s < "$patch_file") >/dev/null 2>&1; then
            echo "cockpit-plugin-patch: o patch de $file não aplica (o upstream mudou). Refaça o patch e gere $patch_file de novo." >&2
            status=2
            continue
        fi
        cp -p "$file" "$file.bak.$stamp"
        cp "$work/hooks/$name.ts" "$file.new" && mv "$file.new" "$file"
        say "patch:   $file"
    done
done
exit "$status"
