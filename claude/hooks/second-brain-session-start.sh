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

# Estado do ECC neste projeto (~20 tokens): o agente não deve ligar/desligar por conta própria.
ecc_script="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../ecc-project.sh"
ecc_line="$(timeout 2 bash "$ecc_script" status "$cwd" --short 2>/dev/null)"
[[ -n "$ecc_line" ]] && printf '%s Só o usuário muda (make ecc-on|ecc-off DIR=...).\n' "$ecc_line"

# Nome do repo principal, mesmo dentro de um worktree (usa o diretório do .git comum).
repo=""
if common="$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
    repo="$(basename "$(dirname "$common")")"
fi
[[ -z "$repo" ]] && repo="$(basename "$cwd")"
# O próprio vault não precisa de dica sobre si mesmo.
# Caminho exato ou filho: um irmão como ~/obsidian_vault2 não casa.
real_cwd="$(cd "$cwd" 2>/dev/null && pwd -P)"
real_vault="$(cd "$vault" 2>/dev/null && pwd -P)"
[[ -n "$real_cwd" && ( "$real_cwd" == "$real_vault" || "$real_cwd" == "$real_vault"/* ) ]] && exit 0

out="$(timeout 4 bash "$hint" "$repo" 2>/dev/null | head -n 5)"
[[ -z "$out" ]] && exit 0

# Registra o que o L0 mostrou no arquivo de dedupe do L1 (prompt_hint.sh); numa sessão que
# volta de compactação a janela perdeu o conteúdo, então o arquivo recomeça vazio.
if command -v jq >/dev/null 2>&1; then
    session="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
    session="${session//[^A-Za-z0-9_-]/}"
    source_kind="$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null)"
    state_dir="${SECOND_BRAIN_STATE_DIR:-$HOME/.local/state/second-brain}"
    if [[ -n "$session" ]] && (umask 077; mkdir -p "$state_dir") 2>/dev/null; then
        seen_file="$state_dir/$session.seen"
        [[ "$source_kind" == "compact" ]] && : >"$seen_file"
        printf '%s\n' "$out" | sed -n 's/.* — \(.*\) (\([^()]*\))$/\1/p' >>"$seen_file" 2>/dev/null
        chmod 600 "$seen_file" 2>/dev/null
    fi
fi

printf 'Second brain: notas do vault relacionadas a "%s" (abra só se forem relevantes à tarefa):\n%s\n' "$repo" "$out"
exit 0
