#!/bin/bash
# SessionStart: injeta no contexto as notas do vault mais relevantes para o repo atual.
#
# Só roda com SECOND_BRAIN_HOOKS=1. Delega a busca ao script do vault
# (contrato: session_hint.sh <repo_basename> imprime no máximo 5 linhas e sai 0).
# Silencioso se o vault ou o script não existirem. Sempre exit 0.

[[ "${SECOND_BRAIN_HOOKS:-0}" == "1" ]] || exit 0

input="$(cat)"
vault="${SECOND_BRAIN_VAULT:-$HOME/obsidian_vault}"
hint="$vault/00_META/skills/second-brain-sync/scripts/session_hint.sh"
[[ -f "$hint" ]] || exit 0

cwd=""
command -v jq >/dev/null 2>&1 && cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[[ -d "$cwd" ]] || cwd="${CLAUDE_PROJECT_DIR:-$PWD}"

# Nome do repo principal, mesmo dentro de um worktree (usa o diretório do .git comum).
repo=""
if common="$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
    repo="$(basename "$(dirname "$common")")"
fi
[[ -z "$repo" ]] && repo="$(basename "$cwd")"
# O próprio vault não precisa de dica sobre si mesmo.
[[ "$(cd "$cwd" 2>/dev/null && pwd -P)" == "$(cd "$vault" 2>/dev/null && pwd -P)"* ]] && exit 0

out="$(timeout 4 bash "$hint" "$repo" 2>/dev/null | head -n 5)"
[[ -z "$out" ]] && exit 0

printf 'Second brain: notas do vault relacionadas a "%s" (abra só se forem relevantes à tarefa):\n%s\n' "$repo" "$out"
exit 0
