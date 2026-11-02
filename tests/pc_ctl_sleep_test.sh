#!/bin/bash
# Testes TDD de pc-ctl schedule-sleep, wake-check e wake-test rtc (só mocks, nada toca o Windows)
# Uso: bash tests/pc_ctl_sleep_test.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PC_CTL="$ROOT/bin/pc-ctl"
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

hasnt() {
    if grep -F -q -- "$2" <<<"$3"; then
        echo "❌ FALHA: $1 (não deveria conter '$2' em: $3)"
        fail=1
    else
        echo "✅ PASSOU: $1"
    fi
}

# ------------------------------------------------------------------------------
# Mocks: powershell.exe, schtasks.exe, curl, ps e sleep. Nenhum toca o Windows real.
# ------------------------------------------------------------------------------
MOCK_BIN="$tmp/mockbin"
WIN_SYS="$tmp/win/system32"
WIN_PS="$tmp/win/ps"
mkdir -p "$MOCK_BIN" "$WIN_SYS" "$WIN_PS"

export MOCK_ORDER="$tmp/order.log"        # ordem das chamadas (register, curl, eco, suspend...)
export MOCK_SCRIPTS="$tmp/ps_scripts.log"  # scripts PowerShell decodificados
export MOCK_PS_ARGS="$tmp/ps_args.log"     # argv cru do powershell.exe
export MOCK_SCHTASKS="$tmp/schtasks.log"
export MOCK_CURL_ARGS="$tmp/curl_args.log"
export MOCK_CURL_STDIN="$tmp/curl_stdin.log"
export MOCK_SLEEP_LOG="$tmp/sleep.log"
export PC_CTL_LOG_FILE="$tmp/sleep_audit.log"
export PC_CTL_REQUEST_FILE="$tmp/request.json"
export PC_CTL_ECO_SETTLE=0
export PC_CTL_HA_ENV="$tmp/mcp.env"
export WIN_SYS_DIR="$WIN_SYS"
export WIN_PS_DIR="$WIN_PS"
export PATH="$MOCK_BIN:$PATH"

TOKEN="TOKEN_SECRETO_123"
printf 'HOMEASSISTANT_URL=http://ha.test:8123\nHOMEASSISTANT_TOKEN=%s\n' "$TOKEN" >"$PC_CTL_HA_ENV"

cat >"$WIN_PS/powershell.exe" <<'MOCK'
#!/bin/bash
echo "$*" >>"$MOCK_PS_ARGS"
script="$*"
prev=""
for a in "$@"; do
    if [[ "$prev" == "-EncodedCommand" ]]; then
        script="$(python3 -c 'import base64,sys; print(base64.b64decode(sys.argv[1]).decode("utf-16-le"))' "$a")"
    fi
    prev="$a"
done
printf '%s\n--FIM--\n' "$script" >>"$MOCK_SCRIPTS"
case "$script" in
    *GetLastInputInfo*)
        echo "idle" >>"$MOCK_ORDER"
        echo "${MOCK_IDLE-900}"
        exit "${MOCK_IDLE_RC:-0}"
        ;;
    *PowerLineStatus*)
        echo "${MOCK_POWER:-Online}"
        exit "${MOCK_POWER_RC:-0}"
        ;;
    *Unregister-ScheduledTask*)
        echo "unregister" >>"$MOCK_ORDER"
        exit "${MOCK_UNREGISTER_RC:-0}"
        ;;
    *Register-ScheduledTask*)
        echo "register" >>"$MOCK_ORDER"
        exit "${MOCK_REGISTER_RC:-0}"
        ;;
    *SetSuspendState*)
        echo "suspend" >>"$MOCK_ORDER"
        exit "${MOCK_SUSPEND_RC:-0}"
        ;;
    *ToUnixTimeSeconds*)
        echo "epoch" >>"$MOCK_ORDER"
        # Fila de epochs em arquivo (cada chamada roda em outro processo): consome a primeira linha.
        if [[ -s "$MOCK_EPOCH_STATE" ]]; then
            head -n 1 "$MOCK_EPOCH_STATE"
            tail -n +2 "$MOCK_EPOCH_STATE" >"$MOCK_EPOCH_STATE.tmp"
            mv "$MOCK_EPOCH_STATE.tmp" "$MOCK_EPOCH_STATE"
        else
            date +%s
        fi
        exit 0
        ;;
esac
exit 0
MOCK
chmod +x "$WIN_PS/powershell.exe"

cat >"$WIN_SYS/schtasks.exe" <<'MOCK'
#!/bin/bash
echo "$*" >>"$MOCK_SCHTASKS"
echo "schtasks $*" >>"$MOCK_ORDER"
exit "${MOCK_SCHTASKS_RC:-0}"
MOCK
chmod +x "$WIN_SYS/schtasks.exe"

cat >"$MOCK_BIN/curl" <<'MOCK'
#!/bin/bash
echo "$*" >>"$MOCK_CURL_ARGS"
echo "curl" >>"$MOCK_ORDER"
cat >>"$MOCK_CURL_STDIN" 2>/dev/null || true
exit "${MOCK_CURL_RC:-0}"
MOCK
chmod +x "$MOCK_BIN/curl"

cat >"$MOCK_BIN/ps" <<'MOCK'
#!/bin/bash
[[ "${MOCK_PS_RC:-0}" -eq 0 ]] || exit "$MOCK_PS_RC"
printf '%s\n' "  1 systemd /sbin/init" "  200 bash -bash" "  300 nvim nvim makefile.txt" "  400 dockerd /usr/bin/dockerd -H fd://"
[[ -n "${MOCK_PROCS:-}" ]] && printf '%s\n' "$MOCK_PROCS"
exit 0
MOCK
chmod +x "$MOCK_BIN/ps"

cat >"$MOCK_BIN/sleep" <<'MOCK'
#!/bin/bash
echo "$*" >>"$MOCK_SLEEP_LOG"
exit 0
MOCK
chmod +x "$MOCK_BIN/sleep"

reset_mocks() {
    rm -f "$MOCK_ORDER" "$MOCK_SCRIPTS" "$MOCK_PS_ARGS" "$MOCK_SCHTASKS" "$MOCK_CURL_ARGS" \
        "$MOCK_CURL_STDIN" "$MOCK_SLEEP_LOG" "$PC_CTL_LOG_FILE" "$PC_CTL_REQUEST_FILE" "$MOCK_EPOCH_STATE"
    : >"$MOCK_ORDER"
    unset MOCK_IDLE MOCK_IDLE_RC MOCK_POWER MOCK_POWER_RC MOCK_REGISTER_RC MOCK_UNREGISTER_RC MOCK_SUSPEND_RC \
        MOCK_CURL_RC MOCK_PS_RC MOCK_PROCS MOCK_SCHTASKS_RC
}
export MOCK_EPOCH_STATE="$tmp/epoch.state"

count() { grep -c -x -- "$1" "$MOCK_ORDER" 2>/dev/null || true; }
last_log() { tail -n 1 "$PC_CTL_LOG_FILE" 2>/dev/null || true; }
log_field() { jq -r ".$1" <<<"$(last_log)"; }
all_scripts() { cat "$MOCK_SCRIPTS" 2>/dev/null || true; }

iso_in() { date -u -d "+$1" +%Y-%m-%dT%H:%M:%SZ; }

if [[ ! -x "$PC_CTL" ]]; then
    echo "❌ FALHA: bin/pc-ctl não existe ou não é executável"
    exit 1
fi

# ==============================================================================
# 1. schedule-sleep: ajuda e validação do until
# ==============================================================================
out="$(bash "$PC_CTL" --help 2>&1)"
has "help lista schedule-sleep" "schedule-sleep" "$out"
has "help lista wake-check" "wake-check" "$out"
has "help lista wake-test wol|rtc" "wake-test wol|rtc" "$out"

reset_mocks
out="$(bash "$PC_CTL" schedule-sleep --agents-idle-checked 2>&1)"; rc=$?
expect "sem --until sai com 1" "$rc" "1"
has "sem --until explica o uso" "--until" "$out"
expect "sem --until não suspende" "$(count suspend)" "0"

reset_mocks
out="$(bash "$PC_CTL" schedule-sleep --until "isso-nao-e-data" --agents-idle-checked 2>&1)"; rc=$?
expect "--until inválido sai com 1" "$rc" "1"
expect "--until inválido grava refused" "$(log_field result)" "refused"
expect "--until inválido grava o motivo" "$(log_field reason)" "until_invalid"
expect "--until inválido não suspende" "$(count suspend)" "0"

reset_mocks
past="$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)"
out="$(bash "$PC_CTL" schedule-sleep --until "$past" --agents-idle-checked 2>&1)"; rc=$?
expect "until no passado sai com 1" "$rc" "1"
expect "until no passado grava refused" "$(log_field result)" "refused"
expect "until no passado grava o motivo" "$(log_field reason)" "until_past"
expect "until no passado não registra tarefa" "$(count register)" "0"
expect "until no passado não suspende" "$(count suspend)" "0"

reset_mocks
short="$(iso_in '20 minutes')"
out="$(bash "$PC_CTL" schedule-sleep --until "$short" --agents-idle-checked 2>&1)"; rc=$?
expect "pausa de 20 minutos sai com 1" "$rc" "1"
expect "pausa de 20 minutos grava refused" "$(log_field result)" "refused"
expect "pausa de 20 minutos grava o motivo" "$(log_field reason)" "pause_too_short"
has "pausa de 20 minutos explica o mínimo" "30" "$out"
expect "pausa de 20 minutos não registra tarefa" "$(count register)" "0"
expect "pausa de 20 minutos não suspende" "$(count suspend)" "0"

# Até com --dry-run a validação do until recusa
reset_mocks
out="$(bash "$PC_CTL" --dry-run schedule-sleep --until "$short" --agents-idle-checked 2>&1)"; rc=$?
expect "dry-run com pausa de 20 minutos sai com 1" "$rc" "1"
expect "dry-run com pausa de 20 minutos grava refused" "$(log_field result)" "refused"

# ==============================================================================
# 2. schedule-sleep: travas (falham fechado)
# ==============================================================================
UNTIL="$(iso_in '2 hours')"
WAKE_AT="$(date -u -d "$UNTIL -5 minutes" +%Y-%m-%dT%H:%M:%SZ)"

assert_blocked() {
    local label="$1" reason="$2"
    expect "$label: sai com código diferente de zero" "$([[ $rc -ne 0 ]] && echo ok || echo "rc=$rc")" "ok"
    expect "$label: grava refused" "$(log_field result)" "refused"
    expect "$label: grava o motivo" "$(log_field reason)" "$reason"
    expect "$label: não registra tarefa" "$(count register)" "0"
    expect "$label: não publica no MQTT" "$(count curl)" "0"
    expect "$label: não suspende" "$(count suspend)" "0"
}

reset_mocks
out="$(bash "$PC_CTL" schedule-sleep --until "$UNTIL" 2>&1)"; rc=$?
assert_blocked "sem --agents-idle-checked" "agents_not_checked"
has "sem --agents-idle-checked explica a flag" "--agents-idle-checked" "$out"

reset_mocks
out="$(MOCK_IDLE=599 bash "$PC_CTL" schedule-sleep --until "$UNTIL" --agents-idle-checked 2>&1)"; rc=$?
assert_blocked "ocioso há 599s" "idle_too_short"

reset_mocks
out="$(MOCK_IDLE=600 bash "$PC_CTL" schedule-sleep --until "$UNTIL" --agents-idle-checked 2>&1)"; rc=$?
expect "ocioso há 600s passa na trava (limite inclusivo)" "$(count suspend)" "1"

reset_mocks
out="$(MOCK_IDLE_RC=1 bash "$PC_CTL" schedule-sleep --until "$UNTIL" --agents-idle-checked 2>&1)"; rc=$?
assert_blocked "powershell de ociosidade falha (falha fechada)" "idle_unknown"

reset_mocks
out="$(MOCK_IDLE="" bash "$PC_CTL" schedule-sleep --until "$UNTIL" --agents-idle-checked 2>&1)"; rc=$?
assert_blocked "ociosidade sem saída (falha fechada)" "idle_unknown"

reset_mocks
out="$(MOCK_IDLE="Exception: algo" bash "$PC_CTL" schedule-sleep --until "$UNTIL" --agents-idle-checked 2>&1)"; rc=$?
assert_blocked "ociosidade com saída não numérica (falha fechada)" "idle_unknown"

for proc in "500 make make test" "501 cargo cargo build --release" "502 npm npm run build" "503 pnpm pnpm install" \
    "504 go go build ./..." "505 docker docker build ." "506 docker docker compose up" "507 docker-compose docker-compose up"; do
    reset_mocks
    out="$(MOCK_PROCS="$proc" bash "$PC_CTL" schedule-sleep --until "$UNTIL" --agents-idle-checked 2>&1)"; rc=$?
    assert_blocked "build ativo '${proc#* }'" "build_active"
done

reset_mocks
out="$(MOCK_PROCS="$(printf '600 docker docker ps\n601 go go version\n602 vim vim Makefile')" bash "$PC_CTL" schedule-sleep --until "$UNTIL" --agents-idle-checked 2>&1)"; rc=$?
expect "containers parados, serviços e editores não contam como build" "$(count suspend)" "1"

reset_mocks
out="$(MOCK_PS_RC=1 bash "$PC_CTL" schedule-sleep --until "$UNTIL" --agents-idle-checked 2>&1)"; rc=$?
assert_blocked "não conseguiu listar processos (falha fechada)" "build_unknown"

reset_mocks
out="$(MOCK_POWER=Unknown bash "$PC_CTL" schedule-sleep --until "$UNTIL" --agents-idle-checked 2>&1)"; rc=$?
assert_blocked "energia Unknown (falha fechada)" "power_unknown"

reset_mocks
out="$(MOCK_POWER_RC=1 bash "$PC_CTL" schedule-sleep --until "$UNTIL" --agents-idle-checked 2>&1)"; rc=$?
assert_blocked "powershell de energia falha (falha fechada)" "power_unknown"

reset_mocks
out="$(PC_CTL_HA_ENV="$tmp/nao-existe.env" HOMEASSISTANT_TOKEN="" bash "$PC_CTL" schedule-sleep --until "$UNTIL" --agents-idle-checked 2>&1)"; rc=$?
assert_blocked "sem token do Home Assistant" "no_ha_token"

# ==============================================================================
# 3. schedule-sleep: caminho feliz com mocks (S3 na tomada)
# ==============================================================================
reset_mocks
out="$(bash "$PC_CTL" schedule-sleep --until "$UNTIL" --agents-idle-checked 2>&1)"; rc=$?
expect "caminho feliz sai com 0" "$rc" "0"
expect "caminho feliz suspende uma vez" "$(count suspend)" "1"
scripts="$(all_scripts)"
has "suspende em S3 na tomada" "SetSuspendState('Suspend', \$false, \$false)" "$scripts"
hasnt "não hiberna na tomada" "'Hibernate'" "$scripts"
expect "ordem: ociosidade, tarefa de wake, MQTT, eco, suspensão" \
    "$(grep -E '^(idle|register|curl|schtasks /run /tn pc-ctl-power|suspend)$' "$MOCK_ORDER" | tr '\n' ',')" \
    "idle,register,curl,schtasks /run /tn pc-ctl-power,suspend,"
expect "pede o perfil eco" "$(jq -r '.profile' "$PC_CTL_REQUEST_FILE")" "eco"
has "tarefa se chama pc-ctl-wake" "'pc-ctl-wake'" "$scripts"
has "tarefa usa Register-ScheduledTask" "Register-ScheduledTask" "$scripts"
has "tarefa usa gatilho -Once -At" "New-ScheduledTaskTrigger -Once -At" "$scripts"
has "tarefa liga WakeToRun" "-WakeToRun" "$scripts"
has "wake é until menos 5 minutos" "$WAKE_AT" "$scripts"
has "a data entra no PowerShell com cultura invariante" "InvariantCulture" "$scripts"
curl_args="$(cat "$MOCK_CURL_ARGS")"
has "publica pela API do Home Assistant" "http://ha.test:8123/api/services/mqtt/publish" "$curl_args"
has "publica no tópico sleeping_until" "pc/loq/sleeping_until" "$curl_args"
has "publica com retain true" '"retain": true' "$curl_args"
has "payload tem until" "$UNTIL" "$(jq -r '.payload' <<<"$(sed -n 's/.* -d //p' "$MOCK_CURL_ARGS")")"
payload="$(jq -r '.payload' <<<"$(sed -n 's/.* -d //p' "$MOCK_CURL_ARGS")")"
expect "payload mode=s3" "$(jq -r '.mode' <<<"$payload")" "s3"
expect "payload until" "$(jq -r '.until' <<<"$payload")" "$UNTIL"
has "payload tem set_at" "T" "$(jq -r '.set_at' <<<"$payload")"
hasnt "o token nunca vai no argv do curl" "$TOKEN" "$curl_args"
has "o token vai por stdin (--config -)" "$TOKEN" "$(cat "$MOCK_CURL_STDIN")"
hasnt "o token nunca vai no log" "$TOKEN" "$(cat "$PC_CTL_LOG_FILE")"
hasnt "o token nunca vai na saída" "$TOKEN" "$out"
hasnt "o token nunca vai no argv do powershell" "$TOKEN" "$(cat "$MOCK_PS_ARGS")"
expect "grava requested antes de suspender" "$(jq -r 'select(.cmd=="schedule-sleep") | .result' "$PC_CTL_LOG_FILE" | tr '\n' ',')" "requested,applied,"
expect "grava o until normalizado no log" "$(jq -r 'select(.cmd=="schedule-sleep") | .until' "$PC_CTL_LOG_FILE" | tail -n1)" "$UNTIL"

# Lições do Sprint 06: nada de /mnt/, schtasks /create, schtasks /sd, Out-Null engolindo erro
all_ps="$(all_scripts)$(cat "$MOCK_PS_ARGS")"
hasnt "nenhum argumento ao Windows tem /mnt/" "/mnt/" "$all_ps"
hasnt "não usa schtasks /sd (depende da localidade)" "/sd" "$all_ps"
hasnt "não usa schtasks /create" "/create" "$all_ps$(cat "$MOCK_SCHTASKS")"
if grep -E 'Register-ScheduledTask[^\n]*\|[[:space:]]*Out-Null' <<<"$scripts" >/dev/null; then
    echo "❌ FALHA: Register-ScheduledTask com | Out-Null engole erro"
    fail=1
else
    echo "✅ PASSOU: Register-ScheduledTask não passa por Out-Null"
fi
has "script de registro trata erro e sai com código diferente de zero" "exit 1" "$scripts"
has "script de registro para no primeiro erro" "ErrorActionPreference = 'Stop'" "$scripts"

# Na bateria, hiberna
reset_mocks
out="$(MOCK_POWER=Offline bash "$PC_CTL" schedule-sleep --until "$UNTIL" --agents-idle-checked 2>&1)"; rc=$?
expect "na bateria sai com 0" "$rc" "0"
expect "na bateria suspende uma vez" "$(count suspend)" "1"
scripts="$(all_scripts)"
has "na bateria hiberna" "SetSuspendState('Hibernate', \$false, \$false)" "$scripts"
hasnt "na bateria não usa S3" "'Suspend'" "$scripts"
payload="$(jq -r '.payload' <<<"$(sed -n 's/.* -d //p' "$MOCK_CURL_ARGS")")"
expect "na bateria payload mode=hibernate" "$(jq -r '.mode' <<<"$payload")" "hibernate"

# ==============================================================================
# 4. schedule-sleep: falhas depois das travas nunca suspendem e desfazem o estado
# ==============================================================================
reset_mocks
out="$(MOCK_REGISTER_RC=1 bash "$PC_CTL" schedule-sleep --until "$UNTIL" --agents-idle-checked 2>&1)"; rc=$?
expect "falha ao registrar a tarefa sai com 1" "$rc" "1"
expect "falha ao registrar a tarefa não suspende" "$(count suspend)" "0"
expect "falha ao registrar a tarefa não publica no MQTT" "$(count curl)" "0"
expect "falha ao registrar a tarefa grava failed" "$(log_field result)" "failed"
expect "falha ao registrar a tarefa grava o motivo" "$(log_field reason)" "wake_task_failed"

reset_mocks
out="$(MOCK_CURL_RC=22 bash "$PC_CTL" schedule-sleep --until "$UNTIL" --agents-idle-checked 2>&1)"; rc=$?
expect "falha no MQTT sai com 1" "$rc" "1"
expect "falha no MQTT não suspende" "$(count suspend)" "0"
expect "falha no MQTT desfaz a tarefa de wake" "$(count unregister)" "1"
expect "falha no MQTT grava failed" "$(log_field result)" "failed"
expect "falha no MQTT grava o motivo" "$(log_field reason)" "mqtt_publish_failed"

reset_mocks
out="$(MOCK_SCHTASKS_RC=1 bash "$PC_CTL" schedule-sleep --until "$UNTIL" --agents-idle-checked 2>&1)"; rc=$?
expect "falha ao pedir o perfil eco sai com 1" "$rc" "1"
expect "falha ao pedir o perfil eco não suspende" "$(count suspend)" "0"
expect "falha ao pedir o perfil eco desfaz a tarefa de wake" "$(count unregister)" "1"
expect "falha ao pedir o perfil eco limpa o estado retido (2 publicações)" "$(count curl)" "2"
expect "falha ao pedir o perfil eco grava failed" "$(jq -r 'select(.cmd=="schedule-sleep") | .result' "$PC_CTL_LOG_FILE" | tail -n1)" "failed"
expect "falha ao pedir o perfil eco grava o motivo" "$(jq -r 'select(.cmd=="schedule-sleep") | .reason' "$PC_CTL_LOG_FILE" | tail -n1)" "power_mode_failed"

reset_mocks
out="$(MOCK_SUSPEND_RC=1 bash "$PC_CTL" schedule-sleep --until "$UNTIL" --agents-idle-checked 2>&1)"; rc=$?
expect "falha ao suspender sai com 1" "$rc" "1"
expect "falha ao suspender desfaz a tarefa de wake" "$(count unregister)" "1"
expect "falha ao suspender limpa o estado retido (2 publicações)" "$(count curl)" "2"
expect "falha ao suspender grava failed" "$(log_field result)" "failed"
expect "falha ao suspender grava o motivo" "$(log_field reason)" "suspend_failed"
has "o script de suspensão checa o retorno de SetSuspendState" "-eq \$false" "$(all_scripts)"

# ==============================================================================
# 5. schedule-sleep --dry-run: plano completo, nunca suspende
# ==============================================================================
reset_mocks
out="$(bash "$PC_CTL" --dry-run schedule-sleep --until "$UNTIL" --agents-idle-checked 2>&1)"; rc=$?
expect "dry-run sai com 0" "$rc" "0"
has "dry-run mostra a trava de ociosidade" "ociosidade" "$out"
has "dry-run mostra a trava de build" "build" "$out"
has "dry-run mostra o modo" "s3" "$out"
has "dry-run mostra a tarefa pc-ctl-wake" "pc-ctl-wake" "$out"
has "dry-run mostra a hora do wake" "$WAKE_AT" "$out"
has "dry-run mostra o tópico MQTT" "pc/loq/sleeping_until" "$out"
has "dry-run mostra retain" "retain" "$out"
has "dry-run mostra o payload" "\"mode\": \"s3\"" "$out"
has "dry-run mostra o perfil eco" "power-mode eco" "$out"
has "dry-run mostra a chamada de suspensão" "SetSuspendState('Suspend'" "$out"
hasnt "dry-run não mostra o token" "$TOKEN" "$out"
expect "dry-run não registra tarefa" "$(count register)" "0"
expect "dry-run não publica" "$(count curl)" "0"
expect "dry-run não suspende" "$(count suspend)" "0"
expect "dry-run não pede o perfil" "$(count 'schtasks /run /tn pc-ctl-power')" "0"
expect "dry-run grava dry-run no log" "$(jq -r 'select(.cmd=="schedule-sleep") | .result' "$PC_CTL_LOG_FILE" | tail -n1)" "dry-run"

reset_mocks
out="$(MOCK_POWER=Offline bash "$PC_CTL" --dry-run schedule-sleep --until "$UNTIL" --agents-idle-checked 2>&1)"; rc=$?
has "dry-run na bateria mostra hibernate" "SetSuspendState('Hibernate'" "$out"

reset_mocks
out="$(MOCK_IDLE=30 bash "$PC_CTL" --dry-run schedule-sleep --until "$UNTIL" --agents-idle-checked 2>&1)"; rc=$?
expect "dry-run com trava falhando sai com 1" "$rc" "1"
has "dry-run com trava falhando ainda mostra o plano" "pc-ctl-wake" "$out"
has "dry-run com trava falhando diz que recusaria" "idle_too_short" "$out"
expect "dry-run com trava falhando não suspende" "$(count suspend)" "0"
expect "dry-run com trava falhando não registra tarefa" "$(count register)" "0"

echo "----------------------------------------"
if [[ $fail -eq 0 ]]; then
    echo "🎉 Todos os testes de schedule-sleep/wake-check/wake-test rtc PASSARAM!"
else
    echo "💥 Foram encontradas falhas no teste TDD."
fi
exit $fail
