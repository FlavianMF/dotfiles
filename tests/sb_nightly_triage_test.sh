#!/bin/bash
# Testes TDD de bin/sb-nightly-triage
# Uso: bash tests/sb_nightly_triage_test.sh
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

SB_TRIAGE="$ROOT/bin/sb-nightly-triage"
if [[ ! -f "$SB_TRIAGE" ]]; then
    echo "❌ FALHA: bin/sb-nightly-triage não existe"
    exit 1
fi

# ==============================================================================
# 1. Testes de Ajuda e Validação de Argumentos
# ==============================================================================
out_help="$(bash "$SB_TRIAGE" --help 2>&1)"
has "help exibe uso" "Uso: sb-nightly-triage" "$out_help"
has "help lista --dry-run" "--dry-run" "$out_help"
has "help lista --limit" "--limit" "$out_help"
has "help lista --vault-path" "--vault-path" "$out_help"
has "help lista --queue-file" "--queue-file" "$out_help"
has "help lista --skip-power" "--skip-power" "$out_help"

rc=0
bash "$SB_TRIAGE" --arg-invalido >/dev/null 2>&1 || rc=$?
expect "opção desconhecida sai com 2" "$rc" "2"

rc=0
bash "$SB_TRIAGE" --limit abc >/dev/null 2>&1 || rc=$?
expect "limit não numérico sai com 2" "$rc" "2"

# ==============================================================================
# 2. Fila Vazia
# ==============================================================================
mock_state="$tmp/state_empty"
mkdir -p "$mock_state"
touch "$mock_state/queue.jsonl"
touch "$mock_state/review.jsonl"
mock_vault="$tmp/vault_empty"
mkdir -p "$mock_vault/00_Inbox"

rc=0
out_empty="$(bash "$SB_TRIAGE" --skip-power --queue-file "$mock_state/queue.jsonl" --vault-path "$mock_vault" 2>&1)" || rc=$?
expect "fila vazia sai com 0" "$rc" "0"
has "fila vazia loga aviso" "Nenhum candidato pendente" "$out_empty"

# ==============================================================================
# 3. Dry-Run e Filtragem de Revisados
# ==============================================================================
mock_state_dry="$tmp/state_dry"
mkdir -p "$mock_state_dry"
mock_queue="$mock_state_dry/queue.jsonl"
mock_review="$mock_state_dry/review.jsonl"

cat << 'JSONL' > "$mock_queue"
{"id":"cand-001","kind":"concept","title":"Nota Conceito 1","summary":"Resumo 1","created":"2026-11-09"}
{"id":"cand-002","kind":"trap","title":"Nota Armadilha 2","summary":"Resumo 2","created":"2026-11-09"}
{"id":"cand-003","kind":"pattern","title":"Nota Padrao 3","summary":"Resumo 3","created":"2026-11-09"}
JSONL

# Marca cand-002 como já revisado
echo '{"id":"cand-002","decision":"applied"}' > "$mock_review"

export SECOND_BRAIN_STATE_DIR="$mock_state_dry"
out_dry="$(bash "$SB_TRIAGE" --dry-run --limit 10 --vault-path "$mock_vault" 2>&1)"
has "dry-run processa cand-001" "cand-001" "$out_dry"
has "dry-run processa cand-003" "cand-003" "$out_dry"
if grep -q "cand-002" <<<"$out_dry"; then
    echo "❌ FALHA: cand-002 (já revisado) não foi filtrado no dry-run"
    fail=1
else
    echo "✅ PASSOU: candidato revisado (cand-002) foi filtrado corretamente"
fi
has "dry-run conclui com mensagem" "Dry-run concluído com sucesso" "$out_dry"

# ==============================================================================
# 4. Limite Respeitado (--limit)
# ==============================================================================
out_limit="$(bash "$SB_TRIAGE" --dry-run --limit 1 --vault-path "$mock_vault" 2>&1)"
has "limit 1 inclui cand-001" "cand-001" "$out_limit"
if grep -q "cand-003" <<<"$out_limit"; then
    echo "❌ FALHA: limit 1 incluiu mais itens do que o esperado"
    fail=1
else
    echo "✅ PASSOU: flag --limit 1 respeitada"
fi

# ==============================================================================
# 5. Fluxo Completo: Mocks de pc-ctl e llm-batch + Geração em 00_Inbox
# ==============================================================================
mock_bin="$tmp/mock_bin"
mkdir -p "$mock_bin"

power_log="$tmp/power.log"
cat << 'MOCK_PC_CTL' > "$mock_bin/pc-ctl"
#!/usr/bin/env bash
echo "$@" >> "$MOCK_POWER_LOG"
exit 0
MOCK_PC_CTL
chmod +x "$mock_bin/pc-ctl"

cat << 'MOCK_LLM_BATCH' > "$mock_bin/llm-batch"
#!/usr/bin/env bash
out_dir=""
queue_dir=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --out-dir) out_dir="$2"; shift 2 ;;
        --queue-dir) queue_dir="$2"; shift 2 ;;
        *) shift ;;
    esac
done

for job in "$queue_dir"/*.json; do
    [[ -f "$job" ]] || continue
    jid="$(jq -r '.id' "$job")"
    jout="$out_dir/$jid"
    mkdir -p "$jout"
    cat << NOTE > "$jout/raw_output.txt"
---
title: Mock Nota $jid
type: concept
tags: [test, mock]
created: 2026-11-09
summary: Resumo gerado via mock para $jid
confidence: low
---

# Mock Nota $jid

## Contexto
Contexto gerado pelo modelo local na GPU RTX 5050.

## Detalhes
Detalhes estruturados da nota.
NOTE
    touch "$jout/SUCCESS"
done
exit 0
MOCK_LLM_BATCH
chmod +x "$mock_bin/llm-batch"

export PC_CTL_BIN="$mock_bin/pc-ctl"
export LLM_BATCH_BIN="$mock_bin/llm-batch"
export MOCK_POWER_LOG="$power_log"

mock_vault_run="$tmp/vault_run"
inbox_dir="$mock_vault_run/00_Inbox"
mkdir -p "$inbox_dir"

rc=0
out_run="$(bash "$SB_TRIAGE" --vault-path "$mock_vault_run" 2>&1)" || rc=$?
expect "execução com mocks sai com 0" "$rc" "0"

# Verifica transição de energia em power.log
has "pc-ctl elevou energia para llm-boost" "power-mode llm-boost --ttl 2h" "$(cat "$power_log" 2>/dev/null || echo "")"
has "pc-ctl restaurou energia para balanced" "power-mode balanced" "$(cat "$power_log" 2>/dev/null || echo "")"

# Verifica se os arquivos foram criados no 00_Inbox
nota_cand1="$(find "$inbox_dir" -name "cand-001*.md" | head -n1)"
nota_cand3="$(find "$inbox_dir" -name "cand-003*.md" | head -n1)"

if [[ -f "$nota_cand1" ]]; then
    echo "✅ PASSOU: nota para cand-001 gerada em $nota_cand1"
    has "frontmatter contém title" "title:" "$(cat "$nota_cand1")"
    has "frontmatter contém confidence low" "confidence: low" "$(cat "$nota_cand1")"
    has "frontmatter contém provenance" "provenance: sb-nightly-triage" "$(cat "$nota_cand1")"
else
    echo "❌ FALHA: nota para cand-001 não foi criada em 00_Inbox"
    fail=1
fi

if [[ -f "$nota_cand3" ]]; then
    echo "✅ PASSOU: nota para cand-003 gerada em $nota_cand3"
else
    echo "❌ FALHA: nota para cand-003 não foi criada em 00_Inbox"
    fail=1
fi

# ==============================================================================
# 6. Restauração de Energia em Caso de Erro (Trap EXIT)
# ==============================================================================
mock_state_fail="$tmp/state_fail"
mkdir -p "$mock_state_fail"
cat << 'JSONL' > "$mock_state_fail/queue.jsonl"
{"id":"cand-fail-999","kind":"concept","title":"Nota Falha","summary":"Resumo Falha","created":"2026-11-09"}
JSONL
touch "$mock_state_fail/review.jsonl"
export SECOND_BRAIN_STATE_DIR="$mock_state_fail"

power_log_fail="$tmp/power_fail.log"
export MOCK_POWER_LOG="$power_log_fail"

mock_vault_fail="$tmp/vault_fail"
mkdir -p "$mock_vault_fail/00_Inbox"

cat << 'MOCK_FAIL_LLM_BATCH' > "$mock_bin/llm-batch"
#!/usr/bin/env bash
out_dir=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --out-dir) out_dir="$2"; shift 2 ;;
        *) shift ;;
    esac
done
# Simula que o job falhou
mkdir -p "$out_dir/cand-fail-999"
echo "OOM on GPU" > "$out_dir/cand-fail-999/FAILED"
exit 1
MOCK_FAIL_LLM_BATCH

rc_fail=0
bash "$SB_TRIAGE" --vault-path "$mock_vault_fail" >/dev/null 2>&1 || rc_fail=$?
expect "falha no llm-batch resulta em erro no sb-nightly-triage" "$rc_fail" "1"
has "energia elevada para llm-boost antes de falhar" "power-mode llm-boost --ttl 2h" "$(cat "$power_log_fail" 2>/dev/null || echo "")"
has "energia restaurada para balanced mesmo após falha" "power-mode balanced" "$(cat "$power_log_fail" 2>/dev/null || echo "")"

echo
if [[ "$fail" -eq 0 ]]; then
    echo "🎉 Todos os testes de sb-nightly-triage passaram com sucesso!"
    exit 0
else
    echo "❌ Existem falhas nos testes de sb-nightly-triage."
    exit 1
fi
