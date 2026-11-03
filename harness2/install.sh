#!/bin/bash
# Instala e reconcilia o Harness² (Recursive Agent Harnessing Framework).
# Repositório padrão: ~/projetos_harness/harness2
# Uso: harness2/install.sh [--dry-run] [--force] [--update] [--help]
set -euo pipefail

HARNESS2_HOME="${HARNESS2_HOME:-$HOME/projetos_harness/harness2}"
HARNESS2_REPO_URL="${HARNESS2_REPO_URL:-https://github.com/google-research/harness2.git}"
BIN_DIR="${HARNESS2_BIN_DIR:-$HOME/.local/bin}"
BINS=(harness2 harness2-setup harness2-check harness2-demo harness2-judge harness2-report harness2-bridge)

DRY_RUN=0
FORCE=0
UPDATE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            ;;
        --force)
            FORCE=1
            ;;
        --update)
            UPDATE=1
            ;;
        -h|--help)
            cat <<'EOF'
Uso: harness2/install.sh [opções]

Instala ou reconcilia o Harness² (Recursive Agent Harnessing Framework)
em ~/projetos_harness/harness2 com ambiente Python e links em ~/.local/bin.

Opções:
  --dry-run    Apenas exibe as ações de instalação sem alterar arquivos
  --force      Reinstala o ambiente virtual e dependências mesmo se já existirem
  --update     Atualiza o repositório git (pull) e reinstala o pacote
  -h, --help   Exibe esta mensagem de ajuda
EOF
            exit 0
            ;;
        *)
            echo "Opção desconhecida: $1" >&2
            echo "Use --help para ver as opções válidas." >&2
            exit 2
            ;;
    esac
    shift
done

if [[ $DRY_RUN -eq 1 ]]; then
    if [[ ! -d "$HARNESS2_HOME/.git" ]]; then
        echo "[dry-run] Clonaria $HARNESS2_REPO_URL em $HARNESS2_HOME"
    else
        echo "[dry-run] Repositório encontrado em $HARNESS2_HOME"
        if [[ $UPDATE -eq 1 ]]; then
            echo "[dry-run] Atualizaria o repositório via git pull"
        fi
    fi
    echo "[dry-run] Criaria/validaria venv Python 3.12 em $HARNESS2_HOME/.venv"
    echo "[dry-run] Instalaria pacote com uv/pip em modo editável: -e '.[render,bridge]'"
    echo "[dry-run] Criaria links em $BIN_DIR para: ${BINS[*]}"
    exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "Python 3 não encontrado; instale o componente python (Python 3.12+)" >&2
    exit 1
fi

if [[ ! -d "$HARNESS2_HOME/.git" ]]; then
    echo "[*] Clonando Harness² para $HARNESS2_HOME..."
    mkdir -p "$(dirname "$HARNESS2_HOME")"
    git clone "$HARNESS2_REPO_URL" "$HARNESS2_HOME"
else
    echo "✓ Repositório Harness² encontrado em $HARNESS2_HOME"
    if [[ $UPDATE -eq 1 ]]; then
        echo "[*] Atualizando repositório via git pull..."
        git -C "$HARNESS2_HOME" pull --ff-only || git -C "$HARNESS2_HOME" pull
    fi
fi

if [[ $FORCE -eq 1 && -d "$HARNESS2_HOME/.venv" ]]; then
    echo "[*] Removendo venv existente (--force)..."
    rm -rf "$HARNESS2_HOME/.venv"
fi

if [[ ! -f "$HARNESS2_HOME/.venv/bin/python" ]]; then
    echo "[*] Criando ambiente virtual Python em $HARNESS2_HOME/.venv..."
    if command -v uv >/dev/null 2>&1; then
        uv venv "$HARNESS2_HOME/.venv" --python python3.12 2>/dev/null || uv venv "$HARNESS2_HOME/.venv"
    else
        python3 -m venv "$HARNESS2_HOME/.venv"
    fi
fi

echo "[*] Instalando dependências do Harness² em modo editável..."
if command -v uv >/dev/null 2>&1; then
    uv pip install --python "$HARNESS2_HOME/.venv" -e "${HARNESS2_HOME}[render,bridge]"
elif [[ -x "$HARNESS2_HOME/.venv/bin/pip" ]]; then
    "$HARNESS2_HOME/.venv/bin/pip" install -e "${HARNESS2_HOME}[render,bridge]"
else
    # uv venv sem pip: usa python -m ensurepip ou uv se disponível
    python3 -m venv "$HARNESS2_HOME/.venv"
    "$HARNESS2_HOME/.venv/bin/pip" install -e "${HARNESS2_HOME}[render,bridge]"
fi

echo "[*] Vinculando executáveis em $BIN_DIR..."
mkdir -p "$BIN_DIR"
for bin_name in "${BINS[@]}"; do
    if [[ -x "$HARNESS2_HOME/.venv/bin/$bin_name" ]]; then
        ln -sf "$HARNESS2_HOME/.venv/bin/$bin_name" "$BIN_DIR/$bin_name"
    fi
done

echo ""
echo "=========================================================="
echo "✓ Harness² instalado com sucesso!"
echo "Executáveis vinculados em $BIN_DIR:"
for bin_name in "${BINS[@]}"; do
    [[ -x "$BIN_DIR/$bin_name" ]] && echo "  - $bin_name"
done
echo ""
echo "Configuração recomendada:"
echo "  1. Copie secrets/harness2.env.example para ~/dotfiles/secrets/harness2.env"
echo "  2. Preencha GOOGLE_CLOUD_PROJECT, HARNESS2_SOLVER_MODEL, etc."
echo "  3. Valide o setup com: harness2-check"
echo "=========================================================="
