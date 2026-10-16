#!/bin/bash
# UserPromptSubmit: camada de modelo do router de tokens.
#
# Heurística barata (regex, sem LLM): quando o pedido é busca ampla, leitura de muitos arquivos ou
# tarefa mecânica, injeta UMA linha sugerindo delegar a subagente menor. O hook não troca o modelo
# do turno; só lembra a regra de roteamento do AGENTS.md. Pedidos de decisão/arquitetura/revisão
# nunca recebem a linha. No máximo 1 sugestão a cada SB_ROUTER_GAP prompts por sessão (padrão 4).
#
# Nasce ativo. Desliga com SB_ROUTER=0, SECOND_BRAIN_HOOKS=0 (por projeto) ou arquivo DISABLED em
# $SECOND_BRAIN_STATE_DIR (padrão ~/.local/state/claude-hooks/second-brain); vale sem reiniciar.
# Falha em qualquer ponto: não imprime nada e sai 0.

off() { case "${1:-}" in 0|false|off|no|FALSE|OFF|NO) return 0 ;; esac; return 1; }
off "${SB_ROUTER:-}" && exit 0
off "${SECOND_BRAIN_HOOKS:-}" && exit 0
state="${SECOND_BRAIN_STATE_DIR:-$HOME/.local/state/claude-hooks/second-brain}"
[[ -e "$state/DISABLED" ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
[[ "$(jq -r '.agent_id // empty' <<<"$input" 2>/dev/null)" == "" ]] || exit 0
prompt="$(jq -r '.prompt // empty' <<<"$input" 2>/dev/null)" || exit 0
session="$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null | tr -cd 'A-Za-z0-9_-')"
prompt="${prompt,,}"
[[ ${#prompt} -ge 20 && "${prompt:0:1}" != "/" ]] || exit 0
prompt="${prompt:0:2000}"

# Julgamento fica na sessão principal.
judge='arquitetur|architect|design d|trade-?off|decid|decision|revis[ãa]o|review|debug|por que|why |explique|explain|planej|plan |estrat[ée]gi|refator|refactor'
[[ "$prompt" =~ $judge ]] && exit 0

search='(onde|where).{0,40}(est[áa]|defin|usad|is |are )|(find|list|locate|map|busq|procur|ach[ea]|liste|mapei).{0,40}(all|every|todos|todas|usos|uses|usages|refer[êe]ncias|arquivos|files)|(grep|rg) .{0,30}(em todo|across|whole|entire)|(quais|which) (arquivos|files)|leia (todos|tudo)|read (all|every)'
mech='(renomeie|rename|substitua|replace|troque).{0,50}(em todo|em todos|across|all |todas|todos)|(formate|format|reindent|adicione|add) .{0,30}(em todo|em todos|to all|todos os|every)|(mude|change|update|atualize).{0,40}(em todos|todos os|all the |every )'
if [[ "$prompt" =~ $search ]]; then kind="busca ampla"
elif [[ "$prompt" =~ $mech ]]; then kind="tarefa mecânica"
else exit 0; fi

# Espaçamento: contador por sessão (best effort).
gap="${SB_ROUTER_GAP:-4}"; [[ "$gap" =~ ^[0-9]+$ ]] || gap=4
if [[ -n "$session" ]]; then
    mkdir -p "$state/router" 2>/dev/null && chmod 700 "$state/router" 2>/dev/null
    f="$state/router/$session.count"
    n="$(cat "$f" 2>/dev/null)"; [[ "$n" =~ ^[0-9]+$ ]] || n=0
    if (( n > 0 && n < gap )); then echo $((n + 1)) >"$f" 2>/dev/null; exit 0; fi
    echo 1 >"$f" 2>/dev/null
    find "$state/router" -name '*.count' -mtime +7 -delete 2>/dev/null
fi

jq -cn --arg k "$kind" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: ("Router de tokens (" + $k + "): delegue a localização/leitura ampla a um subagente de modelo menor (Explore, cavecrew-investigator ou cavecrew-builder) e traga só a conclusão, sem o dump. Ignore se o pedido exigir julgamento.")}}'
exit 0
