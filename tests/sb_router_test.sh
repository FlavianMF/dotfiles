#!/bin/bash
# Testes do hook sb-router.sh. Uso: bash tests/sb_router_test.sh
set -u
HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/claude/hooks/sb-router.sh"
tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -r "$tmp"' EXIT
state="$tmp/state"
fail=0

fire() { # fire <session> <prompt> [env...]
    local s="$1" p="$2"; shift 2
    jq -cn --arg s "$s" --arg p "$p" '{session_id:$s, prompt:$p}' | env SECOND_BRAIN_STATE_DIR="$state" "$@" bash "$HOOK"
}
expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
hit() { [[ -n "$1" ]] && echo sim || echo nao; }

out="$(fire a "onde está definida a função parse_config neste repo?")"
expect "busca (pt) sugere" "$(hit "$out")" sim
expect "saída é JSON válido" "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$out")" UserPromptSubmit
expect "espaçamento: prompt seguinte silencioso" "$(hit "$(fire a "liste todos os usos de parse_config no projeto")")" nao
out="$(fire b "rename foo to bar across all the files in src")"
expect "mecânica (en) sugere" "$(hit "$out")" sim
expect "mecânica rotulada" "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out" | grep -c 'tarefa mecânica')" 1
expect "arquitetura silenciosa" "$(hit "$(fire c "onde está o melhor lugar na arquitetura para esta função?")")" nao
expect "revisão silenciosa" "$(hit "$(fire d "find all usages and review whether the design is right")")" nao
expect "prompt curto silencioso" "$(hit "$(fire e "onde está x")")" nao
expect "slash silencioso" "$(hit "$(fire f "/find all the files that use foo please")")" nao
expect "prompt comum silencioso" "$(hit "$(fire g "implemente a função de login com validação de e-mail")")" nao
expect "SB_ROUTER=0 desliga" "$(hit "$(fire h "onde está definida a função parse_config neste repo?" SB_ROUTER=0)")" nao
expect "SECOND_BRAIN_HOOKS=0 desliga" "$(hit "$(fire i "onde está definida a função parse_config neste repo?" SECOND_BRAIN_HOOKS=0)")" nao
touch "$state/DISABLED"
expect "arquivo DISABLED desliga" "$(hit "$(fire j "onde está definida a função parse_config neste repo?")")" nao
rm "$state/DISABLED"
out="$(jq -cn '{session_id:"k", agent_id:"sub", prompt:"onde está definida a função parse_config neste repo?"}' | env SECOND_BRAIN_STATE_DIR="$state" bash "$HOOK")"
expect "subagente silencioso" "$(hit "$out")" nao
expect "JSON inválido silencioso" "$(hit "$(printf 'xx' | env SECOND_BRAIN_STATE_DIR="$state" bash "$HOOK")")" nao
expect "gap=1 sugere sempre" "$(hit "$(fire l "onde está definida a função parse_config neste repo?" SB_ROUTER_GAP=1)")$(hit "$(fire l "onde está definida a função parse_config neste repo?" SB_ROUTER_GAP=1)")" simsim

[[ $fail -eq 0 ]] && echo "ok" || exit 1
