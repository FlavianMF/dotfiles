#!/bin/bash
# Testes de claude/hooks/traycer-epic-context.sh. Uso: bash tests/traycer_epic_context_test.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -r "$tmp"' EXIT
fail=0
expect() { if [[ "$2" != "$3" ]]; then echo "FALHA: $1 (obtido '$2', esperado '$3')"; fail=1; fi; }
has() { if ! grep -Eq -- "$2" <<<"$3"; then echo "FALHA: $1 (faltou '$2' em: $3)"; fail=1; fi; }

HOOK="$ROOT/claude/hooks/traycer-epic-context.sh"
HDR="Traycer: artifacts do épico atual"
export HOME="$tmp/home"
mkdir -p "$HOME/.traycer/epics"

# art <epic> <relpath-dir> <conteúdo>: cria artifacts/<dir>/index.md
art() {
    local d="$HOME/.traycer/epics/$1/artifacts/$2"
    mkdir -p "$d"
    printf '%s' "$3" >"$d/index.md"
}
# run_hook [env...]: roda o hook; preenche out, err e rc.
run_hook() {
    out="$(env "$@" bash "$HOOK" </dev/null 2>"$tmp/err")"; rc=$?
    err="$(cat "$tmp/err")"
}

# 1) sem TRAYCER_EPIC_ID
run_hook -u TRAYCER_EPIC_ID -u TRAYCER_EPIC_HOOK
expect "sem id: saída vazia" "$out" ""
expect "sem id: rc 0" "$rc" "0"

# 2) sem pasta artifacts e pasta vazia
mkdir -p "$HOME/.traycer/epics/noart"
run_hook -u TRAYCER_EPIC_HOOK TRAYCER_EPIC_ID=noart
expect "sem artifacts: silêncio" "$out" ""
expect "sem artifacts: rc 0" "$rc" "0"
mkdir -p "$HOME/.traycer/epics/empty/artifacts"
run_hook -u TRAYCER_EPIC_HOOK TRAYCER_EPIC_ID=empty
expect "pasta vazia: silêncio" "$out" ""
expect "pasta vazia: rc 0" "$rc" "0"

# 3) artifacts normais
art e3 a $'---\nkind: spec\ntitle: "Alpha"\n---\ncorpo\n'
art e3 b $'---\nkind: ticket\ntitle: B\nstatus: 1\n---\n'
art e3 b/c $'---\nkind: spec\ntitle: Filho\n---\n'
run_hook -u TRAYCER_EPIC_HOOK TRAYCER_EPIC_ID=e3
expect "normal: rc 0" "$rc" "0"
expect "normal: sem stderr" "$err" ""
first="$(head -n1 <<<"$out")"
expect "normal: cabeçalho" "${first:0:${#HDR}}" "$HDR"
expect "normal: 3 artifacts" "$(tail -n +2 <<<"$out" | wc -l)" "3"
has "normal: spec sem status" "^Alpha \(spec\) — a/index.md — atualizado [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$out"
has "normal: ticket com status" "^B \(ticket, 1\) — b/index.md — atualizado [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$out"
has "normal: filho direto" "^Filho \(spec\) — b/c/index.md — atualizado [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$out"

# 4) 12 artifacts: máximo 10 linhas
for i in $(seq -w 1 12); do art e4 "n$i" $'---\nkind: spec\ntitle: T'"$i"$'\n---\n'; done
run_hook -u TRAYCER_EPIC_HOOK TRAYCER_EPIC_ID=e4
expect "limite: 11 linhas totais" "$(wc -l <<<"$out")" "11"
expect "limite: 10 linhas de artifact" "$(tail -n +2 <<<"$out" | grep -c ' — n')" "10"

# 5) frontmatter quebrado
art e5 sem-fecha $'---\ntitle: Aberto\nkind: spec\n'
art e5 vazio ''
art e5 sem-dash $'title: Corpo\nkind: spec\n'
art e5 corpo-falso $'sem frontmatter\n---\ntitle: Inventado\n---\n'
run_hook -u TRAYCER_EPIC_HOOK TRAYCER_EPIC_ID=e5
expect "quebrado: rc 0" "$rc" "0"
expect "quebrado: sem stderr" "$err" ""
for bad in Corpo Inventado; do
    if grep -q -- "$bad" <<<"$out"; then echo "FALHA: quebrado inventou '$bad' em: $out"; fail=1; fi
done
has "quebrado: título cai para o diretório" "^vazio \(\?\) — vazio/index.md — atualizado [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$out"
has "quebrado: sem-dash usa diretório" "^sem-dash \(\?\) — sem-dash/index.md — atualizado [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$out"

# 6) TRAYCER_EPIC_HOOK=0
run_hook TRAYCER_EPIC_ID=e3 TRAYCER_EPIC_HOOK=0
expect "hook=0: silêncio" "$out" ""
expect "hook=0: rc 0" "$rc" "0"

# 7) corpo e .comments/ não vazam
art e7 x $'---\nkind: spec\ntitle: Real\n---\ntitle: Falso\nkind: ticket\nstatus: 9\n'
mkdir -p "$HOME/.traycer/epics/e7/artifacts/x/.comments"
printf '%s\n' $'---\ntitle: Comentario\n---' >"$HOME/.traycer/epics/e7/artifacts/x/.comments/t.md"
run_hook -u TRAYCER_EPIC_HOOK TRAYCER_EPIC_ID=e7
has "corpo: título real" "^Real \(spec\) — x/index.md — atualizado [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$out"
for bad in Falso Comentario .comments; do
    if grep -q -- "$bad" <<<"$out"; then echo "FALHA: vazou '$bad' em: $out"; fail=1; fi
done

# 8) id malicioso
# Alvo da travessia: $HOME/.traycer/epics/../x/artifacts, que existiria sem a recusa.
mkdir -p "$HOME/.traycer/x/artifacts/z"
printf '%s\n' $'---\ntitle: Vazou\n---' >"$HOME/.traycer/x/artifacts/z/index.md"
run_hook -u TRAYCER_EPIC_HOOK 'TRAYCER_EPIC_ID=../x'
expect "id malicioso: silêncio" "$out" ""
expect "id malicioso: rc 0" "$rc" "0"

# 9) data = mtime do index.md
art e9 d $'---\nkind: spec\ntitle: Datado\n---\n'
touch -t 202601020000 "$HOME/.traycer/epics/e9/artifacts/d/index.md"
run_hook -u TRAYCER_EPIC_HOOK TRAYCER_EPIC_ID=e9
has "data: mtime do index.md" "^Datado \(spec\) — d/index.md — atualizado 2026-01-02$" "$out"

# 10) sem date nem stat: o trecho de data some
fake="$tmp/fakebin"
mkdir -p "$fake"
for c in bash awk head basename dirname; do ln -s "$(command -v "$c")" "$fake/$c"; done
for c in date stat; do printf '#!/bin/bash\nexit 1\n' >"$fake/$c"; chmod +x "$fake/$c"; done
out="$(env -u TRAYCER_EPIC_HOOK TRAYCER_EPIC_ID=e9 PATH="$fake" "$fake/bash" "$HOOK" </dev/null 2>"$tmp/err")"; rc=$?
expect "sem date/stat: rc 0" "$rc" "0"
has "sem date/stat: linha sem data" "^Datado \(spec\) — d/index.md$" "$out"
if grep -q -- "atualizado" <<<"$out"; then echo "FALHA: sufixo de data presente sem date/stat: $out"; fail=1; fi

[[ $fail -eq 0 ]] && echo "traycer_epic_context_test: ok"
exit $fail
