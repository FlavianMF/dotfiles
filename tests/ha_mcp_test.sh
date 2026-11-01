#!/bin/bash
# Testes TDD de homeassistant/setup-mcp.sh e bin/ha-mcp-ctl (unitário e sem rede).
# Uso: bash tests/ha_mcp_test.sh
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

SETUP_SCRIPT="$ROOT/homeassistant/setup-mcp.sh"
CTL_SCRIPT="$ROOT/bin/ha-mcp-ctl"

# 1. Existência e execução dos scripts
if [[ ! -f "$SETUP_SCRIPT" ]]; then
    echo "❌ FALHA: homeassistant/setup-mcp.sh não existe"
    exit 1
fi

if [[ ! -x "$SETUP_SCRIPT" ]]; then
    echo "❌ FALHA: homeassistant/setup-mcp.sh não tem permissão de execução"
    fail=1
fi

if [[ ! -L "$CTL_SCRIPT" && ! -f "$CTL_SCRIPT" ]]; then
    echo "❌ FALHA: bin/ha-mcp-ctl não existe"
    fail=1
fi

# 2. Template secrets/mcp.env.example
EXAMPLE_ENV="$ROOT/secrets/mcp.env.example"
if [[ ! -f "$EXAMPLE_ENV" ]]; then
    echo "❌ FALHA: secrets/mcp.env.example não existe"
    fail=1
else
    content_example="$(cat "$EXAMPLE_ENV")"
    has "template contem HOMEASSISTANT_URL" "HOMEASSISTANT_URL" "$content_example"
    has "template contem HOMEASSISTANT_TOKEN" "HOMEASSISTANT_TOKEN" "$content_example"
    has "template aponta para IP Tailscale da VPS" "100.105.143.75:8123" "$content_example"
fi

# 3. Ajuda / Help
out_help="$(bash "$SETUP_SCRIPT" --help 2>&1)"
has "help exibe uso" "Uso: setup-mcp.sh" "$out_help"
has "help lista comando check" "check" "$out_help"
has "help lista comando config" "config" "$out_help"
has "help lista opcao dry-run" "--dry-run" "$out_help"

# Teste de help via bin/ha-mcp-ctl
out_ctl_help="$("$CTL_SCRIPT" --help 2>&1)"
has "ctl executa e exibe uso" "Uso: setup-mcp.sh" "$out_ctl_help"

# 4. Opção desconhecida
out_unknown="$(bash "$SETUP_SCRIPT" --invalido 2>&1 || true)"
has "opcao invalida avisa erro" "Erro: Opção ou comando desconhecido" "$out_unknown"

# 5. Modo config com --dry-run
out_config_dry="$(bash "$SETUP_SCRIPT" config --dry-run 2>&1)"
rc_config_dry=$?
expect "config --dry-run sai com 0" "$rc_config_dry" "0"
has "indica modo dry-run" "MODO DRY-RUN" "$out_config_dry"
has "configura Claude Code" "Claude Code" "$out_config_dry"
has "configura Gemini" "Gemini CLI / Antigravity" "$out_config_dry"
has "configura OpenCode" "OpenCode" "$out_config_dry"
has "configura Cursor" "Cursor" "$out_config_dry"
has "menciona comando uvx ha-mcp" "uvx ha-mcp" "$out_config_dry"

# 6. Modo config filtrado por cliente
out_claude_dry="$(bash "$SETUP_SCRIPT" config --client claude --dry-run 2>&1)"
has "filtra claude" "Claude Code" "$out_claude_dry"
if grep -q "OpenCode" <<<"$out_claude_dry"; then
    echo "❌ FALHA: filtro claude não deveria conter OpenCode"
    fail=1
else
    echo "✅ PASSOU: filtro por cliente isola Claude Code"
fi

# 7. Diagnóstico check com mocks (simulação de sucesso)
# Criar mocks de uvx e curl no PATH temporário
cat >"$tmp/bin/uvx" <<'MOCK'
#!/bin/bash
echo "uvx 0.5.0"
MOCK
chmod +x "$tmp/bin/uvx"

cat >"$tmp/bin/curl" <<'MOCK'
#!/bin/bash
# Mock para responder 200 nas chamadas de health e api
echo "200"
MOCK
chmod +x "$tmp/bin/curl"

out_check_ok="$(HOMEASSISTANT_URL="http://100.105.143.75:8123" HOMEASSISTANT_TOKEN="token_teste_123" bash "$SETUP_SCRIPT" check 2>&1)"
rc_check_ok=$?
expect "check com sucesso sai com 0" "$rc_check_ok" "0"
has "uvx identificado" "Utilitário uvx (Astral uv): ✓ OK" "$out_check_ok"
has "conectividade ok" "Conectividade Tailscale (http://100.105.143.75:8123): ✓ OK" "$out_check_ok"
has "token identificado" "Token de Autenticação (HOMEASSISTANT_TOKEN): ✓ Configurado" "$out_check_ok"

# 8. Diagnóstico check com falha de conectividade (mock curl falhando)
cat >"$tmp/bin/curl" <<'MOCK'
#!/bin/bash
echo "000"
exit 7
MOCK
chmod +x "$tmp/bin/curl"

out_check_fail="$(HOMEASSISTANT_URL="http://100.105.143.75:8123" bash "$SETUP_SCRIPT" check 2>&1 || true)"
has "detecta falha de conectividade" "❌ FALHA" "$out_check_fail"
has "alerta sobre Tailscale" "Verifique se o Tailscale está ativo" "$out_check_fail"

# 9. Diagnóstico check sem uvx
rm -f "$tmp/bin/uvx"
# Isolar PATH para não herdar uvx do host
mkdir -p "$tmp/nouvx"
for b in /bin/* /usr/bin/*; do
    bn="$(basename "$b")"
    [[ "$bn" != "uvx" && ! -e "$tmp/nouvx/$bn" ]] && ln -s "$b" "$tmp/nouvx/$bn" 2>/dev/null || true
done
out_no_uvx="$(PATH="$tmp/nouvx" bash "$SETUP_SCRIPT" check 2>&1 || true)"
has "detecta falta de uvx" "❌ NÃO ENCONTRADO" "$out_no_uvx"

# 10. Wrapper stdio descarta linhas não-JSON do stdout (uvx falso imprime "[ENV] ...")
STDIO_WRAPPER="$ROOT/homeassistant/ha-mcp-stdio.sh"
mkdir -p "$tmp/fakebin"
cat >"$tmp/fakebin/uvx" <<'MOCK'
#!/bin/bash
echo "[ENV] WARNING: No environment file found."
echo '{"jsonrpc":"2.0","id":1,"result":{}}'
echo "ruído sem JSON"
MOCK
chmod +x "$tmp/fakebin/uvx"
out_stdio="$(PATH="$tmp/fakebin:$PATH" bash "$STDIO_WRAPPER" </dev/null 2>/dev/null)"
expect "wrapper deixa só a linha JSON-RPC" "$out_stdio" '{"jsonrpc":"2.0","id":1,"result":{}}'
[[ -L "$ROOT/bin/ha-mcp-stdio" ]] && expect "symlink bin/ha-mcp-stdio resolve" "$(readlink "$ROOT/bin/ha-mcp-stdio")" "../homeassistant/ha-mcp-stdio.sh"

# 11. Configs de cliente apontam para o wrapper, não para uvx cru
out_cfg="$(bash "$SETUP_SCRIPT" config --dry-run --client all 2>&1)"
has "gemini usa o wrapper" "bin/ha-mcp-stdio" "$out_cfg"
if grep -F -q '"ha-mcp"' <<<"$out_cfg"; then
    echo "❌ FALHA: snippet ainda chama uvx ha-mcp direto"
    fail=1
else
    echo "✅ PASSOU: snippets não chamam uvx ha-mcp direto"
fi

echo "----------------------------------------"
if [[ $fail -eq 0 ]]; then
    echo "🎉 Todos os testes de setup-mcp.sh e ha-mcp-ctl PASSARAM!"
else
    echo "💥 Foram encontradas $fail falhas no teste TDD."
fi
exit $fail
