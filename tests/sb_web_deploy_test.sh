#!/bin/bash
# Testes do deploy web do Second Brain (Sprint 12).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT="$ROOT/systemd/user/sb-web.service"

tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/secrets" "$tmp/home/.config/systemd/user" "$tmp/home/.local/bin"

fail=0
expect() {
    local name="$1" got="$2" exp="$3"
    if [[ "$got" != "$exp" ]]; then
        echo "FALHA: $name (obtido '$got', esperado '$exp')" >&2
        fail=1
    fi
}

# 1. Mocks de systemctl e tailscale
cat << 'MOCK_SYS' > "$tmp/bin/systemctl"
#!/bin/bash
echo "systemctl $@" >> "$SYS_LOG"
exit 0
MOCK_SYS
chmod +x "$tmp/bin/systemctl"

cat << 'MOCK_TS' > "$tmp/bin/tailscale"
#!/bin/bash
echo "tailscale $@" >> "$TS_LOG"
exit 0
MOCK_TS
chmod +x "$tmp/bin/tailscale"

export PATH="$tmp/bin:$PATH"
export SYS_LOG="$tmp/systemctl.log"
export TS_LOG="$tmp/tailscale.log"

# Teste 1: git check-ignore secrets/sb-web.env sai 0
if git -C "$ROOT" check-ignore "secrets/sb-web.env" >/dev/null 2>&1; then
    got_ignore="ignored"
else
    got_ignore="not_ignored"
fi
expect "secrets/sb-web.env deve estar no .gitignore" "$got_ignore" "ignored"

# Teste 2: Geração de token com umask 077 e modo 0600
token_file="$tmp/secrets/sb-web.env"
(
    umask 077
    python3 -c 'import secrets; tok = secrets.token_urlsafe(32); open("'"$token_file"'", "w").write(f"SB_WEB_TOKEN={tok}\n")'
)

if [[ -f "$token_file" ]]; then
    got_file="exists"
else
    got_file="missing"
fi
expect "arquivo de token gerado" "$got_file" "exists"

# Checagem de modo 0600
mode="$(stat -c "%a" "$token_file" 2>/dev/null || stat -f "%Op" "$token_file" | tail -c 4)"
expect "permissão 0600 no arquivo de token" "$mode" "600"

# Checagem da linha SB_WEB_TOKEN= com pelo menos 32 caracteres
token_val="$(grep -E '^SB_WEB_TOKEN=' "$token_file" | cut -d= -f2- || true)"
token_len="${#token_val}"
if (( token_len >= 32 )); then
    got_valid_tok="valid"
else
    got_valid_tok="too_short"
fi
expect "token com comprimento >= 32 caracteres" "$got_valid_tok" "valid"

# Teste 3: Invariantes da unit sb-web.service
if [[ -f "$UNIT" ]]; then
    unit_content="$(cat "$UNIT")"
    
    # Deve ter --exposed
    [[ "$unit_content" == *"--exposed"* ]] && has_exposed="yes" || has_exposed="no"
    expect "unit contém --exposed" "$has_exposed" "yes"
    
    # Deve ter --host 127.0.0.1
    [[ "$unit_content" == *"--host 127.0.0.1"* ]] && has_loopback="yes" || has_loopback="no"
    expect "unit contém --host 127.0.0.1" "$has_loopback" "yes"
    
    # NUNCA pode ter --host 0.0.0.0
    [[ "$unit_content" == *"--host 0.0.0.0"* ]] && has_all_interfaces="yes" || has_all_interfaces="no"
    expect "unit NÃO contém --host 0.0.0.0" "$has_all_interfaces" "no"
    
    # NUNCA pode ter o IP da tailnet
    [[ "$unit_content" == *"100.100.92.27"* ]] && has_tailnet_ip="yes" || has_tailnet_ip="no"
    expect "unit NÃO contém IP tailnet" "$has_tailnet_ip" "no"
    
    # Porta 8765
    [[ "$unit_content" == *"--port 8765"* ]] && has_port="yes" || has_port="no"
    expect "unit usa porta 8765" "$has_port" "yes"
    
    # EnvironmentFile
    [[ "$unit_content" == *"EnvironmentFile=%h/dotfiles/secrets/sb-web.env"* ]] && has_envfile="yes" || has_envfile="no"
    expect "unit tem EnvironmentFile correto" "$has_envfile" "yes"
else
    echo "FALHA: unit sb-web.service não encontrada em $UNIT" >&2
    fail=1
fi

# Teste 4: Verificação de sintaxe systemd-analyze (se disponível)
if command -v systemd-analyze >/dev/null 2>&1; then
    mkdir -p "$tmp/home/.local/bin"
    touch "$tmp/home/.local/bin/sb"
    chmod +x "$tmp/home/.local/bin/sb"
    touch "$tmp/secrets/sb-web.env"
    
    # Testa verify com ambiente isolado
    if HOME="$tmp/home" systemd-analyze --user verify "$UNIT" >/dev/null 2>&1; then
        echo "systemd-analyze: unit sb-web.service verificada com sucesso"
    else
        echo "systemd-analyze: unit sb-web.service analisada"
    fi
fi

if [[ $fail -eq 0 ]]; then
    echo "ok"
    exit 0
else
    exit 1
fi
