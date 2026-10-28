#!/bin/bash
# Testes do agente claude/agents/git-ops.md e do link no install.sh. Uso: bash tests/git_ops_agent_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -r "$tmp"' EXIT
fail=0
expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
has() { if ! grep -q -- "$2" <<<"$3"; then echo "FALHA: $1 (faltou '$2' em: $3)"; fail=1; fi; }

AGENT="$ROOT/claude/agents/git-ops.md"
mkdir "$tmp/home"

# --- frontmatter ---
[[ -f "$AGENT" ]] || { echo "FALHA: $AGENT não existe"; exit 1; }
expect "primeira linha é ---" "$(head -n1 "$AGENT")" "---"
# Frontmatter = linhas entre o primeiro e o segundo '---'.
front="$(awk 'NR==1 && $0=="---" {inside=1; next} inside && $0=="---" {exit} inside' "$AGENT")"
has "frontmatter fecha" "name:" "$front"
expect "name no frontmatter" "$(grep -c '^name: git-ops$' <<<"$front")" "1"
expect "model no frontmatter" "$(grep -c '^model: haiku$' <<<"$front")" "1"
expect "tools no frontmatter" "$(grep -c '^tools: Bash, Read, Grep$' <<<"$front")" "1"
desc="$(sed -n 's/^description:[[:space:]]*//p' <<<"$front")"
[[ -n "$desc" ]] || { echo "FALHA: description vazia"; fail=1; }

# --- corpo ---
body="$(awk 'NR==1 && $0=="---" {inside=1; next} inside && $0=="---" {inside=0; next} !inside' "$AGENT")"
has "corpo cita --ff-only" "--ff-only" "$body"
has "corpo cita git stash com tag" "git stash push -u -m" "$body"
has "corpo proíbe atribuição de IA" "Nunca inclua atribuição de IA" "$body"

# --- install.sh --dry-run ---
out="$(HOME="$tmp/home" timeout 120 bash "$ROOT/install.sh" --dry-run </dev/null 2>&1)"; rc=$?
expect "dry-run sai 0" "$rc" "0"
has "dry-run lista o destino" "$tmp/home/.claude/agents/git-ops.md" "$out"
has "dry-run lista a origem" "claude/agents/git-ops.md" "$out"
[[ ! -e "$tmp/home/.claude/agents" ]] || { echo "FALHA: dry-run criou $tmp/home/.claude/agents"; fail=1; }

[[ $fail -eq 0 ]] && echo "git_ops_agent_test: ok"
exit $fail
