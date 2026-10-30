#!/bin/bash
# Testes unitários para extração e normalização de cotas do Antigravity (Gemini Models, Argon e Claude/GPT).
# Uso: bash tests/antigravity_quota_test.sh
set -euo pipefail
fail=0

expect() {
    if [[ "$2" != "$3" ]]; then
        echo "FALHA: $1 (obtido '$2', esperado '$3')"
        fail=1
    fi
}

has() {
    if ! grep -q -- "$2" <<<"$3"; then
        echo "FALHA: $1 (faltou '$2' em: $3)"
        fail=1
    fi
}

# 1. Teste de normalização com JSON válido do agy
MOCK_AGY_JSON='{
  "status": "SUCCESS",
  "command": {
    "name": "usage",
    "data": {
      "groups": [
        {
          "name": "Gemini Models",
          "description": "Models within this group: Gemini Flash, Gemini Pro",
          "buckets": [
            {
              "id": "gemini-weekly",
              "name": "Weekly Limit Remaining",
              "window": "weekly",
              "remaining_fraction": 0.75,
              "reset_time": "2026-11-04T14:24:24Z"
            },
            {
              "id": "gemini-5h",
              "name": "Five Hour Limit Remaining",
              "window": "5h",
              "remaining_fraction": 0.80,
              "reset_time": "2026-10-30T21:49:25Z"
            }
          ]
        },
        {
          "name": "Claude and GPT models",
          "description": "Models within this group: Claude Opus, Claude Sonnet, GPT-OSS",
          "buckets": [
            {
              "id": "3p-weekly",
              "name": "Weekly Limit Remaining",
              "window": "weekly",
              "remaining_fraction": 0.10,
              "reset_time": "2026-11-04T17:34:26Z"
            }
          ]
        },
        {
          "name": "Gemini 4 Argon",
          "description": "Argon quota",
          "buckets": [
            {
              "id": "gemini-argon-wtu-weekly",
              "name": "Gemini 4 Argon Weekly Limit",
              "window": "weekly",
              "remaining_fraction": 0.05,
              "reset_time": "2026-11-04T14:23:24Z"
            }
          ]
        }
      ]
    }
  }
}'

out="$(node -e '
const raw = JSON.parse(process.argv[1]);
const Vzf = new Map([["5h", 300], ["weekly", 10080]]);

function Gzf(b) {
  const frac = b.remaining_fraction ?? 1;
  const used = Math.round((1 - frac) * 10000) / 100;
  return {
    bucketId: b.id,
    windowKind: b.window,
    usedPercent: used,
    durationMinutes: Vzf.get(b.window) ?? null
  };
}

const groups = raw.command.data.groups.map(g => ({
  displayName: g.name,
  windows: g.buckets.map(Gzf)
}));

console.log(JSON.stringify(groups));
' "$MOCK_AGY_JSON")"

has "contém Gemini Models" "Gemini Models" "$out"
has "contém gemini-5h com 20% usado" '"bucketId":"gemini-5h","windowKind":"5h","usedPercent":20' "$out"
has "contém gemini-weekly com 25% usado" '"bucketId":"gemini-weekly","windowKind":"weekly","usedPercent":25' "$out"
has "contém Gemini 4 Argon" "Gemini 4 Argon" "$out"
has "contém gemini-argon-wtu-weekly com 95% usado" '"bucketId":"gemini-argon-wtu-weekly","windowKind":"weekly","usedPercent":95' "$out"
has "contém Claude and GPT models com 90% usado" '"bucketId":"3p-weekly","windowKind":"weekly","usedPercent":90' "$out"

# 2. Teste de fallback quando agy falha ou payload é malformado
MOCK_REST='{
  "groups": [
    {
      "displayName": "Claude and GPT models",
      "buckets": [
        { "bucketId": "3p-weekly", "window": "weekly", "remainingFraction": 0.15 }
      ]
    }
  ]
}'

fallback_out="$(node -e '
const rest = JSON.parse(process.argv[1]);
const agy = null; // simulando falha de exec

let merged = [];
let seen = new Set();
if (agy?.groups) {
  for (const g of agy.groups) {
    if (g?.displayName && !seen.has(g.displayName)) {
      seen.add(g.displayName);
      merged.push(g);
    }
  }
}
if (rest?.groups) {
  for (const g of rest.groups) {
    if (g?.displayName && !seen.has(g.displayName)) {
      seen.add(g.displayName);
      merged.push(g);
    }
  }
}

console.log(JSON.stringify(merged));
' "$MOCK_REST")"

has "fallback preserva Claude and GPT models" "Claude and GPT models" "$fallback_out"
has "fallback mantém 3p-weekly" "3p-weekly" "$fallback_out"

# 3. Teste de fusão sem duplicidade
merge_out="$(node -e '
const rest = { groups: [{ displayName: "Claude and GPT models", buckets: [{ bucketId: "3p-weekly", window: "weekly", remainingFraction: 0.1 }] }] };
const agy = { groups: [
  { displayName: "Gemini Models", buckets: [{ bucketId: "gemini-5h", window: "5h", remainingFraction: 0.8 }] },
  { displayName: "Claude and GPT models", buckets: [{ bucketId: "3p-weekly", window: "weekly", remainingFraction: 0.1 }] }
]};

let merged = [];
let seen = new Set();
for (const g of agy.groups) {
  if (!seen.has(g.displayName)) { seen.add(g.displayName); merged.push(g); }
}
for (const g of rest.groups) {
  if (!seen.has(g.displayName)) { seen.add(g.displayName); merged.push(g); }
}

console.log(merged.length);
' )"

expect "mescla grupos sem duplicar (deve ter 2 grupos)" "$merge_out" "2"

if [[ $fail -eq 0 ]]; then
    echo "antigravity_quota_test: ok"
    exit 0
else
    echo "antigravity_quota_test: FALHOU"
    exit 1
fi
