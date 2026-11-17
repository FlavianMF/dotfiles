#!/bin/bash
# agy SessionStart e Stop: dá ao agente o título da conversa na lista Agents do cockpit (Herdr app).
#
# O cockpit só nomeia o que um plugin reporta, e o agy não tem plugin dele. Este hook lê o título da
# conversa em ~/.gemini/antigravity-cli/conversation_summaries.db (somente leitura) e o grava como `task`
# no documento `agents` do hub (`cockpit store patch agents`), na chave do terminal do agente.
# Sem título ainda (primeira volta da conversa) ou fora do Herdr app, não faz nada.
# Lê o JSON do agy no stdin (`conversationId`, `workspacePaths`) e responde `{}`.
# Liga por padrão; COCKPIT_AGY_NAMES=0 desliga. Sempre exit 0.

done_() { echo '{}'; exit 0; }

[[ "${COCKPIT_AGY_NAMES:-1}" == "0" ]] && done_
[[ -n "${HC_TERMINAL_ID:-}" ]] || done_
command -v jq >/dev/null 2>&1 || done_
command -v cockpit >/dev/null 2>&1 || done_

IFS=$'\t' read -r session cwd < <(
    jq -r '[(.conversationId // ""), (.workspacePaths[0] // "")] | @tsv' 2>/dev/null
)
session="${session//[^A-Za-z0-9_-]/}"
[[ -n "$session" ]] || done_

db="${AGY_SUMMARIES_DB:-$HOME/.gemini/antigravity-cli/conversation_summaries.db}"
[[ -r "$db" ]] || done_

# O título vem sozinho depois da primeira resposta; antes disso a coluna fica vazia.
title="$(python3 -I - "$db" "$session" <<'PY' 2>/dev/null
import sqlite3, sys
c = sqlite3.connect("file:%s?mode=ro" % sys.argv[1], uri=True, timeout=2)
row = c.execute("select title from conversation_summaries where conversation_id = ?", (sys.argv[2],)).fetchone()
print((row[0] if row and row[0] else "").strip())
PY
)"
[[ -n "$title" ]] || done_

# Num desk remoto o app chama o terminal do WSL de "wsl/t1j", e HC_TERMINAL_ID vale "t1j".
terminal="$HC_TERMINAL_ID"
space=""
tab=""
if command -v herdr-app >/dev/null 2>&1; then
    row="$(herdr-app ls 2>/dev/null | jq -r --arg t "$HC_TERMINAL_ID" '
        [.spaces[] as $s | $s.tabs[] as $b | $b.terminals[]
         | select(.terminal == $t or (.terminal | endswith("/" + $t)))
         | [.terminal, $s.id, $b.id]] | first // empty | @tsv' 2>/dev/null)"
    [[ -n "$row" ]] && IFS=$'\t' read -r terminal space tab <<<"$row"
fi

file="$(mktemp)"
trap 'rm -f "$file"' EXIT
jq -n --arg handle "app:$terminal" --arg terminal "$terminal" --arg session "$session" --arg cwd "$cwd" \
    --arg title "$title" --arg space "$space" --arg tab "$tab" --argjson at "$(($(date +%s) * 1000))" \
    '{($handle): {session: $session, cwd: (if $cwd == "" then null else $cwd end), task: $title, frontend: "app",
                  terminal: $terminal, space: $space, tab: $tab, at: $at}}' >"$file"
# O `store patch` apaga o arquivo; o trap cobre o caso de falha.
timeout 5 cockpit store patch agents "$file" >/dev/null 2>&1
done_
