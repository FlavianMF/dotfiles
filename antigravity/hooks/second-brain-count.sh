#!/bin/bash
# agy PostToolUse (todas as ferramentas): conta as escritas da sessão para o hook Stop.
#
# Anexa uma linha por evento em <estado>/agy/<conversationId>.state:
#   w  ferramenta de edição, ou run_command com comando de escrita
#   s  run_command que já enfileirou ou sincronizou o second brain
# O agy não expõe o transcript num formato estável, então o Stop lê este arquivo.
# Grava só uma letra por evento, nunca comando nem caminho. Responde `{}`.
# Liga por padrão; SECOND_BRAIN_HOOKS=0 desliga. Sempre exit 0.

done_() { echo '{}'; exit 0; }

[[ "${SECOND_BRAIN_HOOKS:-1}" == "0" ]] && done_
command -v jq >/dev/null 2>&1 || done_

# Mesma regex do hook Claude (claude/hooks/second-brain-stop.sh).
bash_write='(^|[;&|[:space:]])(sed[[:space:]]+-[a-zA-Z]*i|tee|git[[:space:]]+(commit|mv|rm)|cp|mv|rm|install|chmod|patch)([[:space:]]|$)|python3?[[:space:]]+-([[:space:]]|$)|[^<>=-]>>?[[:space:]]*[^&[:space:]]'
synced_re='vault_sync\.py|sb\.py (sync|candidate add)'
edit_tools='^(write_file|edit_file|write_to_file|replace_file_content|multi_replace_file_content|apply_patch|create_file|delete_file|edit_notebook)$'

IFS=$'\t' read -r session tool cmd < <(
    jq -r '[(.conversationId // ""), (.toolCall.name // ""), ((.toolCall.args.CommandLine // "") | gsub("[\t\n]"; " "))] | @tsv' 2>/dev/null
)
session="${session//[^A-Za-z0-9_-]/}"
[[ -n "$session" && -n "$tool" ]] || done_

event=""
if [[ "$tool" =~ $edit_tools ]]; then
    event=w
elif [[ "$tool" == run_command ]]; then
    if [[ "$cmd" =~ $synced_re ]]; then
        event=s
    elif [[ "$cmd" =~ $bash_write ]]; then
        event=w
    fi
fi
[[ -n "$event" ]] || done_

state_dir="${SECOND_BRAIN_STATE_DIR:-$HOME/.local/state/second-brain}/agy"
(umask 077; mkdir -p "$state_dir") 2>/dev/null || done_
(umask 077; echo "$event" >>"$state_dir/$session.state") 2>/dev/null
done_
