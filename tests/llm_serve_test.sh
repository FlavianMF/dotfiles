#!/bin/bash
# Testes de bin/llm-serve com llama-server, curl e pgrep falsos no PATH (jq real). Uso: bash tests/llm_serve_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT
fail=0
expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
has() { if ! grep -q -F -- "$2" <<<"$3"; then echo "FALHA: $1 (faltou '$2' em: $3)"; fail=1; fi; }
hasnt() { if grep -q -F -- "$2" <<<"$3"; then echo "FALHA: $1 (achou '$2' em: $3)"; fail=1; fi; }

SERVE="$ROOT/bin/llm-serve"
[[ -f "$SERVE" ]] || { echo "FALHA: $SERVE não existe"; exit 1; }

# Guarde o llama-server real antes de trocar o PATH. Só o teste de contrato o usa, e só com --help.
REAL_LLAMA="$(command -v llama-server 2>/dev/null || true)"
command -v jq >/dev/null || { echo "FALHA: jq não está instalado"; exit 1; }
JQ_DIR="$(dirname "$(command -v jq)")"

# Sandbox: PATH com os falsos na frente. Nenhum falso toca a rede.
export HOME="$tmp/home"
mkdir -p "$HOME" "$tmp/bin"
export FAKE_LOG="$tmp/llama-args"
export FAKE_CURL_LOG="$tmp/curl-calls"
export OLLAMA_BASE_URL="http://host-falso:11434/v1"

cat >"$tmp/bin/llama-server" <<'EOF'
#!/bin/bash
echo "$*" >>"$FAKE_LOG"
EOF
# curl falso: /health segue FAKE_HEALTH, /api/ps devolve FAKE_PS (falha se vazio), o resto só registra.
cat >"$tmp/bin/curl" <<'EOF'
#!/bin/bash
echo "$*" >>"$FAKE_CURL_LOG"
case "$*" in
  */health*) [[ "${FAKE_HEALTH:-down}" == up ]] && exit 0; exit 22 ;;
  */api/ps*) [[ -n "${FAKE_PS:-}" ]] || exit 22; echo "$FAKE_PS"; exit 0 ;;
  */api/generate*) exit 0 ;;
esac
exit 22
EOF
cat >"$tmp/bin/pgrep" <<'EOF'
#!/bin/bash
[[ "${FAKE_PGREP:-0}" == 1 ]]
EOF
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$JQ_DIR:/usr/bin:/bin"

reset() {
  rm -f "$FAKE_LOG" "$FAKE_CURL_LOG"
  unset LLM_N_CPU_MOE LLM_PORT LLM_CTX LLM_MAIN_HF LLM_MAIN_ALIAS
  export FAKE_HEALTH=down FAKE_PS="" FAKE_PGREP=0
}
args() { cat "$FAKE_LOG" 2>/dev/null; }
curls() { cat "$FAKE_CURL_LOG" 2>/dev/null; }

# --- 1. perfil desconhecido ---
reset
out="$(bash "$SERVE" bogus 2>&1)"; rc=$?
expect "perfil desconhecido sai 2" "$rc" "2"
has "perfil desconhecido avisa" "Perfil desconhecido" "$out"
expect "perfil desconhecido não chama llama-server" "$(args)" ""

# --- 2. .gguf inexistente ---
reset
out="$(bash "$SERVE" "$tmp/nao-existe.gguf" 2>&1)"; rc=$?
expect ".gguf inexistente sai 1" "$rc" "1"
has ".gguf inexistente avisa" "Arquivo não existe" "$out"
expect ".gguf inexistente não chama llama-server" "$(args)" ""

# --- 3. servidor já no ar ---
reset
export FAKE_HEALTH=up
out="$(bash "$SERVE" main 2>&1)"; rc=$?
expect "servidor no ar sai 0" "$rc" "0"
has "servidor no ar avisa" "já responde" "$out"
expect "servidor no ar não chama llama-server" "$(args)" ""

# --- 4. processo vivo sem /health (baixando ou carregando) ---
reset
export FAKE_PGREP=1
out="$(bash "$SERVE" main 2>&1)"; rc=$?
expect "pgrep achou processo sai 0" "$rc" "0"
has "pgrep avisa que ainda carrega" "ainda não responde" "$out"
expect "pgrep achou processo não chama llama-server" "$(args)" ""

# --- 5. perfil main ---
reset
out="$(bash "$SERVE" main 2>&1)"; rc=$?
expect "main sai 0" "$rc" "0"
a="$(args)"
has "main usa -hf" "-hf ggml-org/gpt-oss-20b-GGUF" "$a"
has "main usa --alias" "--alias gpt-oss-20b" "$a"
has "main usa -np 1" "-np 1" "$a"
has "main escuta em 127.0.0.1:8080" "--host 127.0.0.1 --port 8080" "$a"
hasnt "main não passa -ngl" "-ngl" "$a"
hasnt "main não passa -fit" "-fit" "$a"
hasnt "main sem LLM_N_CPU_MOE não passa --n-cpu-moe" "--n-cpu-moe" "$a"

# --- 6. LLM_N_CPU_MOE ---
reset
LLM_N_CPU_MOE=7 bash "$SERVE" main >/dev/null 2>&1; rc=$?
expect "N_CPU_MOE sai 0" "$rc" "0"
a="$(args)"
has "N_CPU_MOE acrescenta --n-cpu-moe 7" "--n-cpu-moe 7" "$a"
has "N_CPU_MOE desliga o fit" "-fit off" "$a"

# --- 7. .gguf existente, USUARIO/REPO e args extras ---
reset
: >"$tmp/modelo-x.gguf"
bash "$SERVE" "$tmp/modelo-x.gguf" >/dev/null 2>&1
a="$(args)"
has ".gguf usa -m" "-m $tmp/modelo-x.gguf" "$a"
has ".gguf deriva o alias" "--alias modelo-x" "$a"
reset
bash "$SERVE" user/repo:Q4_K_M >/dev/null 2>&1
a="$(args)"
has "repo usa -hf" "-hf user/repo:Q4_K_M" "$a"
has "repo deriva o alias" "--alias repo:Q4_K_M" "$a"
reset
bash "$SERVE" main --foo bar >/dev/null 2>&1
has "args extras chegam ao llama-server" "--foo bar" "$(args)"

# --- 8. Ollama com modelo residente: descarrega com keep_alive 0 ---
reset
export FAKE_PS='{"models":[{"name":"qwen3:4b"}]}'
out="$(bash "$SERVE" main 2>&1)"; rc=$?
expect "ollama residente sai 0" "$rc" "0"
has "ollama residente avisa o modelo" "Descarregando 'qwen3:4b'" "$out"
c="$(curls)"
has "ollama consulta /api/ps na URL sem /v1" "http://host-falso:11434/api/ps" "$c"
has "ollama chama /api/generate" "http://host-falso:11434/api/generate" "$c"
has "ollama descarrega com keep_alive 0" '"keep_alive":0' "$c"
has "ollama descarrega o modelo residente" '"model":"qwen3:4b"' "$c"
hasnt "ollama não usa /v1 no caminho" "/v1/api" "$c"
has "ollama residente ainda sobe o llama-server" "-hf" "$(args)"

# --- 9. Ollama sem modelo residente: não chama /api/generate ---
reset
export FAKE_PS='{"models":[]}'
bash "$SERVE" main >/dev/null 2>&1
hasnt "ollama vazio não chama /api/generate" "/api/generate" "$(curls)"

# --- 10. Ollama fora do ar: avisa e continua ---
reset
out="$(bash "$SERVE" main 2>&1)"; rc=$?
expect "ollama fora sai 0" "$rc" "0"
has "ollama fora avisa" "Aviso: o Ollama não respondeu em http://host-falso:11434" "$out"
has "ollama fora ainda sobe o llama-server" "-hf" "$(args)"

# --- 11. contrato: cada flag que o script passa existe no llama-server real ---
if [[ -z "$REAL_LLAMA" ]]; then
  echo "PULADO: contrato de flags (llama-server real não está no PATH)"
else
  help="$(timeout 60 "$REAL_LLAMA" --help 2>&1)"
  if [[ -z "$help" ]]; then
    echo "FALHA: llama-server --help não imprimiu nada"; fail=1
  else
    for flag in -hf --alias --host --port -np -c --threads -fa -ctk -ctv --no-webui --n-cpu-moe -fit; do
      if ! grep -q -E -- "(^|[[:space:],])${flag}([[:space:],=<[]|$)" <<<"$help"; then
        echo "FALHA: llama-server --help não lista a flag '$flag'"; fail=1
      fi
    done
  fi
fi

[[ $fail -eq 0 ]] && echo "llm_serve_test: ok"
exit $fail
