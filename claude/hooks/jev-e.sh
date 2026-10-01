#!/bin/bash
# UserPromptSubmit: ferramenta E do jev-workflow (sugestão de skill por pedido).
#
# Fino de propósito: confere os interruptores, acha o build do jev-workflow e
# roda `node dist/cli.js hook e` com timeout duro. Em modo sombra (padrão) o
# CLI só grava o log local e não escreve nada; em modo ativo escreve uma linha
# de additionalContext. Falha, timeout, build ausente, kill-switch: não imprime
# nada e sai 0. Nunca bloqueia o prompt.
#
# Env (todas opcionais):
#   JEV_WORKFLOW_HOME   checkout do jev-workflow (padrão ~/projetos_claude/jev-workflow)
#   JEV_TOOLS=0 | JEV_TOOL_E=0 | arquivo DISABLED em $JEV_STATE_DIR  desligam (vale sem reiniciar)
#   JEV_MODE_E / JEV_MODE   shadow (padrão) | active
#   JEV_E_TIMEOUT_MS    teto do processo inteiro (padrão 1000)
#   JEV_E_HARD_TIMEOUT  timeout duro do wrapper, em segundos (padrão 1.3)

off() { case "${1:-}" in 0|false|off|no|FALSE|OFF|NO) return 0 ;; esac; return 1; }

off "${JEV_TOOLS:-}" && exit 0
off "${JEV_TOOL_E:-}" && exit 0
[[ -e "${JEV_STATE_DIR:-$HOME/.local/state/jev-tools}/DISABLED" ]] && exit 0

cli="${JEV_WORKFLOW_HOME:-$HOME/projetos_claude/jev-workflow}/dist/cli.js"
[[ -f "$cli" ]] || exit 0
command -v node >/dev/null 2>&1 || exit 0

# A chave normalmente já está no ambiente (zshrc carrega secrets/*.env); se não, tenta o arquivo, sem imprimir.
if [[ -z "${TYPESAFE_API_KEY:-}" && -r "$HOME/dotfiles/secrets/fast-jev.env" ]]; then
    # shellcheck disable=SC1091
    . "$HOME/dotfiles/secrets/fast-jev.env" >/dev/null 2>&1
fi
[[ -n "${TYPESAFE_API_KEY:-}" ]] || exit 0

mode="${JEV_MODE_E:-${JEV_MODE:-shadow}}"
hard="${JEV_E_HARD_TIMEOUT:-1.3}"
[[ "$hard" =~ ^[0-9]+(\.[0-9]+)?$ ]] || hard=1.3

out="$(timeout --kill-after=0.2 "$hard" node "$cli" hook e 2>/dev/null)"

# Defesa em profundidade: só o modo ativo pode escrever algo para o modelo.
if [[ "$mode" == "active" && -n "$out" ]]; then
    printf '%s\n' "$out"
fi
exit 0
