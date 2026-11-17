#!/bin/bash
# Valida os layouts do Herdr app: JSON válido, ids únicos e `active` de cada stack apontando
# para um filho existente.
# Uso: bash tests/herdr_layouts_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
command -v jq >/dev/null || { echo "SKIP: jq ausente"; exit 0; }
for f in "$ROOT"/herdr/app/layouts/*.json; do
  n="$(basename "$f")"
  jq empty "$f" 2>/dev/null || { echo "FALHA: $n não é JSON válido"; fail=1; continue; }
  dup="$(jq -r '[.. | objects | select(.id? != null) | .id] | group_by(.) | map(select(length > 1) | .[0]) | join(", ")' "$f")"
  [[ -z "$dup" ]] || { echo "FALHA: $n tem ids repetidos: $dup"; fail=1; }
  bad="$(jq -r '[.. | objects | select(.type? == "stack" and .active? != null) | select(.active as $a | ([.children[]?.id] | index($a)) == null) | "\(.id)->\(.active)"] | join(", ")' "$f")"
  [[ -z "$bad" ]] || { echo "FALHA: $n tem stack com active inexistente: $bad"; fail=1; }
done
for id in panel panel-todo; do
  jq -e --arg i "$id" '[.. | objects | select(.id? == $i)] | length == 1' "$ROOT/herdr/app/layouts/multiproject.json" >/dev/null || { echo "FALHA: multiproject.json sem o nó $id"; fail=1; }
done
((fail)) && exit 1
echo "ok: herdr_layouts_test"
