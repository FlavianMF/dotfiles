#!/bin/bash
# Teste A/B do STE-80: 5 prompts fixos, com o plugin desligado (STE80=0) e ligado.
#
# Uso: claude/ste80-ab.sh [rodadas]   (padrão: 1 rodada; cada rodada = 10 chamadas de `claude -p`)
# Saída: tabela por prompt e média por braço (palavras, frases, palavras por frase,
# conformidade do `ste80 lint`, custo em USD). Respostas completas em $OUT/<braço>-<n>.txt.
# Roda num diretório vazio fora do git, com --no-session-persistence, para não herdar contexto de projeto.
set -euo pipefail

ROUNDS="${1:-1}"
MODEL="${STE80_AB_MODEL:-sonnet}"
PLUGIN_DIR="$(ls -d "$HOME"/.claude/plugins/marketplaces/ste80/plugins/ste80 2>/dev/null | head -1)"
LINT="python3 $PLUGIN_DIR/scripts/ste80.py lint - --json"
OUT="${STE80_AB_OUT:-$(mktemp -d)}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

PROMPTS=(
  "Explique a diferença entre um symlink e um hard link no Linux."
  "Como eu descubro por que um processo Node está usando muita memória?"
  "Quais são os riscos de usar git push --force numa branch compartilhada?"
  "Escreva um runbook curto para reiniciar um serviço systemd que travou."
  "Compare SQLite e PostgreSQL para uma aplicação pequena com um usuário."
)

run_arm() { # run_arm <braço> <STE80> <n> <prompt>
  local arm="$1" flag="$2" n="$3" prompt="$4" json text cost
  json="$(cd "$WORK" && STE80="$flag" command claude -p "$prompt" --model "$MODEL" \
    --no-session-persistence --output-format json 2>/dev/null)"
  text="$(jq -r '.result // ""' <<<"$json")"
  cost="$(jq -r '.total_cost_usd // 0' <<<"$json")"
  printf '%s\n' "$text" > "$OUT/$arm-$n.txt"
  local words sents ratio
  words="$(wc -w <<<"$text" | tr -d ' ')"
  read -r sents ratio < <($LINT <<<"$text" | jq -r '"\(.sentences) \(.ratio)"')
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$arm" "$n" "$words" "$sents" "$ratio" "$cost"
}

TSV="$OUT/results.tsv"
printf 'arm\tprompt\twords\tsentences\tconform\tcost_usd\n' > "$TSV"
for ((r = 1; r <= ROUNDS; r++)); do
  for i in "${!PROMPTS[@]}"; do
    n=$((i + 1))
    run_arm off 0 "$n" "${PROMPTS[$i]}" >> "$TSV"
    run_arm on 1 "$n" "${PROMPTS[$i]}" >> "$TSV"
  done
done

echo "Resultados por chamada: $TSV"
echo
printf '%-4s %7s %10s %12s %9s %9s\n' braço n_resp palavras frases palav/frase conforme
for arm in off on; do
  awk -F'\t' -v arm="$arm" 'NR>1 && $1==arm { n++; w+=$3; s+=$4; c+=$5; k+=$6 }
    END { if (n) printf "%-4s %7d %10.0f %12.0f %9.1f %8.0f%%  custo médio $%.4f\n", arm, n, w/n, s/n, (s? w/s : 0), 100*c/n, k/n }' "$TSV"
done
