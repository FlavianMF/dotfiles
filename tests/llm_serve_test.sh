#!/bin/bash
# Testes de bin/llm-serve com llama-server, curl e jq falsos no PATH. Uso: bash tests/llm_serve_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT
fail=0
expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
has() { if ! grep -q -- "$2" <<<"$3"; then echo "FALHA: $1 (faltou '$2' em: $3)"; fail=1; fi; }

SERVE="$ROOT/bin/llm-serve"
[[ -f "$SERVE" ]] || { echo "FALHA: $SERVE não existe"; exit 1; }

# Sandbox: HOME vazio e PATH com os falsos na frente. Nenhum falso toca a rede.
export HOME="$tmp/home"
mkdir -p "$HOME" "$tmp/bin"
export FAKE_LOG="$tmp/llama-args"
export FAKE_CURL_LOG="$tmp/curl-calls"

cat >"$tmp/bin/llama-server" <<'EOF'
#!/bin/bash
echo "$*" >>"$FAKE_LOG"
EOF
# curl falso: /health responde conforme FAKE_HEALTH; o resto (Ollama) falha como se estivesse fora.
cat >"$tmp/bin/curl" <<'EOF'
#!/bin/bash
echo "$*" >>"$FAKE_CURL_LOG"
case "$*" in
  */health*) [[ "${FAKE_HEALTH:-down}" == up ]] && exit 0 ;;
esac
exit 22
EOF
cat >"$tmp/bin/jq" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:/usr/bin:/bin"

reset() { rm -f "$FAKE_LOG" "$FAKE_CURL_LOG"; unset LLM_N_CPU_MOE LLM_PORT LLM_CTX LLM_MAIN_HF LLM_MAIN_ALIAS; export FAKE_HEALTH=down; }
args() { cat "$FAKE_LOG" 2>/dev/null; }

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

# --- 4. perfil main ---
reset
out="$(bash "$SERVE" main 2>&1)"; rc=$?
expect "main sai 0" "$rc" "0"
a="$(args)"
has "main usa -hf" "-hf ggml-org/gpt-oss-20b-GGUF" "$a"
has "main usa --alias" "--alias gpt-oss-20b" "$a"
has "main usa -np 1" "-np 1" "$a"
has "main usa --fit on" "--fit on" "$a"
has "main escuta em 127.0.0.1:8080" "--host 127.0.0.1 --port 8080" "$a"
if grep -q -- '--n-cpu-moe' <<<"$a"; then echo "FALHA: main sem LLM_N_CPU_MOE trouxe --n-cpu-moe"; fail=1; fi

# --- 5. LLM_N_CPU_MOE ---
reset
LLM_N_CPU_MOE=7 bash "$SERVE" main >/dev/null 2>&1; rc=$?
expect "N_CPU_MOE sai 0" "$rc" "0"
has "N_CPU_MOE acrescenta --n-cpu-moe 7" "--n-cpu-moe 7" "$(args)"

# --- 6. .gguf existente e USUARIO/REPO ---
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

# --- 7. argumentos extras passam adiante ---
reset
bash "$SERVE" main --foo bar >/dev/null 2>&1
has "args extras chegam ao llama-server" "--foo bar" "$(args)"

# --- 8. isolamento ---
[[ ! -e "$HOME/.traycer" ]] || { echo "FALHA: teste criou ~/.traycer"; fail=1; }

[[ $fail -eq 0 ]] && echo "llm_serve_test: ok"
exit $fail
