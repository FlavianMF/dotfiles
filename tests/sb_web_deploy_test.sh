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

# Teste 2: Executa make sb-web-token diretamente (arquivo novo)
token_file="$tmp/secrets/sb-web.env"
make -s -C "$ROOT" sb-web-token SECRETS_DIR="$tmp/secrets" >/dev/null

if [[ -f "$token_file" ]]; then
    got_file="exists"
else
    got_file="missing"
fi
expect "arquivo de token gerado via make sb-web-token" "$got_file" "exists"

mode="$(stat -c "%a" "$token_file" 2>/dev/null || stat -f "%Op" "$token_file" | tail -c 4)"
expect "permissão 0600 no arquivo novo gerado via make" "$mode" "600"

token_val="$(grep -E '^SB_WEB_TOKEN=' "$token_file" | cut -d= -f2- || true)"
token_len="${#token_val}"
if (( token_len >= 32 )); then
    got_valid_tok="valid"
else
    got_valid_tok="too_short"
fi
expect "token gerado tem comprimento >= 32" "$got_valid_tok" "valid"

# Teste 3: Arquivo pré-existente com modo 0644 DEVE virar 0600 após rotação
chmod 644 "$token_file"
prev_mode="$(stat -c "%a" "$token_file" 2>/dev/null || stat -f "%Op" "$token_file" | tail -c 4)"
expect "token preparado com 644 para teste de rotação" "$prev_mode" "644"

make -s -C "$ROOT" sb-web-token SECRETS_DIR="$tmp/secrets" >/dev/null
after_mode="$(stat -c "%a" "$token_file" 2>/dev/null || stat -f "%Op" "$token_file" | tail -c 4)"
expect "arquivo rotacionado vira 0600 mesmo se antes era 0644" "$after_mode" "600"

# Teste 4: make sb-web-install com mock de systemctl
: > "$SYS_LOG"
make -s -C "$ROOT" sb-web-install SECRETS_DIR="$tmp/secrets" HOME="$tmp/home" >/dev/null

# Verifica criação do link da unit
unit_link="$tmp/home/.config/systemd/user/sb-web.service"
if [[ -L "$unit_link" ]]; then
    got_link="linked"
else
    got_link="missing"
fi
expect "sb-web-install cria symlink da unit" "$got_link" "linked"

# Verifica chamadas ao systemctl no log
sys_calls="$(cat "$SYS_LOG" 2>/dev/null || true)"
[[ "$sys_calls" == *"systemctl --user daemon-reload"* ]] && has_reload="yes" || has_reload="no"
expect "sb-web-install executa daemon-reload" "$has_reload" "yes"

[[ "$sys_calls" == *"systemctl --user enable --now sb-web.service"* ]] && has_enable="yes" || has_enable="no"
expect "sb-web-install executa enable --now sb-web.service" "$has_enable" "yes"

# Teste 5: sb-web-install falha se sb-web.env não existir
rm -f "$token_file"
if make -s -C "$ROOT" sb-web-install SECRETS_DIR="$tmp/secrets" HOME="$tmp/home" >/dev/null 2>&1; then
    install_no_token="succeeded"
else
    install_no_token="failed"
fi
expect "sb-web-install recusa instalação sem token" "$install_no_token" "failed"

# Teste 6: Invariantes da unit sb-web.service
if [[ -f "$UNIT" ]]; then
    unit_content="$(cat "$UNIT")"
    
    [[ "$unit_content" == *"--exposed"* ]] && has_exposed="yes" || has_exposed="no"
    expect "unit contém --exposed" "$has_exposed" "yes"
    
    [[ "$unit_content" == *"--host 127.0.0.1"* ]] && has_loopback="yes" || has_loopback="no"
    expect "unit contém --host 127.0.0.1" "$has_loopback" "yes"
    
    [[ "$unit_content" == *"--host 0.0.0.0"* ]] && has_all_interfaces="yes" || has_all_interfaces="no"
    expect "unit NÃO contém --host 0.0.0.0" "$has_all_interfaces" "no"
    
    [[ "$unit_content" == *"100.100.92.27"* ]] && has_tailnet_ip="yes" || has_tailnet_ip="no"
    expect "unit NÃO contém IP tailnet" "$has_tailnet_ip" "no"
    
    [[ "$unit_content" == *"--port 8765"* ]] && has_port="yes" || has_port="no"
    expect "unit usa porta 8765" "$has_port" "yes"
    
    [[ "$unit_content" == *"EnvironmentFile=%h/dotfiles/secrets/sb-web.env"* ]] && has_envfile="yes" || has_envfile="no"
    expect "unit tem EnvironmentFile correto" "$has_envfile" "yes"

    [[ "$unit_content" == *"RestartPreventExitStatus=2"* ]] && has_prevent="yes" || has_prevent="no"
    expect "unit tem RestartPreventExitStatus=2" "$has_prevent" "yes"
fi

if [[ $fail -eq 0 ]]; then
    echo "ok"
    exit 0
else
    exit 1
fi
