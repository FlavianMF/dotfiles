#!/bin/bash
# Testes de traycer/agy-acp-wrapper e traycer/install_agy_wrapper.sh. Uso: bash tests/agy_wrapper_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT
fail=0
expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
has() { if ! grep -q -- "$2" <<<"$3"; then echo "FALHA: $1 (faltou '$2' em: $3)"; fail=1; fi; }

W="$ROOT/traycer/agy-acp-wrapper"
export HOME="$tmp/home"; mkdir -p "$HOME"
# Servidor falso: ecoa o stdin e os argumentos, e sai com o código de AGY_FAKE_EXIT.
cat >"$tmp/fake_server" <<'FAKE'
#!/bin/bash
echo "args:$*"
cat
exit "${AGY_FAKE_EXIT:-0}"
FAKE
chmod +x "$tmp/fake_server"
export AGY_ACP_REAL="$tmp/fake_server"

init='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1}}'
out="$(printf '%s\n' "$init" | bash -c "$W --uid=")"
has "repassa argumentos" "args:--uid=" "$out"
has "injeta clientInfo zed" '"clientInfo":{"name":"zed","version":"1.0.0"}' "$out"
has "mantém os outros campos" '"protocolVersion":1' "$out"

out="$(printf '%s\n' "$init" | TRAYCER_AGY_CLIENT_NAME=xcode "$W")"
has "nome configurável" '"name":"xcode"' "$out"

given='{"id":1,"method":"initialize","params":{"clientInfo":{"name":"meu","version":"2"}}}'
out="$(printf '%s\n' "$given" | "$W")"
has "não sobrescreve clientInfo existente" '"name":"meu"' "$out"
[[ "$out" != *zed* ]] || { echo "FALHA: sobrescreveu clientInfo"; fail=1; }

other=$'{"id":2,"method":"session/new","params":{}}\nnot json'
out="$(printf '%s\n' "$other" | "$W" | tail -n +2)"
expect "demais mensagens passam intactas" "$out" "$other"

printf '' | AGY_FAKE_EXIT=7 "$W" >/dev/null; expect "propaga o código de saída" "$?" "7"

out="$(AGY_ACP_REAL='' TRAYCER_HOME_DIR="$tmp/none" "$W" </dev/null 2>&1)"; rc=$?
expect "sem servidor real sai com 127" "$rc" "127"
has "sem servidor real avisa" "cannot locate" "$out"

# --- instalador ---
export TRAYCER_HOME_DIR="$tmp/tc" TRAYCER_AGY_WRAPPER_DIR="$tmp/dest"
pack="$tmp/tc/host/providers/antigravity/linux-x64"
out="$(bash "$ROOT/traycer/install_agy_wrapper.sh" --dry-run 2>&1)"
has "dry-run lista o destino" "$tmp/dest/agy_acp_server" "$out"
[[ ! -e "$tmp/dest" ]] || { echo "FALHA: dry-run criou o destino"; fail=1; }

bash "$ROOT/traycer/install_agy_wrapper.sh" >/dev/null 2>&1; expect "sem pack falha" "$?" "1"

mkdir -p "$pack/1.0.0" "$pack/2.0.0"
echo '{"version":"1.0.0"}' >"$pack/current.json"
touch "$pack/1.0.0/localharness_external" "$pack/2.0.0/localharness_external"
bash "$ROOT/traycer/install_agy_wrapper.sh" >/dev/null 2>&1; expect "instala com pack" "$?" "0"
[[ -x "$tmp/dest/agy_acp_server" ]] || { echo "FALHA: wrapper não instalado"; fail=1; }
expect "symlink do companion" "$(readlink "$tmp/dest/localharness_external")" "$pack/1.0.0/localharness_external"
echo '{"version":"2.0.0"}' >"$pack/current.json"
bash "$ROOT/traycer/install_agy_wrapper.sh" >/dev/null 2>&1
expect "reinstalar repontua o symlink" "$(readlink "$tmp/dest/localharness_external")" "$pack/2.0.0/localharness_external"

[[ $fail -eq 0 ]] && echo "agy_wrapper_test: ok"
exit $fail
