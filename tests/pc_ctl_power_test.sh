#!/bin/bash
# Testes TDD de lib/pc-ctl-log.sh e subcomandos de energia do bin/pc-ctl
# Uso: bash tests/pc_ctl_power_test.sh
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

# ==============================================================================
# 1. Testes do módulo lib/pc-ctl-log.sh
# ==============================================================================
LOG_LIB="$ROOT/lib/pc-ctl-log.sh"
if [[ ! -f "$LOG_LIB" ]]; then
    echo "❌ FALHA: lib/pc-ctl-log.sh não existe (fase RED do TDD)"
    echo "Fim dos testes: 1 falha(s)"
    exit 1
fi

# shellcheck source=/dev/null
source "$LOG_LIB"

test_log="$tmp/test_sleep.log"
export PC_CTL_LOG_FILE="$test_log"

# Teste 1.1: Log completo
pc_ctl_log --cmd "power-mode" --result "applied" --profile "llm-boost" --reason "ok" --until "2026-11-01T20:00:00Z"

if [[ ! -f "$test_log" ]]; then
    echo "❌ FALHA: arquivo de log não foi criado em $test_log"
    fail=1
else
    line="$(tail -n 1 "$test_log")"
    cmd_val="$(jq -r '.cmd' <<<"$line")"
    result_val="$(jq -r '.result' <<<"$line")"
    profile_val="$(jq -r '.profile' <<<"$line")"
    reason_val="$(jq -r '.reason' <<<"$line")"
    until_val="$(jq -r '.until' <<<"$line")"
    ts_val="$(jq -r '.ts' <<<"$line")"

    expect "log registra cmd=power-mode" "$cmd_val" "power-mode"
    expect "log registra result=applied" "$result_val" "applied"
    expect "log registra profile=llm-boost" "$profile_val" "llm-boost"
    expect "log registra reason=ok" "$reason_val" "ok"
    expect "log registra until" "$until_val" "2026-11-01T20:00:00Z"
    has "log registra timestamp ISO 8601" "T" "$ts_val"
fi

# Teste 1.2: Log com campos opcionais nulos
pc_ctl_log --cmd "wake-setup" --result "dry-run" --reason "dry_run"
line2="$(tail -n 1 "$test_log")"
profile_val2="$(jq -r '.profile' <<<"$line2")"
until_val2="$(jq -r '.until' <<<"$line2")"
expect "campo profile ausente vira null no JSON" "$profile_val2" "null"
expect "campo until ausente vira null no JSON" "$until_val2" "null"

# Teste 1.3: Validação do valor de result (applied|refused|failed|dry-run)
rc_invalid=0
pc_ctl_log --cmd "power-mode" --result "invalido" 2>/dev/null || rc_invalid=$?
if [[ "$rc_invalid" -ne 0 ]]; then
    echo "✅ PASSOU: result inválido rejeitado com erro"
else
    echo "❌ FALHA: result inválido deveria ter retornado erro"
    fail=1
fi


# ==============================================================================
# 2. Testes dos scripts PowerShell do Windows (powershell/pc-ctl/)
# ==============================================================================
SET_POWER_PS="$ROOT/powershell/pc-ctl/Set-PowerProfile.ps1"
INSTALL_PS="$ROOT/powershell/pc-ctl/Install-PcCtl.ps1"

if [[ ! -f "$SET_POWER_PS" ]]; then
    echo "❌ FALHA: powershell/pc-ctl/Set-PowerProfile.ps1 não existe (fase RED do TDD)"
    fail=1
else
    ps_content="$(cat "$SET_POWER_PS")"
    has "Set-PowerProfile suporta eco" "eco" "$ps_content"
    has "Set-PowerProfile suporta balanced" "balanced" "$ps_content"
    has "Set-PowerProfile suporta llm-boost" "llm-boost" "$ps_content"
    has "Set-PowerProfile suporta max" "max" "$ps_content"
    has "Set-PowerProfile le request.json" "request.json" "$ps_content"
    has "Set-PowerProfile checa PowerLineStatus na bateria" "PowerLineStatus" "$ps_content"
    has "Set-PowerProfile agenda pc-ctl-power-revert" "pc-ctl-power-revert" "$ps_content"
    has "Set-PowerProfile grava state.json" "state.json" "$ps_content"
    has "Set-PowerProfile reaproveita Set-LenovoLlmBoost" "Set-LenovoLlmBoost.ps1" "$ps_content"
fi

if [[ ! -f "$INSTALL_PS" ]]; then
    echo "❌ FALHA: powershell/pc-ctl/Install-PcCtl.ps1 não existe (fase RED do TDD)"
    fail=1
else
    inst_content="$(cat "$INSTALL_PS")"
    has "Install-PcCtl instala em ProgramData" "ProgramData\\pc-ctl" "$inst_content"
    has "Install-PcCtl ajusta ACL via icacls" "icacls" "$inst_content"
    has "Install-PcCtl concede escrita para Users em request.json" "request.json" "$inst_content"

    # Windows pt-BR: nomes de grupo em inglês não existem. O icacls deve usar SIDs.
    icacls_lines="$(grep -iE '^[^#]*icacls' "$INSTALL_PS" || true)"
    has "Install-PcCtl usa SID de Administradores no icacls" '*S-1-5-32-544' "$icacls_lines"
    has "Install-PcCtl usa SID de SYSTEM no icacls" '*S-1-5-18' "$icacls_lines"
    has "Install-PcCtl usa SID de Usuarios no icacls" '*S-1-5-32-545' "$icacls_lines"
    if grep -qE '(^|[^A-Za-z])(Administrators|SYSTEM|Users):' <<<"$icacls_lines"; then
        echo "❌ FALHA: icacls usa nome de grupo em inglês (quebra no Windows pt-BR)"
        fail=1
    else
        echo "✅ PASSOU: icacls não usa nomes de grupo em inglês"
    fi
    if grep -q 'Out-Null' <<<"$icacls_lines"; then
        echo "❌ FALHA: icacls engole a saída com Out-Null"
        fail=1
    else
        echo "✅ PASSOU: icacls não engole erro com Out-Null"
    fi
    lastexit_count="$(grep -c 'LASTEXITCODE' "$INSTALL_PS" || true)"
    if [[ "$lastexit_count" -ge 2 ]]; then
        echo "✅ PASSOU: Install-PcCtl checa LASTEXITCODE depois de cada icacls"
    else
        echo "❌ FALHA: Install-PcCtl deve checar LASTEXITCODE depois de cada icacls (achou $lastexit_count)"
        fail=1
    fi
fi


# ==============================================================================
# 3. Testes do subcomando wake-setup do bin/pc-ctl
# ==============================================================================
# 3.1 Help exibe wake-setup
out_help="$(bash "$ROOT/bin/pc-ctl" --help 2>&1)"
has "help lista wake-setup" "wake-setup" "$out_help"

# 3.2 Dry-run do wake-setup
out_wake_dry="$(bash "$ROOT/bin/pc-ctl" --dry-run wake-setup 2>&1)"
has "dry-run wake-setup invoca Install-PcCtl.ps1" "Install-PcCtl.ps1" "$out_wake_dry"
has "dry-run wake-setup habilita timers na tomada (AC)" "/setacvalueindex" "$out_wake_dry"
has "dry-run wake-setup habilita timers na bateria (DC)" "/setdcvalueindex" "$out_wake_dry"
has "dry-run wake-setup referencia SUB_SLEEP" "SUB_SLEEP" "$out_wake_dry"
has "dry-run wake-setup referencia GUID do wake timer" "BD3B718A-0680-4D9D-8AB2-E1D2B4AC806D" "$out_wake_dry"
has "dry-run wake-setup registra schtasks pc-ctl-power" "pc-ctl-power" "$out_wake_dry"
has "dry-run wake-setup usa HIGHEST" "HIGHEST" "$out_wake_dry"

line_wake_dry="$(tail -n 1 "$test_log")"
expect "log wake-setup dry-run cmd" "$(jq -r '.cmd' <<<"$line_wake_dry")" "wake-setup"
expect "log wake-setup dry-run result" "$(jq -r '.result' <<<"$line_wake_dry")" "dry-run"

# 3.3 Execução com mocks de sistema
mock_win="$tmp/mock_win"
mkdir -p "$mock_win"
cat >"$mock_win/powershell.exe" <<'MOCK'
#!/bin/bash
echo "MOCK_PS $*"
MOCK
cat >"$mock_win/powercfg.exe" <<'MOCK'
#!/bin/bash
echo "MOCK_POWERCFG $*"
MOCK
cat >"$mock_win/schtasks.exe" <<'MOCK'
#!/bin/bash
echo "MOCK_SCHTASKS $*"
MOCK
chmod +x "$mock_win/"*.exe

out_wake_mock="$(WIN_SYS_DIR="$mock_win" WIN_PS_DIR="$mock_win" bash "$ROOT/bin/pc-ctl" wake-setup 2>&1)"
has "wake-setup mock chama powershell Install-PcCtl" "MOCK_PS" "$out_wake_mock"
has "wake-setup mock chama powercfg" "MOCK_POWERCFG" "$out_wake_mock"
has "wake-setup mock chama schtasks create" "MOCK_SCHTASKS /create" "$out_wake_mock"

line_wake_applied="$(tail -n 1 "$test_log")"
expect "log wake-setup applied cmd" "$(jq -r '.cmd' <<<"$line_wake_applied")" "wake-setup"
expect "log wake-setup applied result" "$(jq -r '.result' <<<"$line_wake_applied")" "applied"


# ==============================================================================
# 4. Testes do subcomando power-mode do bin/pc-ctl
# ==============================================================================
# 4.1 Help exibe power-mode
out_help_pwr="$(bash "$ROOT/bin/pc-ctl" --help 2>&1)"
has "help lista power-mode" "power-mode" "$out_help_pwr"

# 4.2 Validações de argumento do power-mode
rc_no_prof=0
out_no_prof="$(bash "$ROOT/bin/pc-ctl" power-mode 2>&1)" || rc_no_prof=$?
expect "power-mode sem perfil sai com 1" "$rc_no_prof" "1"
has "power-mode sem perfil lista perfis validos" "eco, balanced, llm-boost, max, status" "$out_no_prof"

rc_inv_prof=0
out_inv_prof="$(bash "$ROOT/bin/pc-ctl" power-mode perfil_invalido 2>&1)" || rc_inv_prof=$?
expect "power-mode com perfil invalido sai com 1" "$rc_inv_prof" "1"
has "power-mode com perfil invalido exibe mensagem" "Perfil desconhecido" "$out_inv_prof"

# 4.3 Dry-run com llm-boost e TTL 90m
out_dry_pwr="$(PC_CTL_MOCK_POWER_LINE="Online" bash "$ROOT/bin/pc-ctl" --dry-run power-mode llm-boost --ttl 90m 2>&1)"
has "dry-run power-mode mostra escrita de request.json" "request.json" "$out_dry_pwr"
has "dry-run power-mode mostra perfil llm-boost" "llm-boost" "$out_dry_pwr"
has "dry-run power-mode mostra ttl 90" "90" "$out_dry_pwr"
has "dry-run power-mode executa schtasks run pc-ctl-power" "schtasks" "$out_dry_pwr"
has "dry-run power-mode roda pc-ctl-power" "pc-ctl-power" "$out_dry_pwr"

line_pwr_dry="$(tail -n 1 "$test_log")"
expect "log dry-run power-mode cmd" "$(jq -r '.cmd' <<<"$line_pwr_dry")" "power-mode"
expect "log dry-run power-mode result" "$(jq -r '.result' <<<"$line_pwr_dry")" "dry-run"
expect "log dry-run power-mode profile" "$(jq -r '.profile' <<<"$line_pwr_dry")" "llm-boost"

# 4.4 Validação de TTL acima do teto de 4 horas (240m)
rc_ttl_ceil=0
out_ttl_ceil="$(PC_CTL_MOCK_POWER_LINE="Online" bash "$ROOT/bin/pc-ctl" power-mode max --ttl 5h 2>&1)" || rc_ttl_ceil=$?
expect "TTL acima do teto de 4h sai com 1" "$rc_ttl_ceil" "1"
has "mensagem de TTL acima do teto" "240" "$out_ttl_ceil"

line_ttl_ceil="$(tail -n 1 "$test_log")"
expect "log ttl excedido result" "$(jq -r '.result' <<<"$line_ttl_ceil")" "refused"
expect "log ttl excedido reason" "$(jq -r '.reason' <<<"$line_ttl_ceil")" "ttl_exceeded"

# 4.5 Bloqueio quando na bateria (mock Offline)
rc_bat_max=0
out_bat_max="$(PC_CTL_MOCK_POWER_LINE="Offline" bash "$ROOT/bin/pc-ctl" power-mode max 2>&1)" || rc_bat_max=$?
expect "power-mode max na bateria sai com 1" "$rc_bat_max" "1"
has "mensagem de recusa na bateria" "bateria" "$out_bat_max"

line_bat_max="$(tail -n 1 "$test_log")"
expect "log bateria max result" "$(jq -r '.result' <<<"$line_bat_max")" "refused"
expect "log bateria max reason" "$(jq -r '.reason' <<<"$line_bat_max")" "on_battery"
expect "log bateria max profile" "$(jq -r '.profile' <<<"$line_bat_max")" "max"

# 4.6 Perfis eco e balanced permitidos na bateria
out_bat_eco="$(PC_CTL_MOCK_POWER_LINE="Offline" bash "$ROOT/bin/pc-ctl" --dry-run power-mode eco 2>&1)"
has "eco permitido na bateria em dry-run" "request.json" "$out_bat_eco"

# 4.7 Execução com mock de schtasks e request.json
mock_req_dir="$tmp/progdata"
mkdir -p "$mock_req_dir"
mock_req_file="$mock_req_dir/request.json"

out_mock_run="$(PC_CTL_MOCK_POWER_LINE="Online" PC_CTL_REQUEST_FILE="$mock_req_file" WIN_SYS_DIR="$mock_win" bash "$ROOT/bin/pc-ctl" power-mode balanced 2>&1)"
has "execucao grava request.json" "solicitado com sucesso" "$out_mock_run"
if [[ -f "$mock_req_file" ]]; then
    expect "request.json contem balanced" "$(jq -r '.profile' "$mock_req_file")" "balanced"
    echo "✅ PASSOU: request.json gerado corretamente"
else
    echo "❌ FALHA: request.json não foi criado em $mock_req_file"
    fail=1
fi

line_applied_pwr="$(tail -n 1 "$test_log")"
expect "log power-mode applied cmd" "$(jq -r '.cmd' <<<"$line_applied_pwr")" "power-mode"
expect "log power-mode applied result" "$(jq -r '.result' <<<"$line_applied_pwr")" "applied"
expect "log power-mode applied profile" "$(jq -r '.profile' <<<"$line_applied_pwr")" "balanced"

# 4.8 Status do power-mode
mock_state_file="$mock_req_dir/state.json"
cat >"$mock_state_file" <<'JSON'
{
  "active_profile": "llm-boost",
  "applied_at": "2026-11-01T18:00:00Z",
  "ttl_minutes": 120,
  "expires_at": "2026-11-01T20:00:00Z"
}
JSON

out_pwr_status="$(PC_CTL_STATE_FILE="$mock_state_file" bash "$ROOT/bin/pc-ctl" power-mode status 2>&1)"
has "status exibe perfil ativo" "llm-boost" "$out_pwr_status"
has "status exibe TTL restante ou total" "120" "$out_pwr_status"

echo "----------------------------------------"
if [[ $fail -eq 0 ]]; then
    echo "🎉 Testes de lib/pc-ctl-log.sh PASSARAM!"
else
    echo "💥 Foram encontradas $fail falhas no teste TDD."
fi
exit $fail
