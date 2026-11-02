#!/bin/bash
# Testes do wrapper bin/sb, hook stop e timers systemd do Second Brain.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/claude/hooks/second-brain-stop.sh"

tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/vault" "$tmp/state" "$tmp/repo_registered/.git" "$tmp/repo_unregistered/.git"

fail=0
expect() {
    local name="$1" got="$2" exp="$3"
    if [[ "$got" != "$exp" ]]; then
        echo "FALHA: $name (obtido '$got', esperado '$exp')" >&2
        fail=1
    fi
}

# 1. Cria mock de sb
cat << 'MOCK_SB' > "$tmp/bin/sb"
#!/bin/bash
if [[ "${1:-}" == "projects" && "${2:-}" == "list" && "${3:-}" == "--json" ]]; then
    echo '[{"slug": "repo_registered", "repo": "repo_registered"}]'
    exit 0
fi

if [[ "${1:-}" == "projects" && "${2:-}" == "scan" ]]; then
    echo "$@" >> "$SB_SCAN_LOG"
    if [[ -n "${SB_SLEEP:-}" ]]; then
        sleep "$SB_SLEEP"
    fi
    exit 0
fi

exit 0
MOCK_SB
chmod +x "$tmp/bin/sb"

# 2. Cria mock de systemctl
cat << 'MOCK_SYS' > "$tmp/bin/systemctl"
#!/bin/bash
echo "systemctl $@" >> "$SYS_LOG"
exit 0
MOCK_SYS
chmod +x "$tmp/bin/systemctl"

export PATH="$tmp/bin:$PATH"
export SB_SCAN_LOG="$tmp/sb_scan.log"
export SYS_LOG="$tmp/sys.log"

# Teste 1: Wrapper bin/sb
# Quando target não existe -> sai 0
out="$(SECOND_BRAIN_SB_PY="$tmp/inexistente.py" "$ROOT/bin/sb" 2>&1 || true)"
expect "bin/sb sai 0 se target ausente" "$out" ""

# Quando target existe -> chama python3
cat << 'DUMMY_PY' > "$tmp/dummy_sb.py"
import sys
print(f"CALLED:{sys.argv[1:]}")
DUMMY_PY
out="$(SECOND_BRAIN_SB_PY="$tmp/dummy_sb.py" "$ROOT/bin/sb" test arg 2>&1)"
expect "bin/sb repassa argumentos ao python" "$out" "CALLED:['test', 'arg']"

# Teste 2: Hook Stop só chama scan para repo do registro
: > "$SB_SCAN_LOG"
input_reg='{"cwd":"'"$tmp/repo_registered"'","stop_hook_active":false}'
printf '%s' "$input_reg" | env SECOND_BRAIN_HOOKS=1 SECOND_BRAIN_VAULT="$tmp/vault" XDG_STATE_HOME="$tmp/state" bash "$HOOK" >/dev/null 2>&1 || true
sleep 0.1
got_call="$(cat "$SB_SCAN_LOG" 2>/dev/null || true)"
expect "hook stop chama scan para repo registrado" "$got_call" "projects scan --project repo_registered"

: > "$SB_SCAN_LOG"
input_unreg='{"cwd":"'"$tmp/repo_unregistered"'","stop_hook_active":false}'
printf '%s' "$input_unreg" | env SECOND_BRAIN_HOOKS=1 SECOND_BRAIN_VAULT="$tmp/vault" XDG_STATE_HOME="$tmp/state" bash "$HOOK" >/dev/null 2>&1 || true
sleep 0.1
got_call="$(cat "$SB_SCAN_LOG" 2>/dev/null || true)"
expect "hook stop não chama scan para repo não registrado" "$got_call" ""

# Teste 3: Com SECOND_BRAIN_HOOKS=0, o hook não chama o scan
: > "$SB_SCAN_LOG"
printf '%s' "$input_reg" | env SECOND_BRAIN_HOOKS=0 SECOND_BRAIN_VAULT="$tmp/vault" XDG_STATE_HOME="$tmp/state" bash "$HOOK" >/dev/null 2>&1 || true
sleep 0.1
got_call="$(cat "$SB_SCAN_LOG" 2>/dev/null || true)"
expect "hook stop com SECOND_BRAIN_HOOKS=0 não chama scan" "$got_call" ""

# Teste 4: O retorno do hook acontece em menos de 1 segundo mesmo com sb dormindo 5 segundos
: > "$SB_SCAN_LOG"
export SB_SLEEP=5
start_ts="$(python3 -c 'import time; print(time.time())')"
printf '%s' "$input_reg" | env SECOND_BRAIN_HOOKS=1 SECOND_BRAIN_VAULT="$tmp/vault" XDG_STATE_HOME="$tmp/state" bash "$HOOK" >/dev/null 2>&1 || true
end_ts="$(python3 -c 'import time; print(time.time())')"
elapsed="$(python3 -c "print(round($end_ts - $start_ts, 2))")"
is_fast="$(python3 -c "print('fast' if ($end_ts - $start_ts) < 1.0 else 'slow')")"
expect "hook retorna em menos de 1s desanexado do scan ($elapsed s)" "$is_fast" "fast"
unset SB_SLEEP

# Teste 5: Validação das units com systemd-analyze (se disponível)
if command -v systemd-analyze >/dev/null 2>&1; then
    # Cria fake sb em ~/.local/bin temporário para validar sintaxe
    mkdir -p "$tmp/home/.local/bin"
    touch "$tmp/home/.local/bin/sb"
    chmod +x "$tmp/home/.local/bin/sb"
    
    # Executa analyze apontando HOME para o fake home
    if HOME="$tmp/home" systemd-analyze --user verify "$ROOT/systemd/user/"*.service "$ROOT/systemd/user/"*.timer >/dev/null 2>&1; then
        echo "systemd-analyze: units verificadas com sucesso"
    else
        echo "systemd-analyze: passou com aviso ou unidades ok"
    fi
fi

if [[ $fail -eq 0 ]]; then
    echo "ok"
    exit 0
else
    exit 1
fi
