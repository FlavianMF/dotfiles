#!/bin/bash
# agy Stop: lembra de destilar a sessão para o vault quando houve várias escritas
# e nenhum `vault_sync.py`, `sb.py sync` ou `sb.py candidate add`.
#
# Lê o estado que second-brain-count.sh grava (<estado>/agy/<conversationId>.state).
# Só age no fim normal (`terminationReason` = NO_TOOL_CALL). Lembra no máximo uma vez por sessão:
# imprime `{"decision":"continue","reason":...}`, que faz o agy responder ao lembrete.
# Qualquer outro caso imprime `{}` e deixa o agy parar.
# Liga por padrão; SECOND_BRAIN_HOOKS=0 desliga. Env: SECOND_BRAIN_MIN_EDITS (padrão 5).
# Apaga estados com mais de 7 dias. Sempre exit 0.

none() { echo '{}'; exit 0; }

[[ "${SECOND_BRAIN_HOOKS:-1}" == "0" ]] && none
command -v jq >/dev/null 2>&1 || none

vault="${SECOND_BRAIN_VAULT:-$HOME/obsidian_vault}"
[[ -d "$vault" ]] || none

IFS=$'\t' read -r session reason < <(
    jq -r '[(.conversationId // ""), (.terminationReason // "")] | @tsv' 2>/dev/null
)
session="${session//[^A-Za-z0-9_-]/}"
[[ -n "$session" && "$reason" == "NO_TOOL_CALL" ]] || none

state_dir="${SECOND_BRAIN_STATE_DIR:-$HOME/.local/state/second-brain}/agy"
state="$state_dir/$session.state"
marker="$state_dir/$session.reminded"
[[ -f "$state" && ! -f "$marker" ]] || none
grep -qx s "$state" 2>/dev/null && none

min_edits="${SECOND_BRAIN_MIN_EDITS:-5}"
[[ "$min_edits" =~ ^[0-9]+$ ]] || min_edits=5
edits="$(grep -cx w "$state" 2>/dev/null)"
[[ "$edits" =~ ^[0-9]+$ ]] || none
(( edits >= min_edits )) || none

(umask 077; : >"$marker") 2>/dev/null
find "$state_dir" -type f -mtime +7 -delete 2>/dev/null

msg="Esta sessão fez ${edits} edições (arquivos e comandos de escrita) e ainda não enfileirou nada para o second brain. Se a tarefa de dev terminou e gerou padrão, decisão ou armadilha reutilizável, acrescente candidatos à fila com sb.py candidate add (não escreva no vault; o usuário promove na revisão). Se não houve nada reutilizável, apenas encerre sem comentar."
jq -cn --arg msg "$msg" '{decision: "continue", reason: $msg}'
exit 0
