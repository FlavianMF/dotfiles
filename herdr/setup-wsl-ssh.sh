#!/bin/bash
# Herdr WSL2 SSH Server Setup
# Configures OpenSSH server on port 2222 and imports Windows SSH keys.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT=2222
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_D="/etc/ssh/sshd_config.d"
HERDR_SSHD_CONF="$SSHD_CONFIG_D/60-herdr-wsl.conf"

echo "=== Herdr WSL2 SSH Setup ==="

# 1. Check OpenSSH Server installation
if ! command -v sshd >/dev/null 2>&1; then
    echo "[INFO] OpenSSH server not found. Installing..."
    sudo apt-get update && sudo apt-get install -y openssh-server
else
    echo "[OK] OpenSSH server is installed ($(sshd -V 2>&1 | head -n1))."
fi

# 2. Configure SSH Port and Settings
NEEDS_RELOAD=0
if [[ -d "$SSHD_CONFIG_D" ]]; then
    if [[ ! -f "$HERDR_SSHD_CONF" ]]; then
        echo "[INFO] Writing Herdr SSH configuration to $HERDR_SSHD_CONF..."
        sudo tee "$HERDR_SSHD_CONF" >/dev/null <<EOF
# Configured for Herdr WSL2 SSH integration
Port $PORT
PubkeyAuthentication yes
PasswordAuthentication yes
EOF
        NEEDS_RELOAD=1
    fi
else
    # Fallback: check if port is in sshd_config
    if ! grep -qE "^\s*Port\s+$PORT" "$SSHD_CONFIG"; then
        echo "[INFO] Configuring Port $PORT in $SSHD_CONFIG..."
        echo "Port $PORT" | sudo tee -a "$SSHD_CONFIG" >/dev/null
        NEEDS_RELOAD=1
    fi
fi

# 3. Ensure service is enabled & running in systemd
if pidof systemd >/dev/null 2>&1; then
    if ! systemctl is-enabled ssh >/dev/null 2>&1; then
        echo "[INFO] Enabling ssh systemd service..."
        sudo systemctl enable ssh
    fi

    if ! systemctl is-active --quiet ssh || [[ $NEEDS_RELOAD -eq 1 ]]; then
        echo "[INFO] Starting / restarting ssh service..."
        sudo systemctl restart ssh
    fi
    echo "[OK] SSH service is active on systemd."
else
    # SysVinit / service fallback if systemd is not active
    echo "[WARN] systemd not detected. Starting ssh service via service manager..."
    sudo service ssh start || sudo /usr/sbin/sshd
fi

# 4. Prepare user ~/.ssh folder and authorized_keys
SSH_DIR="$HOME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
touch "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"

# 5. Automatically import Windows SSH public keys if present
IMPORTED=0
shopt -s nullglob
WINDOWS_PUB_KEYS=(/mnt/c/Users/*/.ssh/*.pub)
shopt -u nullglob

if [[ ${#WINDOWS_PUB_KEYS[@]} -gt 0 ]]; then
    echo "[INFO] Searching for Windows SSH public keys in /mnt/c/Users/*/.ssh/..."
    for pub in "${WINDOWS_PUB_KEYS[@]}"; do
        # Ignore known_hosts or invalid files
        [[ -f "$pub" ]] || continue
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip empty lines or non-key lines
            [[ "$line" =~ ^(ssh-|ecdsa-|sk-) ]] || continue
            if ! grep -qF "$line" "$AUTH_KEYS" 2>/dev/null; then
                echo "$line" >> "$AUTH_KEYS"
                echo "  [+] Imported key: $pub"
                IMPORTED=$((IMPORTED + 1))
            fi
        done < "$pub"
    done
fi

if [[ $IMPORTED -gt 0 ]]; then
    echo "[OK] Imported $IMPORTED Windows SSH public key(s) to $AUTH_KEYS."
else
    echo "[INFO] No new Windows SSH keys needed importing."
fi

# 6. Verify Herdr CLI in WSL
if ! command -v herdr >/dev/null 2>&1; then
    echo "[WARN] Herdr CLI not found in PATH."
    if [[ -x "$ROOT/install.sh" ]]; then
        echo "[INFO] Installing Herdr CLI via $ROOT/install.sh..."
        "$ROOT/install.sh"
    fi
else
    echo "[OK] Herdr CLI is installed: $(herdr --version 2>/dev/null || echo 'herdr')"
fi

echo ""
echo "=== Setup Complete ==="
echo "WSL SSH daemon listening on: port $PORT"
echo "WSL Username: $USER"
echo ""
echo "From Windows PowerShell, you can test the connection with:"
echo "  ssh -p $PORT $USER@localhost"
echo ""
echo "Or run the host automated script from Windows:"
echo "  powershell -ExecutionPolicy Bypass -File .\\herdr\\setup-host.ps1"
