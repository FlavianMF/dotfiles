#!/bin/bash
# Testes da seção "Traycer: handoff entre chats" em agents/AGENTS.md. Uso: bash tests/agents_md_traycer_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
has() { if ! grep -q -- "$2" <<<"$3"; then echo "FALHA: $1 (faltou '$2' em: $3)"; fail=1; fi; }

FILE="$ROOT/agents/AGENTS.md"
TITLE="## Traycer: handoff entre chats"
MAX_LINES=12

[[ -f "$FILE" ]] || { echo "FALHA: $FILE não existe"; exit 1; }

# Extrai a seção de nível 2 pelo título, ignorando '## ' dentro de blocos de código.
# Para no próximo '## ' e descarta linhas em branco no fim.
section() {
  awk -v title="$1" '
    /^```/ { fence = !fence }
    !fence && /^## / { if (inside) exit; inside = ($0 == title) }
    inside { buf[++n] = $0 }
    END { while (n > 0 && buf[n] ~ /^[[:space:]]*$/) n--; for (i = 1; i <= n; i++) print buf[i] }
  ' "$FILE"
}

# --- 1. a seção existe, uma vez ---
expect "título aparece uma vez" "$(grep -c -x -- "$TITLE" "$FILE")" "1"

# --- 2. tamanho ---
sec="$(section "$TITLE")"
lines="$(wc -l <<<"$sec" | tr -d ' ')"
[[ -n "$sec" ]] || { echo "FALHA: seção vazia"; fail=1; }
if (( lines > MAX_LINES )); then echo "FALHA: seção com $lines linhas (máximo $MAX_LINES)"; fail=1; fi

# --- 3. conteúdo ---
has "cita TRAYCER_EPIC_ID" "TRAYCER_EPIC_ID" "$sec"
has "cita traycer_*" 'traycer_\*' "$sec"
has "cita git-ops" "git-ops" "$sec"
has "cita artifact" "artifact" "$sec"
has "cita 30 linhas" "30 linhas" "$sec"

# --- 4. ordem dos títulos de nível 2 ---
headings="$(awk '/^```/ { fence = !fence } !fence && /^## / { sub(/^## /, ""); print }' "$FILE" | paste -sd'|')"
expect "ordem das seções" "$headings" \
  "Performance e contexto|Segurança|Git|Skills de design de interface|Second brain|Traycer: handoff entre chats|ECC por projeto"

# --- 5. a seção Git tem a linha do git-ops ---
git_sec="$(section "## Git")"
has "seção Git cita git-ops" "git-ops" "$git_sec"
expect "seção Git: uma linha com git-ops" "$(grep -c -- 'git-ops' <<<"$git_sec")" "1"

[[ $fail -eq 0 ]] && echo "agents_md_traycer_test: ok"
exit $fail
