#!/bin/bash
# Testes de antigravity/install.sh e antigravity/render_config.sh. Uso: bash tests/antigravity_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -r "$tmp"' EXIT
fail=0
expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
has() { if ! grep -q -- "$2" <<<"$3"; then echo "FALHA: $1 (faltou '$2' em: $3)"; fail=1; fi; }

mkdir "$tmp/bin" "$tmp/home" "$tmp/fixture"
# curl falso: serve o manifesto e o payload de $tmp/fixture, sem tocar a rede.
cat >"$tmp/bin/curl" <<'FAKE'
#!/bin/bash
out=""; url=""
while [[ $# -gt 0 ]]; do
    case "$1" in -o) out="$2"; shift ;; -*) ;; *) url="$1" ;; esac
    shift
done
case "$url" in
    */manifests/*) cp "$FIXTURE/manifest.json" "$out" ;;
    *) cp "$FIXTURE/payload" "$out" ;;
esac
FAKE
chmod +x "$tmp/bin/curl"
export HOME="$tmp/home" PATH="$tmp/bin:$PATH" FIXTURE="$tmp/fixture"
export AGY_DOWNLOAD_BASE="https://fake.invalid"
BIN="$HOME/.local/bin/agy"

manifest() { # $1 = url, $2 = sha512
    printf '{"version":"9.9.9","url":"%s","sha512":"%s"}\n' "$1" "$2" >"$FIXTURE/manifest.json"
}

# Binário direto
printf '#!/bin/sh\necho agy-fake\n' >"$FIXTURE/payload"
good="$(sha512sum "$FIXTURE/payload" | cut -d' ' -f1)"

out="$(bash "$ROOT/antigravity/install.sh" --dry-run 2>&1)"
has "dry-run mostra o destino" "$BIN" "$out"
[[ ! -e "$BIN" ]] || { echo "FALHA: dry-run criou o binário"; fail=1; }

manifest "https://fake.invalid/agy" "deadbeef"
out="$(bash "$ROOT/antigravity/install.sh" 2>&1)"; rc=$?
expect "sha512 errado falha" "$rc" "1"
has "sha512 errado avisa" "sha512 mismatch" "$out"
[[ ! -e "$BIN" ]] || { echo "FALHA: instalou com sha512 errado"; fail=1; }

manifest "https://fake.invalid/agy" "$good"
out="$(bash "$ROOT/antigravity/install.sh" 2>&1)"; rc=$?
expect "instala binário direto" "$rc" "0"
expect "binário executa" "$("$BIN")" "agy-fake"
[[ ! -e "$HOME/.zshrc" && ! -e "$HOME/.bashrc" ]] || { echo "FALHA: o instalador mexeu em arquivos de shell"; fail=1; }

out="$(bash "$ROOT/antigravity/install.sh" 2>&1)"
has "segunda rodada pula" "already installed" "$out"

# tar.gz com o binário chamado "antigravity"
rm "$BIN"
mkdir "$FIXTURE/pkg"; printf '#!/bin/sh\necho agy-from-tar\n' >"$FIXTURE/pkg/antigravity"; chmod +x "$FIXTURE/pkg/antigravity"
tar -czf "$FIXTURE/payload" -C "$FIXTURE/pkg" antigravity
manifest "https://fake.invalid/agy.tar.gz" "$(sha512sum "$FIXTURE/payload" | cut -d' ' -f1)"
bash "$ROOT/antigravity/install.sh" >/dev/null 2>&1
expect "instala de tar.gz" "$("$BIN" 2>&1)" "agy-from-tar"

# --- render_config.sh ---
mkdir -p "$HOME/.gemini/antigravity-cli" "$HOME/.gemini/config"
echo '{"model":"m","trustedWorkspaces":["/w"],"permissions":{"allow":["command(git status)"],"deny":["command(foo)"]}}' >"$HOME/.gemini/antigravity-cli/settings.json"
echo '{"mcpServers":{"mine":{"command":"x"}}}' >"$HOME/.gemini/config/mcp_config.json"
bash "$ROOT/antigravity/render_config.sh" >/dev/null 2>&1; rc=$?
expect "render sai 0" "$rc" "0"
S="$HOME/.gemini/antigravity-cli/settings.json"; M="$HOME/.gemini/config/mcp_config.json"
expect "mantém chave só da máquina" "$(jq -r '.model' "$S")" "m"
expect "mantém allow da máquina" "$(jq -c '.permissions.allow' "$S")" '["command(git status)"]'
expect "une deny da máquina e da base" "$(jq -r '.permissions.deny | index("command(foo)") != null and index("command(sudo)") != null' "$S")" "true"
expect "expande HOME no deny" "$(jq -r '.permissions.deny | index("read_file('"$HOME"'/.ssh)") != null' "$S")" "true"
expect "sem @HOME@ sobrando" "$(grep -c '@HOME@' "$S")" "0"
expect "MCPs da base + da máquina" "$(jq -c '.mcpServers | keys' "$M")" '["figma","mine","playwright","rea"]'
K="$HOME/.gemini/config/skills.json"
expect "skills.json com caminho absoluto" "$(jq -r '.entries[0].path' "$K")" "$HOME/.agents/skills"
before="$(sha1sum "$S" "$M" "$K")"
bash "$ROOT/antigravity/render_config.sh" >/dev/null 2>&1
expect "render idempotente" "$(sha1sum "$S" "$M" "$K")" "$before"

# skills.json antigo: link para o repo com "~" vira arquivo real, sem tocar o repo
rm "$K"; ln -s "$tmp/legacy_skills.json" "$K"
echo '{"entries":[{"path":"~/.agents/skills"}]}' >"$tmp/legacy_skills.json"
bash "$ROOT/antigravity/render_config.sh" >/dev/null 2>&1
[[ ! -L "$K" ]] || { echo "FALHA: skills.json continuou link"; fail=1; }
expect "cópia do repo intacta" "$(cat "$tmp/legacy_skills.json")" '{"entries":[{"path":"~/.agents/skills"}]}'
expect "skills.json migrado" "$(jq -c '.entries' "$K")" '[{"path":"'"$HOME"'/.agents/skills"}]'

# --- hooks.json ---
H="$HOME/.gemini/config/hooks.json"
expect "hooks: SessionStart aponta para o repo" "$(jq -r '."second-brain".SessionStart[0].command' "$H")" "\"$ROOT/antigravity/hooks/second-brain-session-start.sh\""
expect "hooks: PostToolUse tem o handler de contagem" "$(jq -r '."second-brain".PostToolUse[0].hooks[0].command' "$H")" "\"$ROOT/antigravity/hooks/second-brain-count.sh\""
expect "hooks: Stop aponta para o repo" "$(jq -r '."second-brain".Stop[0].command' "$H")" "\"$ROOT/antigravity/hooks/second-brain-stop.sh\""
expect "hooks: sem @REPO@ sobrando" "$(grep -c '@REPO@' "$H")" "0"

echo '{"outro":{"x":1}}' >"$H"
bash "$ROOT/antigravity/render_config.sh" >/dev/null 2>&1
expect "hooks: mantém chave alheia" "$(jq -c '.outro' "$H")" '{"x":1}'
expect "hooks: base presente após merge" "$(jq -r 'has("second-brain")' "$H")" "true"
before="$(sha1sum "$H")"
bash "$ROOT/antigravity/render_config.sh" >/dev/null 2>&1
expect "hooks: render idempotente" "$(sha1sum "$H")" "$before"

rm "$H"; ln -s "$tmp/legacy_hooks.json" "$H"
echo '{"legado":true}' >"$tmp/legacy_hooks.json"
bash "$ROOT/antigravity/render_config.sh" >/dev/null 2>&1
[[ ! -L "$H" ]] || { echo "FALHA: hooks.json continuou link"; fail=1; }
expect "hooks: alvo do link intacto" "$(cat "$tmp/legacy_hooks.json")" '{"legado":true}'
expect "hooks: migrado para arquivo real" "$(jq -r 'has("second-brain")' "$H")" "true"

out="$(AGY_HOOKS="$tmp/dry/hooks.json" bash "$ROOT/antigravity/render_config.sh" --dry-run 2>&1)"
has "hooks: dry-run cita o alvo" "$tmp/dry/hooks.json" "$out"
[[ ! -e "$tmp/dry/hooks.json" ]] || { echo "FALHA: dry-run criou hooks.json"; fail=1; }

echo '{broken' >"$tmp/bad_hooks.json"
AGY_HOOKS="$tmp/bad_hooks.json" bash "$ROOT/antigravity/render_config.sh" >/dev/null 2>&1; rc=$?
expect "hooks: JSON inválido falha" "$rc" "1"
expect "hooks: JSON inválido fica intacto" "$(cat "$tmp/bad_hooks.json")" "{broken"

# --- hooks do second brain (vault e estado falsos) ---
V="$tmp/vault"; SCRIPTS="$V/00_META/skills/second-brain-sync/scripts"
mkdir -p "$SCRIPTS" "$tmp/state" "$V/sub"
cat >"$SCRIPTS/session_hint.sh" <<'FAKE'
#!/bin/bash
[[ -n "${HINT_EMPTY:-}" ]] && exit 0
echo "nota um"; echo "nota dois"; echo "repo=$1"
FAKE
cat >"$SCRIPTS/sb.py" <<'FAKE'
import json, os, sys
with open(os.environ["SEEN"], "w") as f:
    json.dump({"argv": sys.argv[1:], "stdin": sys.stdin.read()}, f)
FAKE
export SECOND_BRAIN_VAULT="$V" SECOND_BRAIN_STATE_DIR="$tmp/state" SEEN="$tmp/seen.json"
unset SECOND_BRAIN_HOOKS SB_OBSERVE
SS="$ROOT/antigravity/hooks/second-brain-session-start.sh"
OB="$ROOT/antigravity/hooks/second-brain-observe.sh"
GIT=(git -c user.name=t -c user.email=t@t)
mkdir "$tmp/proj-repo"
git -C "$tmp/proj-repo" init -q
"${GIT[@]}" -C "$tmp/proj-repo" commit -q --allow-empty -m init
"${GIT[@]}" -C "$tmp/proj-repo" worktree add -q "$tmp/proj-wt" -b wt

out="$(printf '{"workspacePaths":["%s"]}' "$tmp/proj-repo" | bash "$SS")"; rc=$?
expect "start: exit 0" "$rc" "0"
msg="$(jq -r '.injectSteps[0].systemMessage.systemMessage' <<<"$out")"
has "start: nome do repo no texto" 'notas do vault relacionadas a "proj-repo"' "$msg"
has "start: linhas da dica" "nota dois" "$msg"
has "start: dica recebe o repo em \$1" "repo=proj-repo" "$msg"
out="$(printf '{"workspacePaths":["%s"]}' "$tmp/proj-wt" | bash "$SS")"
has "start: worktree usa o repo principal" "repo=proj-repo" "$(jq -r '.injectSteps[0].systemMessage.systemMessage' <<<"$out")"

out="$(printf '{"workspacePaths":["%s"]}' "$tmp/proj-repo" | HINT_EMPTY=1 bash "$SS")"; rc=$?
expect "start: dica vazia dá {}" "$out" "{}"; expect "start: dica vazia exit 0" "$rc" "0"
out="$(printf '{"workspacePaths":["%s"]}' "$tmp/proj-repo" | SECOND_BRAIN_VAULT="$tmp/sem-vault" bash "$SS")"; rc=$?
expect "start: vault ausente dá {}" "$out" "{}"; expect "start: vault ausente exit 0" "$rc" "0"
out="$(printf '{"workspacePaths":["%s"]}' "$tmp/proj-repo" | SECOND_BRAIN_HOOKS=0 bash "$SS")"; rc=$?
expect "start: HOOKS=0 dá {}" "$out" "{}"; expect "start: HOOKS=0 exit 0" "$rc" "0"
out="$(printf '{"workspacePaths":["%s"]}' "$V/sub" | bash "$SS")"; rc=$?
expect "start: cwd no vault dá {}" "$out" "{}"; expect "start: cwd no vault exit 0" "$rc" "0"

PAYLOAD='{"conversationId":"c1","toolCall":{"name":"read_file","args":{"Path":"/x/y.md","Content":"segredo"}}}'
out="$(bash "$OB" <<<"$PAYLOAD")"; rc=$?
expect "observe: stdout {}" "$out" "{}"; expect "observe: exit 0" "$rc" "0"
expect "observe: argv" "$(jq -c '.argv' "$tmp/seen.json")" '["observe","record"]'
expect "observe: stdin sem conteúdo" "$(jq -c '.stdin | fromjson' "$tmp/seen.json")" '{"session_id":"c1","tool_name":"read_file","tool_input":{"file_path":"/x/y.md"}}'

for k in AbsolutePath path; do
    rm -f "$tmp/seen.json"
    bash "$OB" <<<"{\"conversationId\":\"c2\",\"toolCall\":{\"name\":\"t\",\"args\":{\"$k\":\"/a/b\"}}}" >/dev/null
    expect "observe: $k vira file_path" "$(jq -r '.stdin | fromjson | .tool_input.file_path' "$tmp/seen.json")" "/a/b"
done

rm -f "$tmp/seen.json"
out="$(SECOND_BRAIN_HOOKS=0 bash "$OB" <<<"$PAYLOAD")"
expect "observe: HOOKS=0 dá {}" "$out" "{}"
[[ ! -e "$tmp/seen.json" ]] || { echo "FALHA: HOOKS=0 chamou o sb.py"; fail=1; }
out="$(SB_OBSERVE=0 bash "$OB" <<<"$PAYLOAD")"
expect "observe: SB_OBSERVE=0 dá {}" "$out" "{}"
[[ ! -e "$tmp/seen.json" ]] || { echo "FALHA: SB_OBSERVE=0 chamou o sb.py"; fail=1; }

out="$(SECOND_BRAIN_VAULT="$tmp/sem-vault" bash "$OB" <<<'lixo{')"; rc=$?
expect "observe: vault sem sb.py dá {}" "$out" "{}"; expect "observe: vault sem sb.py exit 0" "$rc" "0"
out="$(bash "$OB" <<<'lixo{')"; rc=$?
expect "observe: stdin lixo dá {}" "$out" "{}"; expect "observe: stdin lixo exit 0" "$rc" "0"

# --- hooks count e Stop (estado e vault falsos) ---
CNT="$ROOT/antigravity/hooks/second-brain-count.sh"
STP="$ROOT/antigravity/hooks/second-brain-stop.sh"
AS="$tmp/state/agy"
cnt() { # $1 = sessão, $2 = ferramenta, $3 = CommandLine (opcional)
    jq -cn --arg s "$1" --arg t "$2" --arg c "${3:-}" \
        '{conversationId: $s, toolCall: {name: $t, args: (if $c == "" then {} else {CommandLine: $c} end)}}' | bash "$CNT"
}
stp() { # $1 = sessão, $2 = terminationReason (padrão NO_TOOL_CALL)
    jq -cn --arg s "$1" --arg r "${2-NO_TOOL_CALL}" '{conversationId: $s, terminationReason: $r}' | bash "$STP"
}
writes() { for _ in $(seq "$2"); do cnt "$1" write_file >/dev/null; done; }
n() { grep -cx "$2" "$AS/$1.state" 2>/dev/null; }

unset SECOND_BRAIN_MIN_EDITS
# 1. contagem
for t in write_file edit_file write_to_file replace_file_content multi_replace_file_content apply_patch create_file delete_file edit_notebook; do
    out="$(cnt k1 "$t")"; expect "count: $t responde {}" "$out" "{}"
done
expect "count: 9 tools de edição viram w" "$(n k1 w)" "9"
cnt k1 run_command 'echo x > /tmp/f' >/dev/null
cnt k1 run_command 'rm a' >/dev/null
cnt k1 run_command 'sed -i s/a/b/ f' >/dev/null
expect "count: run_command de escrita vira w" "$(n k1 w)" "12"
cnt k1 run_command 'ls -la' >/dev/null
cnt k1 read_file >/dev/null
expect "count: ls e read_file não contam" "$(n k1 w)" "12"
expect "count: sem s" "$(n k1 s)" "0"
expect "count: só uma letra por linha" "$(grep -cvx '[ws]' "$AS/k1.state")" "0"

# 2. synced
cnt k2 run_command 'python3 vault_sync.py' >/dev/null
expect "count: vault_sync vira s" "$(n k2 s)" "1"
cnt k2 run_command 'python3 sb.py sync' >/dev/null
expect "count: sb.py sync vira s" "$(n k2 s)" "2"
expect "count: s tem precedência sobre w" "$(n k2 w)" "0"
writes k3 5
cnt k3 run_command 'python3 sb.py candidate add --kind trap --title x > /dev/null' >/dev/null
expect "count: candidate add com redirecionamento vira s" "$(n k3 s)" "1"
expect "stop: candidate add impede o lembrete" "$(stp k3)" "{}"
[[ ! -e "$AS/k3.reminded" ]] || { echo "FALHA: stop criou marker com synced"; fail=1; }

# 3. limiar
writes k4 4
expect "stop: 4 escritas dá {}" "$(stp k4)" "{}"
writes k5 5
out="$(stp k5)"; rc=$?
expect "stop: 5 escritas exit 0" "$rc" "0"
expect "stop: 5 escritas pede continue" "$(jq -r '.decision' <<<"$out")" "continue"
has "stop: reason cita a contagem" "Esta sessão fez 5 edições" "$(jq -r '.reason' <<<"$out")"
writes k6 2
expect "stop: MIN_EDITS=2 lembra com 2" "$(SECOND_BRAIN_MIN_EDITS=2 stp k6 | jq -r '.decision')" "continue"
writes k7 1
expect "stop: MIN_EDITS=2 com 1 dá {}" "$(SECOND_BRAIN_MIN_EDITS=2 stp k7)" "{}"
writes k8 4
expect "stop: MIN_EDITS=abc cai no padrão (4 dá {})" "$(SECOND_BRAIN_MIN_EDITS=abc stp k8)" "{}"
writes k8 1
expect "stop: MIN_EDITS=abc cai no padrão (5 lembra)" "$(SECOND_BRAIN_MIN_EDITS=abc stp k8 | jq -r '.decision')" "continue"

# 4. uma vez só
[[ -e "$AS/k5.reminded" ]] || { echo "FALHA: stop não criou o marker"; fail=1; }
expect "stop: segunda chamada dá {}" "$(stp k5)" "{}"

# 5. terminationReason
writes k9 6
expect "stop: MAX_STEPS dá {}" "$(stp k9 MAX_STEPS)" "{}"
expect "stop: sem terminationReason dá {}" "$(jq -cn '{conversationId:"k9"}' | bash "$STP")" "{}"
[[ ! -e "$AS/k9.reminded" ]] || { echo "FALHA: stop criou marker sem NO_TOOL_CALL"; fail=1; }
expect "stop: NO_TOOL_CALL ainda lembra depois" "$(stp k9 | jq -r '.decision')" "continue"

# 6. gate desligado
out="$(SECOND_BRAIN_HOOKS=0 cnt k10 write_file)"
expect "count: HOOKS=0 dá {}" "$out" "{}"
[[ ! -e "$AS/k10.state" ]] || { echo "FALHA: HOOKS=0 gravou estado"; fail=1; }
writes k11 6
expect "stop: HOOKS=0 dá {}" "$(SECOND_BRAIN_HOOKS=0 stp k11)" "{}"
[[ ! -e "$AS/k11.reminded" ]] || { echo "FALHA: HOOKS=0 criou marker"; fail=1; }
expect "stop: vault ausente dá {}" "$(SECOND_BRAIN_VAULT="$tmp/sem-vault" stp k11)" "{}"

# 7. isolamento e sanitização
writes k12 5
expect "stop: outra sessão sem estado dá {}" "$(stp k13)" "{}"
expect "stop: sessão k12 lembra sem afetar k13" "$(stp k12 | jq -r '.decision')" "continue"
[[ ! -e "$AS/k13.reminded" ]] || { echo "FALHA: marker vazou para outra sessão"; fail=1; }
cnt '../x' write_file >/dev/null
[[ -f "$AS/x.state" ]] || { echo "FALHA: conversationId '../x' não foi sanitizado"; fail=1; }
[[ ! -e "$tmp/state/x.state" && ! -e "$tmp/x.state" ]] || { echo "FALHA: '../x' escapou do diretório de estado"; fail=1; }
cnt 'a/../b' write_file >/dev/null
[[ -f "$AS/ab.state" ]] || { echo "FALHA: 'a/../b' não virou 'ab'"; fail=1; }

# estados com mais de 7 dias somem quando o lembrete dispara
echo w >"$AS/velha.state"; touch -d '10 days ago' "$AS/velha.state"
writes k14 5
stp k14 >/dev/null
[[ ! -e "$AS/velha.state" ]] || { echo "FALHA: estado antigo não foi apagado"; fail=1; }
[[ -f "$AS/k14.state" ]] || { echo "FALHA: limpeza apagou o estado novo"; fail=1; }

for s in "$CNT" "$STP"; do
    out="$(bash "$s" <<<'lixo{')"; rc=$?
    expect "$(basename "$s"): stdin lixo dá {}" "$out" "{}"; expect "$(basename "$s"): stdin lixo exit 0" "$rc" "0"
done
unset SECOND_BRAIN_VAULT SECOND_BRAIN_STATE_DIR SEEN

# JSON inválido no alvo: não sobrescreve
echo '{broken' >"$S"
bash "$ROOT/antigravity/render_config.sh" >/dev/null 2>&1; rc=$?
expect "JSON inválido falha" "$rc" "1"
expect "JSON inválido fica intacto" "$(cat "$S")" "{broken"

[[ $fail -eq 0 ]] && echo "antigravity_test: ok"
exit $fail
