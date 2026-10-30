#!/bin/bash
# Testes TDD de tailscale/install.sh (unitário e sem rede).
# Uso: bash tests/tailscale_test.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT

fail=0
expect() {
    if [[ "$2" != "$3" ]]; then
        echo "❌ FALHA: $1 (obtido: '$2', esperado: '$3')"
        fail=1
    else
        echo "✅ PASSOU: $1"
    fi
}

has() {
    if ! grep -F -q -- "$2" <<<"$3"; then
        echo "❌ FALHA: $1 (faltou '$2' em: $3)"
        fail=1
    else
        echo "✅ PASSOU: $1"
    fi
}

mkdir -p "$tmp/bin"
export PATH="$tmp/bin:$PATH"

INSTALLER="$ROOT/tailscale/install.sh"

# 1. Existência do instalador
if [[ ! -f "$INSTALLER" ]]; then
    echo "❌ FALHA: tailscale/install.sh não existe (fase RED do TDD)"
    exit 1
fi

if [[ ! -x "$INSTALLER" ]]; then
    echo "❌ FALHA: tailscale/install.sh não tem permissão de execução"
    fail=1
fi

# 2. Ajuda / Help
out_help="$(bash "$INSTALLER" --help 2>&1)"
has "help exibe uso" "Uso: tailscale/install.sh" "$out_help"
has "help documenta dry-run" "--dry-run" "$out_help"

# 3. Opção desconhecida
out_unknown="$(bash "$INSTALLER" --opcao-invalida 2>&1)"
rc_unknown=$?
expect "opcao desconhecida sai com 2" "$rc_unknown" "2"
has "erro de opcao desconhecida" "Opção desconhecida" "$out_unknown"

# 4. Modo Dry-Run quando não instalado
out_dry="$(bash "$INSTALLER" --dry-run 2>&1)"
has "dry-run indica instalacao" "[dry-run]" "$out_dry"
has "dry-run menciona tailscale.com" "tailscale" "$out_dry"

# 5. Idempotência quando já instalado
cat >"$tmp/bin/tailscale" <<'MOCK'
#!/bin/bash
echo "tailscale 1.80.0"
MOCK
chmod +x "$tmp/bin/tailscale"

out_installed="$(bash "$INSTALLER" 2>&1)"
rc_installed=$?
expect "ja instalado sai com 0" "$rc_installed" "0"
has "mensagem de ja instalado" "já está instalado" "$out_installed"

# 6. Idempotência com dry-run quando já instalado
out_dry_installed="$(bash "$INSTALLER" --dry-run 2>&1)"
has "dry-run avisa que ja esta instalado" "já está instalado" "$out_dry_installed"

echo "----------------------------------------"
if [[ $fail -eq 0 ]]; then
    echo "🎉 Todos os testes de tailscale/install.sh PASSARAM!"
else
    echo "💥 Foram encontradas $fail falhas no teste TDD."
fi
exit $fail
