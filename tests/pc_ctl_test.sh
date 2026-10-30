#!/bin/bash
# Testes TDD de bin/pc-ctl (unitário e dry-run sem tocar no hardware)
# Uso: bash tests/pc_ctl_test.sh
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
    if ! grep -q -- "$2" <<<"$3"; then
        echo "❌ FALHA: $1 (faltou '$2' em: $3)"
        fail=1
    else
        echo "✅ PASSOU: $1"
    fi
}

mkdir -p "$tmp/bin" "$tmp/windows/system32"
export PATH="$tmp/bin:$PATH"

# 1. Teste de existência do script bin/pc-ctl
PC_CTL="$ROOT/bin/pc-ctl"
if [[ ! -f "$PC_CTL" ]]; then
    echo "❌ FALHA: bin/pc-ctl não existe ainda (fase RED do TDD)"
    echo "Fim dos testes: $fail falha(s)"
    exit 1
fi

if [[ ! -x "$PC_CTL" ]]; then
    echo "❌ FALHA: bin/pc-ctl não tem permissão de execução"
    fail=1
fi

# 2. Testes de Ajuda / Help
out="$(bash "$PC_CTL" --help 2>&1)"
has "help exibe uso" "Uso: pc-ctl" "$out"
has "help lista shutdown" "shutdown" "$out"
has "help lista restart" "restart" "$out"
has "help lista sleep" "sleep" "$out"
has "help lista lock" "lock" "$out"
has "help lista app" "app <nome>" "$out"
has "help lista status" "status" "$out"

out_empty="$(bash "$PC_CTL" 2>&1)"
rc_empty=$?
expect "chamada sem argumentos exibe erro e sai com 1" "$rc_empty" "1"
has "erro de comando obrigatorio" "Nenhum comando informado" "$out_empty"

# 3. Testes de Modo Dry-Run (Energia e Sessão)
out_sd="$(bash "$PC_CTL" --dry-run shutdown 2>&1)"
has "dry-run shutdown padrao" "shutdown.exe /s /t 10" "$out_sd"

out_sd_force="$(bash "$PC_CTL" --dry-run shutdown --force 2>&1)"
has "dry-run shutdown --force" "shutdown.exe /s /t 0 /f" "$out_sd_force"

out_abort="$(bash "$PC_CTL" --dry-run abort 2>&1)"
has "dry-run abort" "shutdown.exe /a" "$out_abort"

out_reboot="$(bash "$PC_CTL" --dry-run restart 2>&1)"
has "dry-run restart" "shutdown.exe /r /t 0 /f" "$out_reboot"

out_sleep="$(bash "$PC_CTL" --dry-run sleep 2>&1)"
has "dry-run sleep" "rundll32.exe powrprof.dll,SetSuspendState" "$out_sleep"

out_lock="$(bash "$PC_CTL" --dry-run lock 2>&1)"
has "dry-run lock" "rundll32.exe user32.dll,LockWorkStation" "$out_lock"

# 4. Testes de Launcher de Apps
out_app_obsidian="$(bash "$PC_CTL" --dry-run app obsidian 2>&1)"
has "dry-run app obsidian" "Start-Process obsidian" "$out_app_obsidian"

out_app_wt="$(bash "$PC_CTL" --dry-run app wt 2>&1)"
has "dry-run app wt" "Start-Process wt" "$out_app_wt"

out_app_invalid="$(bash "$PC_CTL" --dry-run app app_inexistente 2>&1)"
rc_app_invalid=$?
expect "app desconhecido sai com 1" "$rc_app_invalid" "1"
has "app desconhecido lista apps validos" "Aplicacao desconhecida" "$out_app_invalid"

# 5. Teste de comando invalido
out_invalid="$(bash "$PC_CTL" comando_inexistente 2>&1)"
rc_invalid=$?
expect "comando invalido sai com 1" "$rc_invalid" "1"
has "mensagem de comando invalido" "Comando desconhecido" "$out_invalid"

# 6. Teste de Mock de Execução Real (sem tocar em binários Windows)
# Criando binários mock em $tmp/windows/system32
cat >"$tmp/windows/system32/shutdown.exe" <<'MOCK'
#!/bin/bash
echo "MOCK_SHUTDOWN $*"
MOCK
chmod +x "$tmp/windows/system32/shutdown.exe"

out_mock="$(WIN_SYS_DIR="$tmp/windows/system32" bash "$PC_CTL" shutdown 2>&1)"
has "execucao com mock chama o binario simulado" "MOCK_SHUTDOWN /s /t 10" "$out_mock"

# 7. Teste de Status
out_status="$(bash "$PC_CTL" status 2>&1)"
has "status exibe cabecalho" "Status do Sistema" "$out_status"
has "status checa interoperabilidade Windows" "Windows Host" "$out_status"
has "status checa SSH" "SSH" "$out_status"

echo "----------------------------------------"
if [[ $fail -eq 0 ]]; then
    echo "🎉 Todos os testes de bin/pc-ctl PASSARAM!"
else
    echo "💥 Foram encontradas $fail falhas no teste TDD."
fi
exit $fail
