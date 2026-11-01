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

echo "----------------------------------------"
if [[ $fail -eq 0 ]]; then
    echo "🎉 Testes de lib/pc-ctl-log.sh PASSARAM!"
else
    echo "💥 Foram encontradas $fail falhas no teste TDD."
fi
exit $fail
