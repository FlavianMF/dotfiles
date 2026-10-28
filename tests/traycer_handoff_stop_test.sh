#!/bin/bash
# Testes de claude/hooks/traycer-handoff-stop.sh. Uso: bash tests/traycer_handoff_stop_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT
fail=0
expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
has() { if ! grep -q -- "$2" <<<"$3"; then echo "FALHA: $1 (faltou '$2' em: $3)"; fail=1; fi; }

HOOK="$ROOT/claude/hooks/traycer-handoff-stop.sh"
real_home="$HOME"
export HOME="$tmp/home"
export XDG_STATE_HOME="$tmp/state"
EPIC="e1"
ART="$HOME/.traycer/epics/$EPIC/artifacts"
mkdir -p "$ART"
STATE="$XDG_STATE_HOME/claude-hooks/traycer"
real_state="$real_home/.local/state/claude-hooks/traycer"
real_before="$(ls -A "$real_state" 2>/dev/null | sort | tr '\n' ' ')"

# Linhas de transcript sintéticas.
bash_line() { jq -cn --arg c "$1" '{type:"assistant",message:{content:[{type:"tool_use",name:"Bash",input:{command:$c}}]}}'; }
tool_line() { jq -cn --arg n "$1" --arg p "$2" '{type:"assistant",message:{content:[{type:"tool_use",name:$n,input:{file_path:$p}}]}}'; }
agent_line() { jq -cn --arg s "$1" --arg p "${2:-}" '{type:"assistant",message:{content:[{type:"tool_use",name:"Agent",input:{subagent_type:$s,prompt:$p}}]}}'; }
text_line() { jq -cn --arg t "$1" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}'; }
user_line() { jq -cn --arg t "$1" '{type:"user",message:{content:$t}}'; }
user_blocks() { jq -cn --arg t "$1" '{type:"user",message:{content:[{type:"text",text:$t}]}}'; }

# mk <nome> <linhas...>: cria $tmp/<nome>.jsonl
mk() { local f="$tmp/$1.jsonl"; shift; printf '%s\n' "$@" >"$f"; }

# fire <session> <transcript> [env...] [-- json-override]: preenche out e rc.
fire() {
    local sid="$1" tr="$2"; shift 2
    out="$(jq -cn --arg t "$tr" --arg s "$sid" '{transcript_path:$t,session_id:$s,stop_hook_active:false}' \
        | env TRAYCER_EPIC_ID="$EPIC" "$@" bash "$HOOK" 2>"$tmp/err")"; rc=$?
}
blocked() { jq -r '.decision // empty' <<<"$out" 2>/dev/null; }
silent() { expect "$1: silêncio" "$out" ""; expect "$1: rc 0" "$rc" "0"; }
blocks() { expect "$1: decision" "$(blocked)" "block"; expect "$1: rc 0" "$rc" "0"; }

C="$(bash_line 'git commit -m x')"

# 1) sem commit
mk nocommit "$(user_line oi)" "$(bash_line 'ls -la')"
fire s1 "$tmp/nocommit.jsonl"; silent "sem commit"

# 2) commit bloqueia; segunda rodada silencia (marcador)
mk commit "$(user_line oi)" "$C"
fire s2 "$tmp/commit.jsonl"; blocks "commit"
has "commit: cita o caminho" "epics/$EPIC/artifacts" "$out"
[[ -f "$STATE/s2.reminded" ]] && got=sim || got=nao
expect "commit: marcador criado" "$got" "sim"
fire s2 "$tmp/commit.jsonl"; silent "commit: segunda rodada"
fire s2b "$tmp/commit.jsonl"; blocks "commit: outra sessão ainda bloqueia"

# 3) git -C /x commit
mk gitc "$(user_line oi)" "$(bash_line 'git -C /x commit -m y')"
fire s3 "$tmp/gitc.jsonl"; blocks "git -C commit"

# 4) git log --grep commit
mk grep "$(user_line oi)" "$(bash_line 'git log --grep commit')"
fire s4 "$tmp/grep.jsonl"; silent "git log --grep commit"

# 5) Agent git-ops
mk gitops "$(user_line oi)" "$(agent_line git-ops 'Faça o Commit das mudanças')"
fire s5 "$tmp/gitops.jsonl"; blocks "Agent git-ops com commit no prompt"
mk gitopsro "$(user_line oi)" "$(agent_line git-ops 'rode git status, log e push')"
fire s5c "$tmp/gitopsro.jsonl"; silent "Agent git-ops sem commit no prompt"
mk otheragent "$(user_line oi)" "$(agent_line Explore 'faça commit')"
fire s5b "$tmp/otheragent.jsonl"; silent "Agent outro"

# 6) só tool_use conta: texto de usuário e de assistente
mk usertxt "$(user_line 'rode git commit -m x')" "$(text_line 'vou rodar git commit -m x')"
fire s6 "$tmp/usertxt.jsonl"; silent "texto cita git commit"
mk userblk "$(user_blocks 'use git commit agora')"
fire s6b "$tmp/userblk.jsonl"; silent "bloco de usuário cita git commit"

# 7) escrita no artifacts suprime, antes ou depois do commit (intencional: a sessão já registrou contexto)
mk wr "$(user_line oi)" "$C" "$(tool_line Write "$ART/x/index.md")"
fire s7 "$tmp/wr.jsonl"; silent "Write em artifacts"
mk ed "$(user_line oi)" "$C" "$(tool_line Edit "$ART/x/index.md")"
fire s7b "$tmp/ed.jsonl"; silent "Edit em artifacts"
mk bw "$(user_line oi)" "$C" "$(bash_line "cat > $ART/x/index.md <<EOF")"
fire s7c "$tmp/bw.jsonl"; silent "Bash redireciona para artifacts"
mk wrbefore "$(user_line oi)" "$(tool_line Write "$ART/x/index.md")" "$C"
fire s7d "$tmp/wrbefore.jsonl"; silent "Write em artifacts antes do commit"
mk tee "$(user_line oi)" "$C" "$(bash_line "printf x | tee $ART/x/index.md")"
fire s7e "$tmp/tee.jsonl"; silent "Bash tee em artifacts"
mk wtilde "$(user_line oi)" "$C" "$(bash_line 'cat >> ~/.traycer/epics/e1/artifacts/x/index.md')"
fire s7f "$tmp/wtilde.jsonl"; silent "Bash escreve com ~/"
mk whome "$(user_line oi)" "$C" "$(bash_line 'cp /tmp/a $HOME/.traycer/epics/e1/artifacts/x/index.md')"
fire s7g "$tmp/whome.jsonl"; silent "Bash escreve com \$HOME/"
mk rdls "$(user_line oi)" "$C" "$(bash_line "ls $ART/")"
fire s7h "$tmp/rdls.jsonl"; blocks "Bash ls em artifacts não suprime"
mk rdcat "$(user_line oi)" "$C" "$(bash_line "cat \$HOME/.traycer/epics/e1/artifacts/x/index.md 2>/dev/null")"
fire s7i "$tmp/rdcat.jsonl"; blocks "Bash cat em artifacts não suprime"
mk rdtil "$(user_line oi)" "$C" "$(bash_line 'cat ~/.traycer/epics/e1/artifacts/x/index.md')"
fire s7j "$tmp/rdtil.jsonl"; blocks "Bash cat com ~/ não suprime"

# 7b) formas de git commit
mk gtree "$(user_line oi)" "$(bash_line 'git commit-tree abc')"
fire s7k "$tmp/gtree.jsonl"; silent "git commit-tree"
mk gparen "$(user_line oi)" "$(bash_line '(git commit -m x)')"
fire s7l "$tmp/gparen.jsonl"; blocks "(git commit)"
mk gbin "$(user_line oi)" "$(bash_line '/usr/bin/git commit -m x')"
fire s7m "$tmp/gbin.jsonl"; blocks "/usr/bin/git commit"
mk gquote "$(user_line oi)" "$(bash_line 'git -C "/a b" commit -m x')"
fire s7n "$tmp/gquote.jsonl"; blocks 'git -C "/a b" commit'

# 7c) transcript sem session_id: bloqueia e não cria marcador
before="$(ls -A "$STATE" 2>/dev/null | sort | tr '\n' ' ')"
out="$(jq -cn --arg t "$tmp/commit.jsonl" '{transcript_path:$t,stop_hook_active:false}' \
    | env TRAYCER_EPIC_ID="$EPIC" bash "$HOOK" 2>"$tmp/err")"; rc=$?
blocks "sem session_id"
expect "sem session_id: sem marcador novo" "$(ls -A "$STATE" 2>/dev/null | sort | tr '\n' ' ')" "$before"

# 8) Write em outro caminho ainda bloqueia
mk wother "$(user_line oi)" "$C" "$(tool_line Write "$HOME/outro/x/index.md")"
fire s8 "$tmp/wother.jsonl"; blocks "Write em outro caminho"

# 9) sessão filha: primeira mensagem de usuário de outro agente
mk child1 "$(user_line '[traycer:agent-message] faça isso')" "$C"
fire s9 "$tmp/child1.jsonl"; silent "filha (string)"
mk child2 "$(user_blocks '[traycer:agent-message] faça isso')" "$C"
fire s9b "$tmp/child2.jsonl"; silent "filha (blocos)"

# 10) desligamentos e entradas inválidas
fire s10 "$tmp/commit.jsonl" TRAYCER_EPIC_HOOK=0; silent "HOOK=0"
fire s10b "$tmp/commit.jsonl" TRAYCER_EPIC_ID=; silent "id vazio"
fire s10c "$tmp/commit.jsonl" 'TRAYCER_EPIC_ID=../x'; silent "id malicioso"
mkdir -p "$HOME/.traycer/epics/sem-art"
fire s10d "$tmp/commit.jsonl" TRAYCER_EPIC_ID=sem-art; silent "artifacts inexistente"
out="$(jq -cn --arg t "$tmp/commit.jsonl" '{transcript_path:$t,session_id:"s10e",stop_hook_active:true}' \
    | env TRAYCER_EPIC_ID="$EPIC" bash "$HOOK" 2>&1)"; rc=$?
silent "stop_hook_active"
fire s10f "$tmp/nao-existe.jsonl"; silent "transcript inexistente"

# 11) nenhum caso grava no ~/.local/state real
real_after="$(ls -A "$real_state" 2>/dev/null | sort | tr '\n' ' ')"
expect "estado real intacto" "$real_after" "$real_before"
[[ ! -e "$HOME/.local/state" ]] && got=sim || got=nao
expect "HOME temporário sem .local/state" "$got" "sim"

[[ $fail -eq 0 ]] && echo "traycer_handoff_stop_test: ok"
exit $fail
