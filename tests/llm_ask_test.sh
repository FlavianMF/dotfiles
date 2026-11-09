#!/bin/bash
# Testes TDD de bin/llm-ask com mock de curl, think, grammar e apply de search-replace
# Uso: bash tests/llm_ask_test.sh
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

LLM_ASK="$ROOT/bin/llm-ask"
if [[ ! -f "$LLM_ASK" ]]; then
    echo "❌ FALHA: bin/llm-ask não existe"
    exit 1
fi

# 1. Testes de Ajuda e Validação de Argumentos
out_help="$(bash "$LLM_ASK" --help 2>&1)"
has "help exibe uso" "Uso: llm-ask" "$out_help"
has "help lista opções" "--temp" "$out_help"
has "help lista --think" "--think" "$out_help"
has "help lista --apply" "--apply" "$out_help"

out_noargs="$(bash "$LLM_ASK" 2>&1 || true)"
has "erro de argumento obrigatório" "Arquivo de prompt do usuário é obrigatório" "$out_noargs"

out_no_file="$(bash "$LLM_ASK" "$tmp/inexistente.txt" 2>&1 || true)"
has "erro de arquivo não encontrado" "Arquivo de prompt do usuário não encontrado" "$out_no_file"

# 2. Criação de prompts para teste de payload JSON
echo "USER PROMPT TEST" > "$tmp/user.txt"
echo "SYSTEM PROMPT TEST" > "$tmp/sys.txt"

# 3. Teste de Dry-run
out_dry="$(bash "$LLM_ASK" --dry-run "$tmp/user.txt" "$tmp/sys.txt")"
if jq empty <<<"$out_dry" >/dev/null 2>&1; then
    echo "✅ PASSOU: payload do dry-run é JSON válido"
else
    echo "❌ FALHA: payload do dry-run não é JSON válido"
    fail=1
fi

sys_msg="$(jq -r '.messages[] | select(.role == "system") | .content' <<<"$out_dry")"
has "system prompt incluído no payload" "SYSTEM PROMPT TEST" "$sys_msg"

usr_msg="$(jq -r '.messages[] | select(.role == "user") | .content' <<<"$out_dry")"
has "user prompt incluído no payload" "USER PROMPT TEST" "$usr_msg"

temp="$(jq -r '.temperature' <<<"$out_dry")"
expect "temperatura padrão 0.2" "$temp" "0.2"

max_tokens="$(jq -r '.max_tokens' <<<"$out_dry")"
expect "max_tokens padrão 6000" "$max_tokens" "6000"

# 4. Customização de parâmetros no dry-run e --grammar
echo 'root ::= "test"' > "$tmp/test.gbnf"
out_custom="$(bash "$LLM_ASK" --dry-run --temp 0.7 --max-tokens 1024 --grammar "$tmp/test.gbnf" "$tmp/user.txt" "$tmp/sys.txt")"
custom_temp="$(jq -r '.temperature' <<<"$out_custom")"
expect "temperatura customizada 0.7" "$custom_temp" "0.7"
custom_max="$(jq -r '.max_tokens' <<<"$out_custom")"
expect "max_tokens customizado 1024" "$custom_max" "1024"
grammar_in_payload="$(jq -r '.grammar' <<<"$out_custom")"
has "grammar injetada no payload" 'root ::= "test"' "$grammar_in_payload"

# 5. Entrada via stdin (-)
out_stdin="$(echo "STDIN CONTENT" | bash "$LLM_ASK" --dry-run - "$tmp/sys.txt")"
usr_stdin="$(jq -r '.messages[] | select(.role == "user") | .content' <<<"$out_stdin")"
has "leitura via stdin funciona" "STDIN CONTENT" "$usr_stdin"

# 6. Teste de extração de código e modo --raw com mock de curl
mkdir -p "$tmp/bin"
cat << 'MOCK' > "$tmp/bin/curl"
#!/bin/bash
cat << 'RESP'
{
  "choices": [
    {
      "message": {
        "content": "<think>\nThinking about the problem...\n</think>\nIgnored explanation\n```typescript\nexport const answer = 42;\n```\nMore text"
      }
    }
  ]
}
RESP
MOCK
chmod +x "$tmp/bin/curl"

out_extract="$(PATH="$tmp/bin:$PATH" bash "$LLM_ASK" "$tmp/user.txt" "$tmp/sys.txt")"
has "extrai bloco de código sem prosa externa e sem think" "export const answer = 42;" "$out_extract"
if grep -q "Thinking about" <<<"$out_extract"; then
    echo "❌ FALHA: tag think não foi descartada na extração de código"
    fail=1
else
    echo "✅ PASSOU: tag think descartada na extração de código"
fi

out_think="$(PATH="$tmp/bin:$PATH" bash "$LLM_ASK" --think "$tmp/user.txt" "$tmp/sys.txt")"
has "extrai apenas conteúdo da tag think" "Thinking about the problem..." "$out_think"

out_raw="$(PATH="$tmp/bin:$PATH" bash "$LLM_ASK" --raw "$tmp/user.txt" "$tmp/sys.txt")"
has "modo raw preserva texto completo" "Ignored explanation" "$out_raw"

# 7. Teste de --apply com Search/Replace blocks
cat << 'MOCK_SR' > "$tmp/bin/curl"
#!/bin/bash
cat << 'RESP'
{
  "choices": [
    {
      "message": {
        "content": "```search-replace\n<<<<<<< SEARCH\nold_value = 10\n=======\nnew_value = 20\n>>>>>>> REPLACE\n```"
      }
    }
  ]
}
RESP
MOCK_SR

echo "old_value = 10" > "$tmp/target_file.py"
PATH="$tmp/bin:$PATH" bash "$LLM_ASK" --apply "$tmp/target_file.py" "$tmp/user.txt" "$tmp/sys.txt" >/dev/null
updated_content="$(cat "$tmp/target_file.py")"
expect "--apply substitui conteúdo com search-replace" "$updated_content" "new_value = 20"


# 8. Teste de --no-system no dry-run
out_nosys="$(bash "$LLM_ASK" --dry-run --no-system "$tmp/user.txt" "$tmp/sys.txt")"
has_sys="$(jq '[.messages[] | select(.role == "system")] | length' <<<"$out_nosys")"
expect "--no-system não inclui role system" "$has_sys" "0"
usr_nosys="$(jq -r '[.messages[] | select(.role == "user")] | .[0].content' <<<"$out_nosys")"
has "user prompt contém regras do system com --no-system" "SYSTEM PROMPT TEST" "$usr_nosys"
has "user prompt contém prompt original com --no-system" "USER PROMPT TEST" "$usr_nosys"

# 9. Teste de --log e --save-raw
log_out="$tmp/test_log.json"
raw_out="$tmp/test_raw.txt"
PATH="$tmp/bin:$PATH" bash "$LLM_ASK" --log "$log_out" --save-raw "$raw_out" "$tmp/user.txt" "$tmp/sys.txt" >/dev/null
if [[ -f "$log_out" && -f "$raw_out" ]]; then
    echo "✅ PASSOU: --log e --save-raw geram os arquivos informados"
else
    echo "❌ FALHA: --log ou --save-raw não geraram arquivos"
    fail=1
fi

# 10. Teste de códigos de saída: 2 para rede, 3 para truncado, 4 para vazio
# Mock de falha de rede
cat << 'MOCK_NET' > "$tmp/bin/curl"
#!/bin/bash
exit 28
MOCK_NET

set +e
PATH="$tmp/bin:$PATH" bash "$LLM_ASK" "$tmp/user.txt" "$tmp/sys.txt" >/dev/null 2>&1
code_net=$?
expect "código de saída 2 para erro de rede/curl" "$code_net" "2"

# Mock de resposta vazia
cat << 'MOCK_EMPTY' > "$tmp/bin/curl"
#!/bin/bash
echo '{"choices": [{"message": {"content": ""}}]}'
MOCK_EMPTY

PATH="$tmp/bin:$PATH" bash "$LLM_ASK" "$tmp/user.txt" "$tmp/sys.txt" >/dev/null 2>&1
code_empty=$?
expect "código de saída 4 para resposta vazia" "$code_empty" "4"

# Mock de resposta truncada (finish_reason=length)
cat << 'MOCK_TRUNC' > "$tmp/bin/curl"
#!/bin/bash
echo '{"choices": [{"finish_reason": "length", "message": {"content": "partially completed code..."}}]}'
MOCK_TRUNC

PATH="$tmp/bin:$PATH" bash "$LLM_ASK" "$tmp/user.txt" "$tmp/sys.txt" >/dev/null 2>&1
code_trunc=$?
expect "código de saída 3 para resposta truncada" "$code_trunc" "3"

echo "----------------------------------------"
if [[ $fail -eq 0 ]]; then
    echo "🎉 Todos os testes de bin/llm-ask PASSARAM!"
else
    echo "💥 Foram encontradas $fail falhas no teste de bin/llm-ask."
fi
exit $fail
