#!/usr/bin/env bash
# Utilitário de setup e verificação do MCP do Home Assistant (ha-mcp).
# Gerencia a conectividade Tailscale (100.105.143.75:8123) e configuração dos clientes de IA.
# Uso: homeassistant/setup-mcp.sh [check|config] [opções]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEFAULT_HA_URL="http://100.105.143.75:8123"
HA_URL="${HOMEASSISTANT_URL:-$DEFAULT_HA_URL}"
HA_TOKEN="${HOMEASSISTANT_TOKEN:-}"
# Wrapper que filtra o stdout do ha-mcp (clientes estritos quebram com o "[ENV] ..." dele).
WRAPPER="$ROOT/bin/ha-mcp-stdio"
DRY_RUN=0
COMMAND="check"
TARGET_CLIENT="all"

# Carrega segredos se existirem
if [[ -f "$ROOT/secrets/mcp.env" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "$ROOT/secrets/mcp.env"
    HA_URL="${HOMEASSISTANT_URL:-$HA_URL}"
    HA_TOKEN="${HOMEASSISTANT_TOKEN:-$HA_TOKEN}"
fi

show_help() {
    cat <<'EOF'
Uso: setup-mcp.sh [comando] [opções]

Comandos:
  check               Verifica a conectividade com o Home Assistant via Tailscale,
                      disponibilidade de uvx e autenticação (padrão).
  config              Gera ou aplica a configuração de MCP para clientes de IA
                      (Claude Code, Antigravity/Gemini, OpenCode, Cursor).

Opções:
  -d, --dry-run       Simula alterações sem modificar arquivos ou invocar comandos externos.
  -u, --url URL       URL do Home Assistant (padrão: http://100.105.143.75:8123).
  -t, --token TOKEN   Token de Acesso de Longa Duração (substitui secrets/mcp.env).
  -c, --client CLIENT Cliente específico para configurar: claude, gemini, opencode, cursor ou all (padrão: all).
  -h, --help          Exibe esta mensagem de ajuda.
EOF
}

check_connectivity() {
    local url="$1"
    local http_code
    http_code="$(curl -s -m 4 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")"
    echo "$http_code"
}

check_ha_api() {
    local url="$1"
    local token="$2"
    local http_code
    http_code="$(curl -s -m 4 -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $token" "$url/api/" 2>/dev/null || echo "000")"
    echo "$http_code"
}

run_check() {
    local errors=0
    echo "=========================================================="
    echo "  Diagnóstico de MCP: Home Assistant (ha-mcp)"
    echo "=========================================================="
    echo "Endpoint alvo: $HA_URL"
    echo ""

    # 1. Checagem de uvx
    echo -n "[1/3] Utilitário uvx (Astral uv): "
    if command -v uvx >/dev/null 2>&1; then
        local uvx_ver
        uvx_ver="$(uvx --version 2>&1 | head -n 1)"
        echo "✓ OK ($uvx_ver)"
    else
        echo "❌ NÃO ENCONTRADO"
        echo "      Instale via: curl -LsSf https://astral.sh/uv/install.sh | sh"
        errors=$((errors + 1))
    fi

    # 2. Checagem de conectividade Tailscale
    echo -n "[2/3] Conectividade Tailscale ($HA_URL): "
    local code
    code="$(check_connectivity "$HA_URL")"
    if [[ "$code" == "200" || "$code" == "302" ]]; then
        echo "✓ OK (HTTP $code)"
    else
        echo "❌ FALHA (HTTP $code)"
        echo "      Não foi possível conectar a $HA_URL."
        echo "      Verifique se o Tailscale está ativo (sudo tailscale up / tailscale status)"
        echo "      e se a stack docker do Home Assistant está em execução na VPS."
        errors=$((errors + 1))
    fi

    # 3. Checagem de credenciais e API
    echo -n "[3/3] Token de Autenticação (HOMEASSISTANT_TOKEN): "
    if [[ -n "$HA_TOKEN" ]]; then
        echo "✓ Configurado (${#HA_TOKEN} chars)"
        if [[ "$code" == "200" || "$code" == "302" ]]; then
            echo -n "      Validando token na API REST (/api/): "
            local api_code
            api_code="$(check_ha_api "$HA_URL" "$HA_TOKEN")"
            if [[ "$api_code" == "200" ]]; then
                echo "✓ OK (API autenticada com sucesso)"
            else
                echo "⚠️  Falha na autenticação (HTTP $api_code). Verifique se o token é válido."
            fi
        fi
    else
        echo "⚠️  Não configurado"
        echo "      Crie o arquivo secrets/mcp.env a partir do template:"
        echo "        cp secrets/mcp.env.example secrets/mcp.env"
        echo "      E preencha HOMEASSISTANT_TOKEN com seu Long-Lived Access Token."
    fi

    echo ""
    echo "----------------------------------------------------------"
    if [[ $errors -eq 0 ]]; then
        echo "🎉 Ambiente pronto para integração com ha-mcp!"
        return 0
    else
        echo "💥 Foram encontrados $errors problema(s) no diagnóstico."
        return 1
    fi
}

configure_claude() {
    echo ""
    echo "=== [Claude Code] ==="
    local cmd="claude mcp add home-assistant -s user -e \"HOMEASSISTANT_URL=$HA_URL\" -e \"HOMEASSISTANT_TOKEN=${HA_TOKEN:-<SEU_TOKEN>}\" -- uvx ha-mcp"
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[dry-run] Executaria:"
        echo "  $cmd"
        return 0
    fi

    if ! command -v claude >/dev/null 2>&1; then
        echo "⚠️  Claude CLI não está instalado no PATH. Comando para executar manualmente:"
        echo "  $cmd"
        return 0
    fi

    if [[ -z "$HA_TOKEN" ]]; then
        echo "⚠️  HOMEASSISTANT_TOKEN não informado em secrets/mcp.env."
        echo "Para registrar manualmente após obter o token, execute:"
        echo "  $cmd"
        return 0
    fi

    echo "Registrando ha-mcp no Claude Code (user scope)..."
    # Remove se já existir para atualizar variáveis
    claude mcp remove home-assistant -s user < /dev/null >/dev/null 2>&1 || true
    if claude mcp add home-assistant -s user \
        -e "HOMEASSISTANT_URL=$HA_URL" \
        -e "HOMEASSISTANT_TOKEN=$HA_TOKEN" \
        -- uvx ha-mcp < /dev/null; then
        echo "✓ ha-mcp registrado com sucesso no Claude Code."
    else
        echo "❌ Falha ao registrar ha-mcp no Claude Code."
    fi
}

configure_gemini() {
    echo ""
    echo "=== [Gemini CLI / Antigravity] ==="
    local target_mcp="${AGY_MCP_CONFIG:-$HOME/.gemini/config/mcp_config.json}"
    local json_block
    json_block="$(cat <<EOF
{
  "command": "$WRAPPER",
  "args": [],
  "env": {
    "HOMEASSISTANT_URL": "$HA_URL",
    "HOMEASSISTANT_TOKEN": "${HA_TOKEN:-<SEU_TOKEN>}"
  }
}
EOF
)"
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[dry-run] Adicionaria a 'mcpServers.homeassistant' em $target_mcp:"
        echo "$json_block"
        return 0
    fi

    if [[ -z "$HA_TOKEN" ]]; then
        echo "⚠️  HOMEASSISTANT_TOKEN não informado em secrets/mcp.env."
        echo "Snippet para adicionar em '$target_mcp':"
        echo "$json_block"
        return 0
    fi

    if command -v jq >/dev/null 2>&1 && [[ -f "$target_mcp" ]]; then
        local tmp
        tmp="$(mktemp)"
        if jq --arg ha "$json_block" '.mcpServers.homeassistant = ($ha | fromjson)' "$target_mcp" > "$tmp" 2>/dev/null; then
            mv "$tmp" "$target_mcp"
            echo "✓ Servidor 'homeassistant' adicionado em $target_mcp."
        else
            rm -f "$tmp"
            echo "⚠️  Não foi possível mesclar automaticamente em $target_mcp. Atualize manualmente com:"
            echo "$json_block"
        fi
    else
        echo "Configuração sugerida para $target_mcp:"
        echo "$json_block"
    fi
}

configure_opencode() {
    echo ""
    echo "=== [OpenCode] ==="
    local opencode_snippet
    opencode_snippet="$(cat <<EOF
"homeassistant": {
  "type": "local",
  "command": ["$WRAPPER"],
  "enabled": true,
  "environment": {
    "HOMEASSISTANT_URL": "{env:HOMEASSISTANT_URL}",
    "HOMEASSISTANT_TOKEN": "{env:HOMEASSISTANT_TOKEN}"
  }
}
EOF
)"
    echo "O OpenCode suporta injeção de variáveis de ambiente ({env:VAR})."
    echo "Garante compatibilidade sem salvar o token em texto no disco."
    echo "Snippet para bloco 'mcp' em ~/.config/opencode/opencode.json ou opencode/opencode.json:"
    echo "$opencode_snippet"
}

configure_cursor() {
    echo ""
    echo "=== [Cursor] ==="
    local cursor_snippet
    cursor_snippet="$(cat <<EOF
{
  "mcpServers": {
    "homeassistant": {
      "command": "$WRAPPER",
      "args": [],
      "env": {
        "HOMEASSISTANT_URL": "$HA_URL",
        "HOMEASSISTANT_TOKEN": "${HA_TOKEN:-<SEU_TOKEN>}"
      }
    }
  }
}
EOF
)"
    echo "Snippet para adicionar em ~/.cursor/mcp.json ou .cursor/mcp.json:"
    echo "$cursor_snippet"
}

run_config() {
    echo "=========================================================="
    echo "  Configuração de MCP: Home Assistant (ha-mcp)"
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "  [MODO DRY-RUN - Nenhuma alteração será aplicada]"
    fi
    echo "=========================================================="
    echo "Endpoint: $HA_URL"
    if [[ -n "$HA_TOKEN" ]]; then
        echo "Token: Presente (${#HA_TOKEN} caracteres)"
    else
        echo "Token: Ausente (usando placeholder <SEU_TOKEN>)"
    fi

    case "$TARGET_CLIENT" in
        claude)
            configure_claude
            ;;
        gemini|antigravity)
            configure_gemini
            ;;
        opencode)
            configure_opencode
            ;;
        cursor)
            configure_cursor
            ;;
        all)
            configure_claude
            configure_gemini
            configure_opencode
            configure_cursor
            ;;
        *)
            echo "❌ Cliente inválido: $TARGET_CLIENT. Escolha: claude, gemini, opencode, cursor ou all." >&2
            exit 2
            ;;
    esac

    echo ""
    echo "----------------------------------------------------------"
    echo "✓ Procedimento de configuração concluído."
}

# Parsing de argumentos
while [[ $# -gt 0 ]]; do
    case "$1" in
        check|--check)
            COMMAND="check"
            ;;
        config|--config)
            COMMAND="config"
            ;;
        -d|--dry-run)
            DRY_RUN=1
            ;;
        -u|--url)
            shift
            [[ $# -gt 0 ]] || { echo "Erro: --url requer argumento." >&2; exit 2; }
            HA_URL="$1"
            ;;
        -t|--token)
            shift
            [[ $# -gt 0 ]] || { echo "Erro: --token requer argumento." >&2; exit 2; }
            HA_TOKEN="$1"
            ;;
        -c|--client)
            shift
            [[ $# -gt 0 ]] || { echo "Erro: --client requer argumento." >&2; exit 2; }
            TARGET_CLIENT="$1"
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Erro: Opção ou comando desconhecido: '$1'" >&2
            show_help >&2
            exit 2
            ;;
    esac
    shift
done

if [[ "$COMMAND" == "check" ]]; then
    run_check
elif [[ "$COMMAND" == "config" ]]; then
    run_config
fi
