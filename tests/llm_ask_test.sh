#!/bin/bash
# Testes TDD de bin/llm-ask com mock de curl e validação de payload JSON
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

# 4. Customização de parâmetros no dry-run
out_custom="$(bash "$LLM_ASK" --dry-run --temp 0.7 --max-tokens 1024 "$tmp/user.txt" "$tmp/sys.txt")"
custom_temp="$(jq -r '.temperature' <<<"$out_custom")"
expect "temperatura customizada 0.7" "$custom_temp" "0.7"
custom_max="$(jq -r '.max_tokens' <<<"$out_custom")"
expect "max_tokens customizado 1024" "$custom_max" "1024"

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
        "content": "Ignored explanation\n```typescript\nexport const answer = 42;\n```\nMore text"
      }
    }
  ]
}
RESP
MOCK
chmod +x "$tmp/bin/curl"

out_extract="$(PATH="$tmp/bin:$PATH" bash "$LLM_ASK" "$tmp/user.txt" "$tmp/sys.txt")"
has "extrai bloco de código sem prosa externa" "export const answer = 42;" "$out_extract"
if grep -q "Ignored explanation" <<<"$out_extract"; then
    echo "❌ FALHA: prosa externa não foi descartada"
    fail=1
else
    echo "✅ PASSOU: prosa externa descartada na extração"
fi

out_raw="$(PATH="$tmp/bin:$PATH" bash "$LLM_ASK" --raw "$tmp/user.txt" "$tmp/sys.txt")"
has "modo raw preserva texto completo" "Ignored explanation" "$out_raw"

echo "----------------------------------------"
if [[ $fail -eq 0 ]]; then
    echo "🎉 Todos os testes de bin/llm-ask PASSARAM!"
else
    echo "💥 Foram encontradas $fail falhas no teste de bin/llm-ask."
fi
exit $fail
