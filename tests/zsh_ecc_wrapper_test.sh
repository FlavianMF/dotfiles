#!/bin/bash
# Testes da função claude de zsh/ecc-auto.zsh. Uso: bash tests/zsh_ecc_wrapper_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v zsh >/dev/null || { echo "zsh ausente: teste ignorado"; exit 0; }
tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -r "$tmp"' EXIT
fail=0

export CLAUDE_CONFIG_DIR="$tmp/userconf"; mkdir -p "$CLAUDE_CONFIG_DIR"
echo '{"enabledPlugins":{"ecc@ecc":false}}' >"$CLAUDE_CONFIG_DIR/settings.json"
export ECC_AUTO_CONF="$tmp/auto.conf"; echo 'kinds=web,c,node' >"$ECC_AUTO_CONF"
export GIT_CONFIG_GLOBAL=/dev/null DOTFILES_DIR="$ROOT"
mkdir "$tmp/bin"
# claude falso: mostra os argumentos (um por linha) e se o ECC já estava ligado quando abriu.
cat >"$tmp/bin/claude" <<'FAKE'
#!/bin/bash
echo "FAKE-CLAUDE ecc=$(jq -r '.enabledPlugins["ecc@ecc"] // "ausente"' .claude/settings.local.json 2>/dev/null || echo ausente)"
printf 'arg:%s\n' "$@"
FAKE
chmod +x "$tmp/bin/claude"

expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
repo() { git init -q "$tmp/$1"; echo "$tmp/$1"; }
runz() { # runz <dir> <args...>: abre um zsh que carrega a função e chama claude; stdout em $tmp/out, stderr em $tmp/err
    local dir="$1"; shift
    (cd "$dir" && PATH="$tmp/bin:$PATH" zsh -c 'source "$DOTFILES_DIR/zsh/ecc-auto.zsh"; claude "$@"' zsh "$@" >"$tmp/out" 2>"$tmp/err")
}

d="$(repo web)"; echo '{"dependencies":{"react":"18"}}' >"$d/package.json"
runz "$d" -p "olá mundo" --flag
expect "liga antes de abrir" "$(head -n 1 "$tmp/out")" "FAKE-CLAUDE ecc=true"
expect "argumentos intactos" "$(tail -n +2 "$tmp/out" | paste -sd'|' -)" "arg:-p|arg:olá mundo|arg:--flag"
expect "aviso em stderr" "$(grep -c 'ligado automaticamente' "$tmp/err")" 1
expect "stdout limpo" "$(grep -c 'ligado automaticamente' "$tmp/out")" 0

runz "$d" ; expect "segunda vez silenciosa" "$(grep -c 'ligado automaticamente' "$tmp/err")" 0

d="$(repo sub)"; echo '{"dependencies":{"react":"18"}}' >"$d/package.json"
runz "$d" plugin list; expect "subcomando não liga" "$(head -n 1 "$tmp/out")" "FAKE-CLAUDE ecc=ausente"
runz "$d" --version; expect "--version não liga" "$(head -n 1 "$tmp/out")" "FAKE-CLAUDE ecc=ausente"
ECC_AUTO=0 runz "$d"; expect "ECC_AUTO=0 não liga" "$(head -n 1 "$tmp/out")" "FAKE-CLAUDE ecc=ausente"
runz "$d" "prompt solto"; expect "prompt posicional liga" "$(head -n 1 "$tmp/out")" "FAKE-CLAUDE ecc=true"

d="$(repo plain)"; echo x >"$d/README.md"
runz "$d"; expect "projeto comum: abre sem ligar" "$(head -n 1 "$tmp/out")" "FAKE-CLAUDE ecc=ausente"

# Falha do script não impede o claude de abrir.
mkdir -p "$tmp/broken/claude"; printf '#!/bin/bash\nexit 1\n' >"$tmp/broken/claude/ecc-project.sh"; chmod +x "$tmp/broken/claude/ecc-project.sh"
d="$(repo broken_case)"; echo '{"dependencies":{"react":"18"}}' >"$d/package.json"
DOTFILES_DIR="$tmp/broken" runz "$d"; expect "falha não bloqueia" "$(head -n 1 "$tmp/out")" "FAKE-CLAUDE ecc=ausente"
DOTFILES_DIR="$tmp/inexistente" runz "$d"; expect "script ausente não bloqueia" "$(head -n 1 "$tmp/out")" "FAKE-CLAUDE ecc=ausente"

[[ $fail -eq 0 ]] && echo "ok" || exit 1
