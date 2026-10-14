#!/bin/bash
# UserPromptSubmit: dica do second brain por prompt (RFC-001, camada L1).
#
# Desligado por padrão: exige SECOND_BRAIN_HOOKS=1 e SECOND_BRAIN_PROMPT_HINT=shadow|active
# (ex.: "env" em ~/.claude/settings.json ou .claude/settings.local.json). No modo shadow
# só grava um log local e não escreve nada no contexto. A lógica fica no vault
# (prompt_hint.sh); aqui só o portão barato e o timeout. Sempre exit 0.

[[ "${SECOND_BRAIN_HOOKS:-0}" == "1" ]] || exit 0
[[ "${SECOND_BRAIN_PROMPT_HINT:-}" == "shadow" || "${SECOND_BRAIN_PROMPT_HINT:-}" == "active" ]] || exit 0

vault="${SECOND_BRAIN_VAULT:-$HOME/obsidian_vault}"
hint="$vault/00_META/skills/second-brain-sync/scripts/prompt_hint.sh"
[[ -f "$hint" ]] || exit 0

timeout 1 bash "$hint" 2>/dev/null
exit 0
