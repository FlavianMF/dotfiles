#!/bin/bash
# UserPromptSubmit: registra a decisão do roteador Jev para o prompt (dry run, só harness claude).
#
# Só roda dentro de um chat do Traycer (TRAYCER_AGENT_ID definido). Não aplica nada, não escreve
# no stdout e sempre sai 0. O registro e a lógica ficam no flows-editor (scripts/jev-route-hook.sh).
# Log: ~/.local/state/second-brain/jev-route-hook.jsonl
#
# Env (todas opcionais):
#   JEV_ROUTE_HOOK=0       desliga (vale sem reiniciar)
#   FLOWS_EDITOR_HOME      checkout do flows-editor (padrão ~/projetos_claude/flows-editor)

case "${JEV_ROUTE_HOOK:-}" in 0|false|off|no) exit 0 ;; esac
[[ -n "${TRAYCER_AGENT_ID:-}" ]] || exit 0

script="${FLOWS_EDITOR_HOME:-$HOME/projetos_claude/flows-editor}/scripts/jev-route-hook.sh"
[[ -f "$script" ]] || exit 0

bash "$script"
exit 0
