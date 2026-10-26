#!/bin/bash
# Testes de ccr/install.sh, traycer/install.sh e zsh/ccr.zsh. Uso: bash tests/ccr_traycer_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT
fail=0
expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
has() { if ! grep -q -- "$2" <<<"$3"; then echo "FALHA: $1 (faltou '$2' em: $3)"; fail=1; fi; }

mkdir "$tmp/bin" "$tmp/home"
# curl falso: grava um arquivo fixo no destino de -o e nunca toca a rede.
cat >"$tmp/bin/curl" <<'FAKE'
#!/bin/bash
out=""; while [[ $# -gt 0 ]]; do [[ "$1" == -o ]] && out="$2"; shift; done
printf 'fake-appimage' >"$out"
FAKE
chmod +x "$tmp/bin/curl"
export HOME="$tmp/home" PATH="$tmp/bin:$PATH"

# --- Traycer ---
out="$(bash "$ROOT/traycer/install.sh" --dry-run 2>&1)"
has "dry-run baixa" "download" "$out"
has "dry-run instala o launcher" "$HOME/.local/bin/traycer" "$out"
[[ ! -e "$HOME/.local/bin/traycer" ]] || { echo "FALHA: dry-run criou o launcher"; fail=1; }

# Cópia do instalador com um SHA256 que não bate.
cp -r "$ROOT/traycer" "$tmp/tr"
out="$(bash "$tmp/tr/install.sh" 2>&1)"; rc=$?
expect "hash errado falha" "$rc" "1"
has "hash errado explica" "sha256 mismatch" "$out"
[[ ! -e "$HOME/.local/opt/traycer/traycer.AppImage" ]] || { echo "FALHA: instalou com hash errado"; fail=1; }

# --update regrava o hash sem instalar; depois o install passa.
bash "$tmp/tr/install.sh" --update >/dev/null 2>&1
expect "update grava o sha256 do download" "$(cut -d' ' -f1 "$tmp/tr/SHA256")" "$(printf 'fake-appimage' | sha256sum | cut -d' ' -f1)"
[[ ! -e "$HOME/.local/bin/traycer" ]] || { echo "FALHA: --update instalou"; fail=1; }
bash "$tmp/tr/install.sh" >/dev/null 2>&1; expect "install com hash certo" "$?" "0"
[[ -x "$HOME/.local/opt/traycer/traycer.AppImage" && -x "$HOME/.local/bin/traycer" ]] || { echo "FALHA: arquivos instalados ausentes"; fail=1; }

# Sem SHA256 o install falha.
rm "$tmp/tr/SHA256"
bash "$tmp/tr/install.sh" >/dev/null 2>&1; expect "sem SHA256 falha" "$?" "1"

# --- CCR ---
expect "VERSION é semver" "$(grep -c -E '^[0-9]+\.[0-9]+\.[0-9]+$' "$ROOT/ccr/VERSION")" "1"
bash "$ROOT/ccr/install.sh" --update "abc" >/dev/null 2>&1; expect "--update rejeita versão inválida" "$?" "2"
if command -v npm >/dev/null && [[ "$(node -v | sed -E 's/^v([0-9]+).*/\1/')" -ge 22 ]]; then
    out="$(CCR_PREFIX="$tmp/prefix" bash "$ROOT/ccr/install.sh" --dry-run 2>&1)"
    has "dry-run fixa a versão" "claude-code-router@$(tr -d '[:space:]' <"$ROOT/ccr/VERSION")" "$out"
fi

# --- ccrc ---
if command -v zsh >/dev/null; then
    cat >"$tmp/bin/ccr" <<'FAKE'
#!/bin/bash
printf 'ccr:%s\n' "$*" >>"$CCR_LOG"
FAKE
    chmod +x "$tmp/bin/ccr"
    export CCR_LOG="$tmp/ccr.log"
    zsh -c 'source "$1/zsh/ccr.zsh"; ccrc --model sonnet' zsh "$ROOT" >/dev/null 2>&1
    expect "ccrc sobe o gateway e lança o perfil" "$(cat "$CCR_LOG")" $'ccr:start --no-open\nccr:Claude Code cli -- --model sonnet'
    : >"$CCR_LOG"
    CCR_PROFILE=outro zsh -c 'source "$1/zsh/ccr.zsh"; ccrc' zsh "$ROOT" >/dev/null 2>&1
    expect "CCR_PROFILE troca o perfil" "$(tail -1 "$CCR_LOG")" "ccr:outro cli --"
    rm "$tmp/bin/ccr"
    out="$(zsh -c 'source "$1/zsh/ccr.zsh"; ccrc' zsh "$ROOT" 2>&1)"; rc=$?
    expect "ccrc sem ccr falha" "$rc" "1"
    has "ccrc sem ccr avisa" "ccr ausente" "$out"
fi

[[ $fail -eq 0 ]] && echo "ccr_traycer_test: ok"
exit $fail
