#!/bin/bash
# Testes de claude/statusline.sh (linha 2: ECC e second brain). Uso: bash tests/statusline_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SL="$ROOT/claude/statusline.sh"
tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT
fail=0

export CLAUDE_CONFIG_DIR="$tmp/userconf"; mkdir -p "$CLAUDE_CONFIG_DIR"
echo '{"enabledPlugins":{"ecc@ecc":false}}' >"$CLAUDE_CONFIG_DIR/settings.json"
export CLAUDE_SESSION_STATE_DIR="$tmp/sess" SECOND_BRAIN_STATE_DIR="$tmp/sb" HOME="$tmp/home"
mkdir -p "$tmp/sess" "$tmp/sb" "$HOME"
export NO_COLOR=1
unset COLUMNS

expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
proj="$tmp/proj"; git init -q "$proj"
json() { printf '{"model":{"display_name":"Sonnet"},"cwd":"%s","session_id":"%s","context_window":{"remaining_percentage":71.2}}' "$proj" "$1"; }
run() { json "$1" | bash "$SL"; }                # saída completa
last() { run "$1" | tail -n 1; }                  # linha 2
snap() { printf '%s\n' "$2" "$3" "$4" "$proj" >"$tmp/sess/$1.ecc"; }  # snap <sid> <estado> <escopo> <sb>

# Estrutura: duas linhas; a última é a do ECC/SB (fica logo acima do indicador de modo).
expect "duas linhas" "$(run s0 | wc -l | tr -d ' ')" 2
expect "linha 1 mantém modelo e contexto" "$(run s0 | head -n 1 | grep -c 'Sonnet.*ctx 71%')" 1
expect "sem snapshot nem arquivos" "$(last s0)" "ECC ? · SB —"

# Snapshot e contagens.
snap s1 ligado local on
printf 'a.md\nb.md\nc.md\n' >"$tmp/sb/s1.injected"; printf 'a.md\n' >"$tmp/sb/s1.opened"
mkdir -p "$proj/.claude"; echo '{"enabledPlugins":{"ecc@ecc":true}}' >"$proj/.claude/settings.local.json"
expect "ligado com notas e aberta" "$(last s1)" "ECC ligado (local) · SB 3 notas · 1 aberta"
printf 'a.md\n' >"$tmp/sb/s1.injected"; printf 'a.md\nb.md\n' >"$tmp/sb/s1.opened"
expect "singular e plural" "$(last s1)" "ECC ligado (local) · SB 1 nota · 2 abertas"
: >"$tmp/sb/s1.injected"; rm "$tmp/sb/s1.opened"
expect "zero notas" "$(last s1)" "ECC ligado (local) · SB 0 notas"

# Divergência: snapshot diz desligado, disco diz ligado (e o contrário), com cache por mtime.
snap s2 desligado usuário on
expect "snapshot desligado, disco ligado" "$(last s2)" "ECC desligado* reinicie · SB 0 notas"
echo '{"enabledPlugins":{"ecc@ecc":false}}' >"$proj/.claude/settings.local.json"; sleep 1.1; touch "$proj/.claude/settings.local.json"
expect "cache invalida quando o settings muda" "$(last s2)" "ECC desligado · SB 0 notas"
snap s3 ligado local on
expect "snapshot ligado, disco desligado" "$(last s3)" "ECC ligado (local)* reinicie · SB 0 notas"
echo '{"enabledPlugins":{"ecc@ecc":true}}' >"$proj/.claude/settings.local.json"; sleep 1.1; touch "$proj/.claude/settings.local.json"
expect "volta a coincidir" "$(last s3)" "ECC ligado (local) · SB 0 notas"

# Second brain desligado na sessão; formas curtas; cores.
snap s4 ligado local off
expect "SB off" "$(last s4)" "ECC ligado (local) · SB off"
expect "forma curta" "$(COLUMNS=30 last s1)" "ECC+ · SB0"
expect "forma curta sem snapshot" "$(COLUMNS=30 last s0)" "ECC ? · SB-"
expect "NO_COLOR sem escapes" "$(run s1 | grep -c $'\033')" 0
expect "com cor há escapes" "$(json s1 | NO_COLOR='' bash "$SL" | grep -c $'\033')" 2

# session_id malicioso não escapa nem quebra; entrada inválida não falha.
expect "sid malicioso" "$(last '../../etc')" "ECC ? · SB —"
expect "entrada inválida: rc 0" "$(printf 'lixo' | bash "$SL" >/dev/null 2>&1; echo $?)" 0
expect "entrada vazia ainda imprime 2 linhas" "$(printf '' | bash "$SL" | wc -l | tr -d ' ')" 2

# Desempenho: média abaixo de 150 ms por execução (50 execuções), com cache quente.
snap sp ligado local on; printf 'a.md\n' >"$tmp/sb/sp.injected"; run sp >/dev/null
start=$(date +%s%N); for _ in $(seq 50); do run sp >/dev/null; done; end=$(date +%s%N)
avg=$(( (end - start) / 50 / 1000000 ))
[[ $avg -lt 150 ]] || { echo "FALHA: média ${avg} ms por execução"; fail=1; }

[[ $fail -eq 0 ]] && echo "ok" || exit 1
