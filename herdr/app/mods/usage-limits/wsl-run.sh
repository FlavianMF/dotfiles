#!/usr/bin/env bash
# Wrapper do WSL: carrega o PATH de login (claude, codex, python3) e roda o comando.
# shellcheck disable=SC1091
[ -f "$HOME/.profile" ] && . "$HOME/.profile"
PATH="$HOME/.local/bin:$PATH"
exec "$@"
