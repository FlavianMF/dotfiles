#!/bin/bash
# Stop: roda format/typecheck do projeto ao fim do turno e devolve os erros ao Claude.
#
# Opt-in por projeto, desligado por padrão. Para ligar, em .claude/settings.local.json:
#   "env": { "CLAUDE_FORMAT_TYPECHECK": "1" }
# Opcional: "CLAUDE_FORMAT_TYPECHECK_CMD": "npm run -s lint && npx tsc --noEmit"
# Sem CMD, detecta: script npm "typecheck", tsc local, ruff, cargo check, go vet.
#
# Só roda se a árvore git tiver mudanças. Respeita stop_hook_active: devolve
# os erros uma vez e deixa o turno terminar na tentativa seguinte. Sempre exit 0.

[[ "${CLAUDE_FORMAT_TYPECHECK:-0}" == "1" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
[[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)" == "true" ]] && exit 0

dir="${CLAUDE_PROJECT_DIR:-$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)}"
[[ -d "$dir" ]] || exit 0
cd "$dir" || exit 0

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
[[ -n "$(git status --porcelain 2>/dev/null | head -1)" ]] || exit 0

cmds=()
if [[ -n "${CLAUDE_FORMAT_TYPECHECK_CMD:-}" ]]; then
    cmds+=("$CLAUDE_FORMAT_TYPECHECK_CMD")
else
    if [[ -f package.json ]] && jq -e '.scripts.typecheck' package.json >/dev/null 2>&1; then
        cmds+=("npm run -s typecheck")
    elif [[ -f tsconfig.json && -x node_modules/.bin/tsc ]]; then
        cmds+=("node_modules/.bin/tsc --noEmit")
    fi
    if [[ -f pyproject.toml ]] && command -v ruff >/dev/null 2>&1; then
        cmds+=("ruff format --quiet . && ruff check --quiet .")
    fi
    if [[ -f Cargo.toml ]] && command -v cargo >/dev/null 2>&1; then
        cmds+=("cargo check --quiet")
    fi
    if [[ -f go.mod ]] && command -v go >/dev/null 2>&1; then
        cmds+=("go vet ./...")
    fi
fi
(( ${#cmds[@]} )) || exit 0

report=""
for cmd in "${cmds[@]}"; do
    if ! out="$(timeout 110 bash -c "$cmd" 2>&1)"; then
        report+=$'\n'"\$ ${cmd}"$'\n'"$(printf '%s\n' "$out" | tail -n 40)"$'\n'
    fi
done
[[ -z "$report" ]] && exit 0

msg="Format/typecheck do projeto falhou após este turno. Corrija os erros abaixo (ou explique por que não se aplicam) antes de encerrar:${report}"
jq -cn --arg msg "${msg:0:9000}" '{hookSpecificOutput: {hookEventName: "Stop", additionalContext: $msg}}'
exit 0
