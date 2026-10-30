#!/bin/bash
# Instala o cliente Tailscale no Linux / WSL2 via repositório oficial.
# Uso: tailscale/install.sh [--dry-run] [--help]
set -euo pipefail

DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            ;;
        -h|--help)
            cat <<'EOF'
Uso: tailscale/install.sh [opções]

Instala o cliente Tailscale (VPN Mesh WireGuard) no Linux / WSL2.

Opções:
  --dry-run    Apenas exibe as ações de instalação sem modificar o sistema
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

if command -v tailscale >/dev/null 2>&1; then
    version="$(tailscale version 2>/dev/null | head -n 1 || echo "desconhecida")"
    echo "✓ Tailscale já está instalado (versão: $version)."
    echo "Para verificar status: tailscale status"
    echo "Para conectar: sudo tailscale up"
    exit 0
fi

if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] Instalaria o Tailscale via https://tailscale.com/install.sh"
    echo "[dry-run] Habilitaria e iniciaria o serviço tailscaled via systemd"
    echo "[dry-run] Instruiria a rodar 'sudo tailscale up' para autenticação"
    exit 0
fi

echo "[*] Baixando e instalando Tailscale via instalador oficial..."
curl -fsSL https://tailscale.com/install.sh | sh

if [ -d /run/systemd/system ]; then
    echo "[*] Habilitando serviço tailscaled no systemd..."
    sudo systemctl enable --now tailscaled 2>/dev/null || true
fi

echo ""
echo "=========================================================="
echo "✓ Tailscale instalado com sucesso!"
echo "Para conectar esta máquina à sua rede privada:"
echo "  👉 sudo tailscale up"
echo "=========================================================="
