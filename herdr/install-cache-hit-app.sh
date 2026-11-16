#!/usr/bin/env bash
# Instala o mod cache-hit (adaptado ao WSL) no Herdr app.
# Clona e-kotov/herdr-cache-hit na versão fixada, grava o caminho em plugin-root
# e roda install-app.sh para copiar o mod. Rode no WSL.
# Uso: install-cache-hit-app.sh
set -euo pipefail

ref=9d887525f0492c9fa2cc5f177224f438c3202af1
checkout="${CACHE_HIT_DIR:-$HOME/.local/share/herdr-cache-hit}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -d "$checkout/.git" ]]; then
    git clone -q https://github.com/e-kotov/herdr-cache-hit.git "$checkout"
fi
git -C "$checkout" fetch -q origin
git -C "$checkout" checkout -q -f "$ref"
# Patch local: resolve a sessão do claude pelo pid (dois claude na mesma pasta).
git -C "$checkout" apply "$here/patches/cache-hit-wsl-claude-session.patch"

# Wrapper do WSL: carrega o PATH de login e roda `env "$@"` (wsl.exe reparseia aspas).
cat > "$checkout/herdr-app-run.sh" <<'W'
#!/usr/bin/env bash
# shellcheck disable=SC1091
[ -f "$HOME/.profile" ] && . "$HOME/.profile"
PATH="$HOME/.local/bin:$PATH"
exec env "$@"
W
chmod +x "$checkout/herdr-app-run.sh"

"$here/install-app.sh"

dest="${HERDR_APP_HOME:-}"
if [[ -z "$dest" ]]; then
    for d in /mnt/c/Users/*/.config/herdr-app; do
        [[ -d "$d" ]] && { dest="$d"; break; }
    done
fi
[[ -n "$dest" ]] || dest="$HOME/.config/herdr-app"
printf '%s\n' "$checkout" > "$dest/mods/cache-hit/plugin-root"
echo "plugin-root: $checkout (commit ${ref:0:7})"
