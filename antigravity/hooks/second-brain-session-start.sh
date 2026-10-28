#!/bin/bash
# agy SessionStart: injeta no contexto as notas do vault mais relevantes para o repo atual.
#
# Lê o JSON do agy no stdin (`workspacePaths`) e imprime `{"injectSteps":[...]}`; sem nota
# imprime `{}`. Delega a busca a session_hint.sh (contrato: <repo_basename> -> no máximo 5 linhas).
# Liga por padrão (o agy não tem `env` em settings); SECOND_BRAIN_HOOKS=0 desliga.
# Sempre exit 0.

none() { echo '{}'; exit 0; }

[[ "${SECOND_BRAIN_HOOKS:-1}" == "0" ]] && none
command -v jq >/dev/null 2>&1 || none

vault="${SECOND_BRAIN_VAULT:-$HOME/obsidian_vault}"
hint="$vault/00_META/skills/second-brain-sync/scripts/session_hint.sh"
[[ -f "$hint" ]] || none

cwd="$(jq -r '.workspacePaths[0] // empty' 2>/dev/null)"
[[ -d "$cwd" ]] || cwd="$PWD"

# Nome do repo principal, mesmo dentro de um worktree (mesma lógica do hook do Claude).
repo=""
if common="$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
    case "$common" in
        */.git/modules/*) repo="$(basename "$common")" ;;
        *) repo="$(basename "$(dirname "$common")")" ;;
    esac
fi
[[ -z "$repo" ]] && repo="$(basename "$cwd")"

# O próprio vault não precisa de dica sobre si mesmo.
real_cwd="$(cd "$cwd" 2>/dev/null && pwd -P)"
real_vault="$(cd "$vault" 2>/dev/null && pwd -P)"
[[ -n "$real_cwd" && ( "$real_cwd" == "$real_vault" || "$real_cwd" == "$real_vault"/* ) ]] && none

out="$(timeout 4 bash "$hint" "$repo" 2>/dev/null | head -n 5)"
[[ -z "$out" ]] && none

text="$(printf 'Second brain: notas do vault relacionadas a "%s" (abra só se forem relevantes à tarefa):\n%s\n' "$repo" "$out")"
jq -cn --arg t "$text" '{injectSteps: [{systemMessage: {systemMessage: $t}}]}'
exit 0
