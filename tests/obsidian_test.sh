#!/bin/bash
# Testes de obsidian/install.sh (sem rede). Uso: bash tests/obsidian_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -r "$tmp"' EXIT
fail=0
expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
has() { if ! grep -q -- "$2" <<<"$3"; then echo "FALHA: $1 (faltou '$2' em: $3)"; fail=1; fi; }

mkdir "$tmp/bin" "$tmp/home" "$tmp/vault" "$tmp/repo"
cp "$ROOT/obsidian/install.sh" "$tmp/repo/install.sh"
# curl falso: serve o payload de $tmp/payload, sem tocar a rede.
cat >"$tmp/bin/curl" <<'FAKE'
#!/bin/bash
out=""
while [[ $# -gt 0 ]]; do case "$1" in -o) out="$2"; shift ;; esac; shift; done
cp "$PAYLOAD" "$out"
FAKE
chmod +x "$tmp/bin/curl"
export HOME="$tmp/home" PATH="$tmp/bin:$PATH" PAYLOAD="$tmp/payload"
export OBSIDIAN_VAULT="$tmp/vault"
D="$HOME/.local/opt/obsidian"

# AppImage falso: --appimage-extract cria o ícone, como o real.
cat >"$tmp/payload" <<'APP'
#!/bin/bash
if [[ "${1:-}" == --appimage-extract ]]; then
    mkdir -p squashfs-root/usr/share/icons/hicolor/512x512/apps
    echo png > squashfs-root/usr/share/icons/hicolor/512x512/apps/obsidian.png
    exit 0
fi
echo "obsidian-fake $*"
APP
printf '9.9.9\n' >"$tmp/repo/VERSION"
good="$(sha256sum "$tmp/payload" | cut -d' ' -f1)"
printf '%s  Obsidian-9.9.9.AppImage\n' "$good" >"$tmp/repo/SHA256"

out="$(bash "$tmp/repo/install.sh" --dry-run 2>&1)"
has "dry-run mostra o destino" "$D/Obsidian-9.9.9.AppImage" "$out"
[[ ! -e "$D" ]] || { echo "FALHA: dry-run instalou"; fail=1; }

out="$(bash "$tmp/repo/install.sh" 2>&1)"; rc=$?
expect "instala" "$rc" "0"
[[ -x "$D/Obsidian-9.9.9.AppImage" ]] || { echo "FALHA: AppImage ausente"; fail=1; }
expect "link current" "$(readlink "$D/current.AppImage")" "Obsidian-9.9.9.AppImage"
[[ -x "$HOME/.local/bin/obsidian" ]] || { echo "FALHA: launcher ausente"; fail=1; }
has "desktop entry" "Exec=$HOME/.local/bin/obsidian" "$(cat "$HOME/.local/share/applications/obsidian.desktop")"
[[ -s "$HOME/.local/share/icons/hicolor/512x512/apps/obsidian.png" ]] || { echo "FALHA: ícone ausente"; fail=1; }
expect "launcher executa o AppImage" "$("$HOME/.local/bin/obsidian" --x | head -1 | sed 's/ --no-sandbox//')" "obsidian-fake --x"
cfg="$HOME/.config/obsidian/obsidian.json"
expect "vault registrado" "$(jq -r '.vaults[].path' "$cfg")" "$tmp/vault"
expect "vault aberto" "$(jq -r '.vaults[].open' "$cfg")" "true"

# Reexecução: não rebaixa nem mexe na config que o app já controla.
echo '{"vaults":{"abc":{"path":"/outro","ts":1}}}' >"$cfg"
out="$(bash "$tmp/repo/install.sh" 2>&1)"
has "idempotente" "already installed" "$out"
expect "config do app intacta" "$(jq -r '.vaults | keys[0]' "$cfg")" "abc"

# Versão antiga é removida ao trocar o pin.
cp "$tmp/payload" "$D/Obsidian-1.0.0.AppImage"
bash "$tmp/repo/install.sh" >/dev/null 2>&1
[[ ! -e "$D/Obsidian-1.0.0.AppImage" ]] || { echo "FALHA: AppImage antigo ficou"; fail=1; }

# sha256 errado falha e não instala.
rm -rf "$D"
printf 'deadbeef  Obsidian-9.9.9.AppImage\n' >"$tmp/repo/SHA256"
out="$(bash "$tmp/repo/install.sh" 2>&1)"; rc=$?
expect "sha256 errado falha" "$rc" "1"
has "mensagem de sha256" "sha256 mismatch" "$out"
[[ ! -e "$D/Obsidian-9.9.9.AppImage" ]] || { echo "FALHA: instalou com sha256 errado"; fail=1; }

# Pin sem entrada para a versão.
printf '%s  Obsidian-1.0.0.AppImage\n' "$good" >"$tmp/repo/SHA256"
bash "$tmp/repo/install.sh" >/dev/null 2>&1; rc=$?
expect "SHA256 sem a versão falha" "$rc" "1"

# Opção desconhecida.
bash "$tmp/repo/install.sh" --nope >/dev/null 2>&1; rc=$?
expect "opção desconhecida" "$rc" "2"

[[ $fail -eq 0 ]] && echo "obsidian_test: ok"
exit $fail
