#!/bin/bash
# Instala o enriquecedor de cotas do Antigravity no Traycer host runtime,
# habilitando a extração dos limites de Gemini Models (Flash/Pro) e Gemini 4 Argon.
# Uso: traycer/install_quota_enricher.sh [--dry-run]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        *) echo "Opção desconhecida: $arg" >&2; exit 2 ;;
    esac
done

command -v python3 >/dev/null 2>&1 || { echo "python3 é necessário para aplicar o patch" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "node é necessário para validar a sintaxe" >&2; exit 1; }

TARGET="${TRAYCER_HOST_MAIN_PATH:-$HOME/.traycer/host/install/host-runtime/host-main.cjs}"

if [[ ! -f "$TARGET" ]]; then
    echo "host-main.cjs não encontrado em $TARGET" >&2
    exit 1
fi

if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] Aplicaria patch em $TARGET"
    exit 0
fi

python3 "$ROOT/patch_antigravity_quota.py"
echo "Patch aplicado com sucesso em $TARGET."
echo "Para recarregar o host do Traycer e ativar as novas cotas:"
echo "  systemctl --user restart ai.traycer.host.service"
