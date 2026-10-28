#!/bin/bash
# Testes de traycer/install_guide.sh e da chamada em traycer/install.sh. Uso: bash tests/traycer_guide_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT
fail=0
expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
has() { if ! grep -q -- "$2" <<<"$3"; then echo "FALHA: $1 (faltou '$2' em: $3)"; fail=1; fi; }

SRC="$ROOT/traycer/agent-selection-guide.md"
INSTALL="$ROOT/traycer/install_guide.sh"
[[ -f "$SRC" ]] || { echo "FALHA: $SRC não existe"; exit 1; }

n=0
# Cria um HOME de sandbox novo e o exporta (cada caso isola seus backups por timestamp).
new_home() { n=$((n + 1)); H="$tmp/home$n"; mkdir "$H"; export HOME="$H"; DEST="$H/.traycer/agent-selection-guide.md"; }
count_bak() { find "$HOME/.traycer" -maxdepth 1 -name 'agent-selection-guide.md.bak*' 2>/dev/null | wc -l | tr -d ' '; }
listing() { find "$HOME" | sort; }

# --- 1. instalação nova ---
new_home
out="$(bash "$INSTALL" 2>&1)"; rc=$?
expect "instalação nova sai 0" "$rc" "0"
[[ -e "$DEST" ]] || { echo "FALHA: destino não existe"; fail=1; }
[[ -f "$DEST" && ! -L "$DEST" ]] || { echo "FALHA: destino não é arquivo regular"; fail=1; }
cmp -s "$SRC" "$DEST" || { echo "FALHA: destino difere do repo"; fail=1; }
expect "instalação nova sem backup" "$(count_bak)" "0"

# --- 2. reinstalação idempotente ---
out="$(bash "$INSTALL" 2>&1)"; rc=$?
expect "reinstalação sai 0" "$rc" "0"
has "reinstalação diz já atualizado" "already up to date" "$out"
expect "reinstalação sem backup" "$(count_bak)" "0"
cmp -s "$SRC" "$DEST" || { echo "FALHA: destino difere após reinstalação"; fail=1; }

# --- 3. destino divergente ---
new_home
mkdir "$HOME/.traycer"
echo "texto divergente" >"$DEST"
out="$(bash "$INSTALL" 2>&1)"; rc=$?
expect "divergente sai 0" "$rc" "0"
cmp -s "$SRC" "$DEST" || { echo "FALHA: destino não voltou ao repo"; fail=1; }
expect "divergente cria um backup" "$(count_bak)" "1"
bak="$(find "$HOME/.traycer" -maxdepth 1 -name 'agent-selection-guide.md.bak.*' | head -n1)"
expect "backup guarda o texto divergente" "$(cat "$bak" 2>/dev/null)" "texto divergente"

# --- 3b. destino symlink ---
new_home
mkdir "$HOME/.traycer"
echo "alvo do link" >"$tmp/alvo.md"
ln -s "$tmp/alvo.md" "$DEST"
out="$(bash "$INSTALL" 2>&1)"; rc=$?
expect "symlink sai 0" "$rc" "0"
[[ -f "$DEST" && ! -L "$DEST" ]] || { echo "FALHA: destino continua symlink"; fail=1; }
cmp -s "$SRC" "$DEST" || { echo "FALHA: destino symlink não virou cópia do repo"; fail=1; }
expect "alvo do link intacto" "$(cat "$tmp/alvo.md")" "alvo do link"
expect "symlink gera um backup" "$(count_bak)" "1"
bak="$(find "$HOME/.traycer" -maxdepth 1 -name 'agent-selection-guide.md.bak.*' | head -n1)"
[[ -L "$bak" ]] || { echo "FALHA: backup não é o symlink antigo"; fail=1; }

# --- 4. --dry-run ---
new_home
out="$(bash "$INSTALL" --dry-run 2>&1)"; rc=$?
expect "dry-run novo sai 0" "$rc" "0"
has "dry-run novo imprime [dry-run]" "\[dry-run\]" "$out"
[[ ! -e "$HOME/.traycer" ]] || { echo "FALHA: dry-run criou ~/.traycer"; fail=1; }
mkdir "$HOME/.traycer"
echo "texto divergente" >"$DEST"
before="$(listing)"
out="$(bash "$INSTALL" --dry-run 2>&1)"; rc=$?
expect "dry-run divergente sai 0" "$rc" "0"
has "dry-run divergente imprime [dry-run]" "\[dry-run\]" "$out"
expect "dry-run mantém o destino" "$(cat "$DEST")" "texto divergente"
expect "dry-run mantém a lista de arquivos" "$(listing)" "$before"
expect "dry-run sem backup" "$(count_bak)" "0"

# --- 5. meta.json intacto ---
new_home
mkdir "$HOME/.traycer"
META="$HOME/.traycer/.agent-selection-guide.meta.json"
printf '{"hash":"abc","n":1}\n' >"$META"
meta_before="$(cat "$META")"
bash "$INSTALL" >/dev/null 2>&1
bash "$INSTALL" >/dev/null 2>&1
echo "texto divergente" >"$DEST"
bash "$INSTALL" --dry-run >/dev/null 2>&1
bash "$INSTALL" >/dev/null 2>&1
expect "meta.json intacto" "$(cat "$META")" "$meta_before"

# --- 6. opção desconhecida ---
new_home
bash "$INSTALL" --bogus >/dev/null 2>&1; rc=$?
expect "opção desconhecida sai 2" "$rc" "2"

# --- 7. integração com install.sh --dry-run ---
new_home
out="$(timeout 120 bash "$ROOT/traycer/install.sh" --dry-run </dev/null 2>&1)"; rc=$?
expect "install.sh --dry-run sai 0" "$rc" "0"
has "install.sh lista a cópia" "\[dry-run\] copy" "$out"
has "install.sh cita o guia" "agent-selection-guide.md" "$out"
[[ ! -e "$HOME/.traycer" ]] || { echo "FALHA: install.sh --dry-run criou ~/.traycer"; fail=1; }
[[ ! -e "$HOME/.local" ]] || { echo "FALHA: install.sh --dry-run criou ~/.local"; fail=1; }

# --- 8. conteúdo do guia ---
guide="$(cat "$SRC")"
has "guia cita haiku" "haiku" "$guide"
has "guia cita low" "low" "$guide"
has "guia cita artifact" "artifact" "$guide"

# --- 9. roteamento por cota e camada local opt-in ---
for term in "Quota guard" "80%" "95%" "100k" "gemini-3.8-flash" "claude-opus-5.5" \
  "claude-sonnet-5.5" "fable" "50 diff lines" "150 lines" "Local (opt-in)" "llamacpp" \
  "8080" "one local agent" "Do not start the server"; do
  has "guia cita '$term'" "$term" "$guide"
done
# Combinações GPT e o nome inexistente "Mythos" ficam fora enquanto o codex está sem login.
for term in "GPT Sol" "GPT Terra" "GPT Luna" "Mythos" "Local first"; do
  if grep -q -- "$term" <<<"$guide"; then echo "FALHA: guia ainda cita '$term'"; fail=1; fi
done
size="$(wc -c <"$SRC" | tr -d ' ')"
(( size <= 5120 )) || { echo "FALHA: guia com $size bytes, teto de 5120"; fail=1; }

# Amarre o id do guia ao provider do opencode e aos padrões do llm-serve.
SERVE="$ROOT/bin/llm-serve"
OPENCODE="$ROOT/opencode/opencode.json"
model_id="$(grep -o 'llamacpp:[A-Za-z0-9._-]*' <<<"$guide" | head -n1)"
model_key="${model_id#llamacpp:}"
[[ -n "$model_key" ]] || { echo "FALHA: guia sem id llamacpp:<modelo>"; fail=1; }
expect "provider llamacpp tem o modelo do guia" \
  "$(jq -r --arg k "$model_key" '.provider.llamacpp.models | has($k)' "$OPENCODE")" "true"
serve_alias="$(sed -n 's/.*LLM_MAIN_ALIAS:-\([^}]*\)}.*/\1/p' "$SERVE" | head -n1)"
expect "alias padrão do llm-serve é o modelo do guia" "$serve_alias" "$model_key"
serve_port="$(sed -n 's/^PORT="${LLM_PORT:-\([0-9]*\)}"/\1/p' "$SERVE")"
guide_port="$(grep -o '127\.0\.0\.1:[0-9]*' <<<"$guide" | head -n1 | cut -d: -f2)"
[[ -n "$serve_port" ]] || { echo "FALHA: llm-serve sem LLM_PORT padrão"; fail=1; }
expect "porta do guia é o LLM_PORT padrão do llm-serve" "$guide_port" "$serve_port"

[[ $fail -eq 0 ]] && echo "traycer_guide_test: ok"
exit $fail
