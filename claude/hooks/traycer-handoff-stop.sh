#!/bin/bash
# Stop: lembra de gravar um artifact `spec` do épico Traycer depois de um commit.
#
# Só roda dentro do Traycer (TRAYCER_EPIC_ID definido e a pasta artifacts do épico existe).
# Gatilho: o transcript tem um tool_use do assistente que seja `Bash` com `git commit`
# ou `Agent` com subagent_type `git-ops` e prompt que cita `commit` (sem diferenciar maiúsculas).
# Suprime se a sessão já gravou em ~/.traycer/epics/<id>/artifacts/ (Write/Edit/MultiEdit,
# ou Bash que cita o caminho e tem um padrão de escrita: sed -i, tee, cp, mv, install, `>`/`>>`).
# A ordem não importa: um artifact gravado antes do commit também cala o lembrete,
# porque a sessão já registrou contexto. `echo git commit` ainda dispara (custo aceito).
# Nunca grava o artifact: só lembra. Só olha tool_use do assistente, porque o AGENTS.md
# injetado no transcript cita esses mesmos comandos.
#
# Pula sessões filhas (a primeira mensagem de usuário contém `[traycer:agent-message]`):
# elas herdam TRAYCER_EPIC_ID, mas o artifact pertence ao agente pai.
# Lembra no máximo uma vez por sessão (marcador) e respeita stop_hook_active.
# Custo conhecido: um `block` aqui e outro do second-brain-stop.sh no mesmo Stop
# forçam um turno extra: o Stop seguinte chega com stop_hook_active e os dois hooks saem cedo.
# O marcador por sessão limita este hook a um lembrete.
# Desligue com TRAYCER_EPIC_HOOK=0. Sempre exit 0.

[[ "${TRAYCER_EPIC_HOOK:-1}" == "0" ]] && exit 0
epic="${TRAYCER_EPIC_ID:-}"
[[ -n "$epic" ]] || exit 0
# O id vira parte de um caminho: recusa qualquer coisa fora de [A-Za-z0-9_-].
[[ "$epic" =~ ^[A-Za-z0-9_-]+$ ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
stop_active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)"
[[ "$stop_active" == "true" ]] && exit 0

root="$HOME/.traycer/epics/$epic/artifacts"
[[ -d "$root" ]] || exit 0

transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
transcript="${transcript/#\~/$HOME}"
[[ -f "$transcript" ]] || exit 0

session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9_-')"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude-hooks/traycer"
marker="$state_dir/${session_id:-unknown}.reminded"
[[ -n "$session_id" && -f "$marker" ]] && exit 0

# Sessão filha: lê só a primeira linha da primeira mensagem de usuário (string ou blocos de texto) e procura o marcador nela.
first_user="$(jq -R -r 'fromjson? | select(.type == "user")
    | .message.content | if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join("\n")) end' \
    "$transcript" 2>/dev/null | head -n1)"
[[ "$first_user" == *"[traycer:agent-message]"* ]] && exit 0

# Formas literais do caminho que um comando Bash pode citar (`~` e `$HOME` sem expandir).
lit_tilde='~'
lit_home='$HOME'
# Uma passada só sobre os tool_use do assistente: emite `commit` e/ou `wrote`.
# `git commit` com `(`, `/` (caminho do binário) ou separador antes; opções com argumento, inclusive entre aspas
# (`git -C "/a b" commit`). `commit-tree` e `log --grep commit` ficam de fora.
git_commit="(^|[;&|(/[:space:]])git([[:space:]]+-[^[:space:]]+([[:space:]]+(\"[^\"]*\"|'[^']*'|[^-[:space:]\"'][^[:space:]]*))?)*[[:space:]]+commit([[:space:];&|)]|\$)"
# Escrita em Bash (base do bash_write de second-brain-stop.sh, sem git commit). Redirecionar para /dev/null não conta.
bash_write='(^|[;&|[:space:]])(sed[[:space:]]+-[a-zA-Z]*i|tee|cp|mv|install)([[:space:]]|$)|[^<>=-]>>?[[:space:]]*[^&[:space:]]'
tags="$(jq -R -r --arg re "$git_commit" --arg wre "$bash_write" --arg abs "$root/" --arg tilde "$lit_tilde/.traycer/epics/$epic/artifacts/" --arg home "$lit_home/.traycer/epics/$epic/artifacts/" '
    fromjson? | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")
    | if .name == "Bash" then
        ((.input.command // "") as $c
         | (if ($c | test($re)) then "commit" else empty end),
           (if ($c | contains($abs) or contains($tilde) or contains($home)) and ($c | gsub(">>?[[:space:]]*/dev/null"; "") | test($wre)) then "wrote" else empty end))
      elif .name == "Agent" then
        (if (.input.subagent_type // "") == "git-ops" and ((.input.prompt // "") | test("commit"; "i")) then "commit" else empty end)
      elif (.name == "Write" or .name == "Edit" or .name == "MultiEdit") then
        (if ((.input.file_path // "") | startswith($abs)) then "wrote" else empty end)
      else empty end' "$transcript" 2>/dev/null | sort -u)"
[[ "$tags" == *commit* ]] || exit 0
[[ "$tags" == *wrote* ]] && exit 0

if [[ -n "$session_id" ]]; then
    mkdir -p "$state_dir" 2>/dev/null && : > "$marker"
    find "$state_dir" -type f -mtime +7 -delete 2>/dev/null
fi

msg="Houve commit nesta sessão e nenhum artifact do épico foi gravado. Se a tarefa gerou decisão, estado ou próximo passo que outro chat precisa, grave um artifact spec de até 30 linhas em ~/.traycer/epics/${epic}/artifacts/. Se não, encerre sem comentar."
jq -cn --arg msg "$msg" '{decision: "block", reason: $msg}'
exit 0
