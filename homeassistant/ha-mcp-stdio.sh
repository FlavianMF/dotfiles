#!/usr/bin/env bash
# Wrapper stdio do ha-mcp: descarta do stdout tudo que não é mensagem JSON-RPC.
# Motivo: ha_mcp/config.py imprime "[ENV] ..." no stdout ao importar. Clientes estritos
# (Gemini CLI/Antigravity, escritos em Go) falham com "invalid character 'E' looking for
# beginning of value". O Claude Code ignora a linha, por isso não quebra.
# Uso (como "command" do cliente MCP): homeassistant/ha-mcp-stdio.sh [args do ha-mcp]
set -euo pipefail

command -v uvx >/dev/null 2>&1 || { echo "uvx não encontrado no PATH" >&2; exit 127; }

# Mensagens JSON-RPC são objetos de uma linha e começam com "{". O stdin passa direto.
uvx ha-mcp "$@" | grep --line-buffered -E '^\{'
