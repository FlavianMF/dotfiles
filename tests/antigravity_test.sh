#!/bin/bash
# Testes de antigravity/install.sh e antigravity/render_config.sh. Uso: bash tests/antigravity_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT
fail=0
expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
has() { if ! grep -q -- "$2" <<<"$3"; then echo "FALHA: $1 (faltou '$2' em: $3)"; fail=1; fi; }

mkdir "$tmp/bin" "$tmp/home" "$tmp/fixture"
# curl falso: serve o manifesto e o payload de $tmp/fixture, sem tocar a rede.
cat >"$tmp/bin/curl" <<'FAKE'
#!/bin/bash
out=""; url=""
while [[ $# -gt 0 ]]; do
    case "$1" in -o) out="$2"; shift ;; -*) ;; *) url="$1" ;; esac
    shift
done
case "$url" in
    */manifests/*) cp "$FIXTURE/manifest.json" "$out" ;;
    *) cp "$FIXTURE/payload" "$out" ;;
esac
FAKE
chmod +x "$tmp/bin/curl"
export HOME="$tmp/home" PATH="$tmp/bin:$PATH" FIXTURE="$tmp/fixture"
export AGY_DOWNLOAD_BASE="https://fake.invalid"
BIN="$HOME/.local/bin/agy"

manifest() { # $1 = url, $2 = sha512
    printf '{"version":"9.9.9","url":"%s","sha512":"%s"}\n' "$1" "$2" >"$FIXTURE/manifest.json"
}

# Binário direto
printf '#!/bin/sh\necho agy-fake\n' >"$FIXTURE/payload"
good="$(sha512sum "$FIXTURE/payload" | cut -d' ' -f1)"

out="$(bash "$ROOT/antigravity/install.sh" --dry-run 2>&1)"
has "dry-run mostra o destino" "$BIN" "$out"
[[ ! -e "$BIN" ]] || { echo "FALHA: dry-run criou o binário"; fail=1; }

manifest "https://fake.invalid/agy" "deadbeef"
out="$(bash "$ROOT/antigravity/install.sh" 2>&1)"; rc=$?
expect "sha512 errado falha" "$rc" "1"
has "sha512 errado avisa" "sha512 mismatch" "$out"
[[ ! -e "$BIN" ]] || { echo "FALHA: instalou com sha512 errado"; fail=1; }

manifest "https://fake.invalid/agy" "$good"
out="$(bash "$ROOT/antigravity/install.sh" 2>&1)"; rc=$?
expect "instala binário direto" "$rc" "0"
expect "binário executa" "$("$BIN")" "agy-fake"
[[ ! -e "$HOME/.zshrc" && ! -e "$HOME/.bashrc" ]] || { echo "FALHA: o instalador mexeu em arquivos de shell"; fail=1; }

out="$(bash "$ROOT/antigravity/install.sh" 2>&1)"
has "segunda rodada pula" "already installed" "$out"

# tar.gz com o binário chamado "antigravity"
rm "$BIN"
mkdir "$FIXTURE/pkg"; printf '#!/bin/sh\necho agy-from-tar\n' >"$FIXTURE/pkg/antigravity"; chmod +x "$FIXTURE/pkg/antigravity"
tar -czf "$FIXTURE/payload" -C "$FIXTURE/pkg" antigravity
manifest "https://fake.invalid/agy.tar.gz" "$(sha512sum "$FIXTURE/payload" | cut -d' ' -f1)"
bash "$ROOT/antigravity/install.sh" >/dev/null 2>&1
expect "instala de tar.gz" "$("$BIN" 2>&1)" "agy-from-tar"

# --- render_config.sh ---
mkdir -p "$HOME/.gemini/antigravity-cli" "$HOME/.gemini/config"
echo '{"model":"m","trustedWorkspaces":["/w"],"permissions":{"allow":["command(git status)"],"deny":["command(foo)"]}}' >"$HOME/.gemini/antigravity-cli/settings.json"
echo '{"mcpServers":{"mine":{"command":"x"}}}' >"$HOME/.gemini/config/mcp_config.json"
bash "$ROOT/antigravity/render_config.sh" >/dev/null 2>&1; rc=$?
expect "render sai 0" "$rc" "0"
S="$HOME/.gemini/antigravity-cli/settings.json"; M="$HOME/.gemini/config/mcp_config.json"
expect "mantém chave só da máquina" "$(jq -r '.model' "$S")" "m"
expect "mantém allow da máquina" "$(jq -c '.permissions.allow' "$S")" '["command(git status)"]'
expect "une deny da máquina e da base" "$(jq -r '.permissions.deny | index("command(foo)") != null and index("command(sudo)") != null' "$S")" "true"
expect "expande HOME no deny" "$(jq -r '.permissions.deny | index("read_file('"$HOME"'/.ssh)") != null' "$S")" "true"
expect "sem @HOME@ sobrando" "$(grep -c '@HOME@' "$S")" "0"
expect "MCPs da base + da máquina" "$(jq -c '.mcpServers | keys' "$M")" '["figma","mine","playwright","rea"]'
before="$(sha1sum "$S" "$M")"
bash "$ROOT/antigravity/render_config.sh" >/dev/null 2>&1
expect "render idempotente" "$(sha1sum "$S" "$M")" "$before"

# JSON inválido no alvo: não sobrescreve
echo '{broken' >"$S"
bash "$ROOT/antigravity/render_config.sh" >/dev/null 2>&1; rc=$?
expect "JSON inválido falha" "$rc" "1"
expect "JSON inválido fica intacto" "$(cat "$S")" "{broken"

[[ $fail -eq 0 ]] && echo "antigravity_test: ok"
exit $fail
