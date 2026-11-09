#!/bin/bash
# Testes TDD de bin/llm-batch com isolamento de worktree, mock de llm-ask, validadores e logs
# Uso: bash tests/llm_batch_test.sh
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

LLM_BATCH="$ROOT/bin/llm-batch"
if [[ ! -f "$LLM_BATCH" ]]; then
    echo "❌ FALHA: bin/llm-batch não existe"
    exit 1
fi

# 1. Testes de Ajuda e Validação de Argumentos
out_help="$(bash "$LLM_BATCH" --help 2>&1)"
has "help exibe uso" "Uso: llm-batch" "$out_help"
has "help lista --queue-dir" "--queue-dir" "$out_help"
has "help lista --dry-run" "--dry-run" "$out_help"
has "help lista --skip-ram-check" "--skip-ram-check" "$out_help"

# 2. Configuração de Repositório Git Simulado
repo_dir="$tmp/mock_repo"
mkdir -p "$repo_dir"
git -C "$repo_dir" init -q -b main
git -C "$repo_dir" config user.name "Tester"
git -C "$repo_dir" config user.email "tester@example.com"
echo "val = 10" > "$repo_dir/target.py"
git -C "$repo_dir" add target.py
git -C "$repo_dir" commit -q -m "Initial commit"

# 3. Criação de Jobs de Teste (JSON e YAML)
jobs_dir="$tmp/jobs"
mkdir -p "$jobs_dir"

prompt_file="$tmp/prompt.txt"
echo "Update target.py val to 20" > "$prompt_file"

cat << JOB1 > "$jobs_dir/job1.yaml"
id: test-job-1
profile: coder7b
repo: "$repo_dir"
base_ref: main
prompt_file: "$prompt_file"
target_file: target.py
validators:
  - grep -q "val = 20" target.py
max_tokens: 1024
timeout_s: 60
JOB1

cat << JOB2 > "$jobs_dir/job2.json"
{
  "id": "test-job-2",
  "profile": "deepseek14b",
  "repo": "$repo_dir",
  "base_ref": "main",
  "prompt_file": "$prompt_file",
  "target_file": "target.py",
  "validators": [
    "grep -q 'val = 20' target.py"
  ],
  "max_tokens": 2048,
  "timeout_s": 120
}
JOB2

# 4. Teste de Dry-run com Agrupamento por Perfil
out_dry="$(bash "$LLM_BATCH" run -q "$jobs_dir" --dry-run --skip-power-check 2>&1)"
has "dry-run detecta perfis" "Perfis detectados: coder7b deepseek14b" "$out_dry"
has "dry-run lista job 1" "Job test-job-1" "$out_dry"
has "dry-run lista job 2" "Job test-job-2" "$out_dry"

# 5. Execução de Job com Mock de llm-ask e llama-server
bin_dir="$tmp/bin"
mkdir -p "$bin_dir"

# Mock de llm-ask que simula aplicação de patch e gravação de log/reasoning
cat << 'MOCK_ASK' > "$bin_dir/llm-ask"
#!/bin/bash
apply_file=""
log_file=""
raw_file=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)
            apply_file="$2"
            shift 2
            ;;
        --log)
            log_file="$2"
            shift 2
            ;;
        --save-raw)
            raw_file="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

if [[ -n "$apply_file" && -f "$apply_file" ]]; then
    echo "val = 20" > "$apply_file"
fi

if [[ -n "$log_file" ]]; then
    mkdir -p "$(dirname "$log_file")"
    cat << 'JSON' > "$log_file"
{
  "choices": [
    {
      "finish_reason": "stop",
      "message": {
        "content": "val = 20",
        "reasoning_content": "Plan: change val to 20 to satisfy validator."
      }
    }
  ],
  "usage": {
    "prompt_tokens": 50,
    "completion_tokens": 25,
    "total_tokens": 75
  }
}
JSON
fi

if [[ -n "$raw_file" ]]; then
    mkdir -p "$(dirname "$raw_file")"
    echo "val = 20" > "$raw_file"
fi

echo "Mock llm-ask executed successfully"
exit 0
MOCK_ASK
chmod +x "$bin_dir/llm-ask"

# Mock de curl para simular health check do servidor como 200 OK
cat << 'MOCK_CURL' > "$bin_dir/curl"
#!/bin/bash
if [[ "$*" == *"/health"* ]]; then
    echo '{"status":"ok"}'
    exit 0
elif [[ "$*" == *"/v1/models"* ]]; then
    echo '{"data":[{"id":"qwen2.5-coder-7b"}]}'
    exit 0
fi
exit 0
MOCK_CURL
chmod +x "$bin_dir/curl"

out_dir="$tmp/out"
LLM_ASK_BIN="$bin_dir/llm-ask" PATH="$bin_dir:$PATH" bash "$LLM_BATCH" run     -q "$jobs_dir/job1.yaml"     -o "$out_dir"     --skip-ram-check     --skip-power-check     --restore-profile "" > "$tmp/run.log" 2>&1

# Verificações da execução do job 1
job1_out="$out_dir/test-job-1"
if [[ -f "$job1_out/SUCCESS" ]]; then
    echo "✅ PASSOU: job 1 finalizado com SUCCESS"
else
    echo "❌ FALHA: job 1 não gerou SUCCESS. Log:"
    cat "$tmp/run.log"
    fail=1
fi

if [[ -f "$job1_out/patch.diff" ]]; then
    echo "✅ PASSOU: patch.diff gerado para job 1"
    diff_content="$(cat "$job1_out/patch.diff")"
    has "patch contém alteração esperada" "+val = 20" "$diff_content"
else
    echo "❌ FALHA: patch.diff não foi gerado para job 1"
    fail=1
fi

if [[ -f "$job1_out/log.json" ]]; then
    echo "✅ PASSOU: log.json estruturado gerado para job 1"
    st="$(jq -r '.status' "$job1_out/log.json")"
    expect "status no log.json é SUCCESS" "$st" "SUCCESS"
    reasoning="$(jq -r '.reasoning_content' "$job1_out/log.json")"
    has "reasoning_content preservado no log" "Plan: change val to 20" "$reasoning"
else
    echo "❌ FALHA: log.json não encontrado para job 1"
    fail=1
fi

# Verifica que o repositório principal permaneceu limpo
main_repo_val="$(cat "$repo_dir/target.py")"
expect "repositório original não foi modificado (worktree isolado)" "$main_repo_val" "val = 10"

# 6. Teste de Falha de Validador
cat << JOB_FAIL > "$jobs_dir/job_fail.yaml"
id: test-job-fail
profile: coder7b
repo: "$repo_dir"
base_ref: main
prompt_file: "$prompt_file"
target_file: target.py
validators:
  - grep -q "valor_inexistente" target.py
JOB_FAIL

LLM_ASK_BIN="$bin_dir/llm-ask" PATH="$bin_dir:$PATH" bash "$LLM_BATCH" run     -q "$jobs_dir/job_fail.yaml"     -o "$out_dir"     --skip-ram-check     --skip-power-check     --restore-profile "" >/dev/null 2>&1 || true

job_fail_out="$out_dir/test-job-fail"
if [[ -f "$job_fail_out/FAILED" ]]; then
    echo "✅ PASSOU: job com validador falho gerou FAILED"
    f_reason="$(cat "$job_fail_out/FAILED")"
    expect "motivo da falha é VALIDATOR_FAILED" "$f_reason" "VALIDATOR_FAILED"
else
    echo "❌ FALHA: job com validador falho não gerou FAILED"
    fail=1
fi

# 7. Teste de status e clean
out_status="$(bash "$LLM_BATCH" status -o "$out_dir" 2>&1)"
has "status exibe test-job-1 SUCCESS" "test-job-1: SUCCESS" "$out_status"
has "status exibe test-job-fail FAILED" "test-job-fail: FAILED" "$out_status"

out_clean="$(bash "$LLM_BATCH" clean --default-repo "$repo_dir" 2>&1)"
has "clean reporta conclusão" "Limpeza concluída" "$out_clean"

echo "----------------------------------------"
if [[ $fail -eq 0 ]]; then
    echo "🎉 Todos os testes de bin/llm-batch PASSARAM!"
else
    echo "💥 Foram encontradas $fail falhas no teste de bin/llm-batch."
fi
exit $fail
