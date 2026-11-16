# Herdr Installation & WSL2 Integration Guide (Option C)

This guide documents **Option C**: running the native **Herdr Desktop GUI** on Windows with hardware GPU acceleration (Vulkan) while executing terminal multiplexing, tools, and AI coding agents (Claude Code, Antigravity, OpenCode, Codex, etc.) inside **WSL2** over SSH.

---

## 1. Architecture Overview

```
+-------------------------------------------------------+
| Windows 10 / 11 Host                                  |
|                                                       |
|  +-------------------------------------------------+  |
|  | Herdr Desktop App (herdr-app)                   |  |
|  | - Native GPU acceleration (DirectX / Vulkan)    |  |
|  | - Workspaces, tabs, splits, real-time agent UI  |  |
|  +------------------------+------------------------+  |
|                           |                           |
|                    SSH to localhost:2222              |
+---------------------------|---------------------------+
                            |
+---------------------------v---------------------------+
| WSL2 (Ubuntu / Linux)                                 |
|                                                       |
|  +-------------------------------------------------+  |
|  | OpenSSH Server (sshd on port 2222)              |  |
|  +------------------------+------------------------+  |
|                           |                           |
|  +------------------------v------------------------+  |
|  | Herdr Core & CLI (~/.local/bin/herdr)           |  |
|  | AI Coding Agents (Claude, Antigravity, etc.)    |  |
|  | Development tools, compilers, dotfiles          |  |
|  +-------------------------------------------------+  |
+-------------------------------------------------------+
```

### Why Option C?
- **Native performance:** The GUI runs natively on Windows with hardware acceleration and crisp font rendering without depending on WSLg Vulkan translation layers.
- **Full Linux toolchain:** All CLI tools, dev packages, and agents run in their native Linux environment inside WSL2.
- **Persistent sessions:** `herdr-core` in WSL keeps terminal sessions and agents alive even when the Windows GUI client is closed or restarted.

---

## 2. Quick Setup (Automated)

The dotfiles repository provides two automated scripts for both sides of the bridge:

### Step A: WSL2 Side (Run inside WSL)
In your WSL2 terminal, run:
```bash
make herdr-ssh-setup
```
*(Or directly: `./herdr/setup-wsl-ssh.sh`)*

**What this script does:**
1. Verifies/installs OpenSSH Server (`openssh-server`).
2. Configures `sshd` to listen on **port 2222** (avoiding collision with any Windows SSH server on port 22).
3. Ensures `ssh.service` is enabled and active in `systemd`.
4. Sets strict permissions on `~/.ssh` (`700`) and `~/.ssh/authorized_keys` (`600`).
5. Automatically scans `/mnt/c/Users/*/.ssh/*.pub` and imports your Windows SSH public keys into `authorized_keys`.
6. Checks that `herdr` CLI is installed and configured in WSL2.

---

### Step B: Windows Host Side (Run in Windows PowerShell)
Open **PowerShell** on Windows (Run as your regular user) in the root of the dotfiles repository:
```powershell
powershell -ExecutionPolicy Bypass -File .\herdr\setup-host.ps1
```

**What this script does:**
1. Auto-detects your WSL distribution username.
2. Checks if Herdr Desktop is installed on Windows; if missing, downloads and installs it.
3. Ensures an SSH key exists on Windows (`~/.ssh/id_ed25519`).
4. Uses `wsl.exe` to authorize the Windows public key inside WSL2 without requiring manual copy-pasting.
5. Adds a convenient `Host wsl` profile to Windows `~/.ssh/config`:
   ```ssh-config
   Host wsl
       HostName localhost
       Port 2222
       User <your-wsl-user>
       IdentityFile ~/.ssh/id_ed25519
       StrictHostKeyChecking accept-new
   ```
6. Tests the connection (`ssh wsl`) to confirm zero-prompt passwordless access.
7. Registers WSL in Herdr as a saved machine profile (`herdr machine add wsl --label WSL`).

---

## 3. Manual Step-by-Step Instructions

If you prefer configuring the bridge manually:

### 1. Configure OpenSSH Server in WSL2
1. Install OpenSSH server:
   ```bash
   sudo apt-get update && sudo apt-get install -y openssh-server
   ```
2. Configure port 2222 in `/etc/ssh/sshd_config.d/60-herdr.conf`:
   ```ssh-config
   Port 2222
   PubkeyAuthentication yes
   PasswordAuthentication yes
   ```
3. Enable and start the SSH service:
   ```bash
   sudo systemctl enable --now ssh
   ```

### 2. Install Herdr Desktop on Windows
In Windows PowerShell:
```powershell
irm https://releases.herdr.dev/app/install.ps1 | iex
```

### 3. Generate Windows SSH Key and Authorize in WSL
1. In Windows PowerShell, generate a key if you don't have one:
   ```powershell
   ssh-keygen -t ed25519
   ```
2. Read the public key content:
   ```powershell
   Get-Content ~\.ssh\id_ed25519.pub
   ```
3. Inside WSL, append this public key to `~/.ssh/authorized_keys`:
   ```bash
   mkdir -p ~/.ssh && chmod 700 ~/.ssh
   echo "<PASTE_WINDOWS_PUBKEY_HERE>" >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```

### 4. Create Windows SSH Config Alias
In Windows, edit `C:\Users\<YourUser>\.ssh\config`:
```ssh-config
Host wsl
    HostName localhost
    Port 2222
    User <your-wsl-username>
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
```
Test the connection:
```powershell
ssh wsl
```

### 5. Add Machine in Herdr Desktop
- **Via CLI (Recommended for first run):**
  Open Windows PowerShell and run:
  ```powershell
  hc machine add wsl
  ```
  *(Or with automatic install: `hc machine add wsl --install`)*
- **Via GUI:** Open Herdr Desktop on Windows. Click **Add Machine** (or `+`) in the left sidebar:
  - **Label:** `WSL`
  - **Target:** `wsl` (or `ssh -p 2222 <user>@localhost`)
  *(Note: The GUI cannot answer interactive prompts. If adding via GUI fails, run `hc machine add wsl` in a terminal first).*

---

## 4. Usage & Workflows

Once the WSL machine is connected in Herdr Desktop:

1. **Sidebar Navigation:** Click `WSL` in the left sidebar to access your WSL workspaces and tabs.
2. **Terminal Panes:** Split panes (`Ctrl+Space` + `v` for vertical, `Ctrl+Space` + `-` for horizontal) open directly inside your Linux distro.
3. **Coding Agents:** Launch coding agents inside panes:
   ```bash
   claude
   # or
   codex
   # or
   agy
   ```
4. **Agent Monitoring:** Herdr detects agent states (*idle*, *working*, *blocked*, *done*) and displays indicators on the sidebar tabs.

---

## 5. Troubleshooting & FAQ

### Error: "Couldn't add wsl here: it needs you to answer something (a password, a new host key, or installing herdr-core there)"
This happens when you click **Add Machine** in the Herdr Desktop GUI before approving the SSH connection or installing `herdr-core` in WSL. Because the GUI dialog cannot present an interactive terminal prompt (such as asking for your password, asking `Are you sure you want to continue connecting (yes/no)?`, or asking to install `herdr-core`), it cancels immediately.

**Fix:**
1. Open **Windows PowerShell** (or Windows Terminal).
2. Run:
   ```powershell
   hc machine add wsl
   ```
   *(If `hc` is not in your Windows PATH, use: `& "$env:LOCALAPPDATA\Programs\Herdr\hc.exe" machine add wsl`)*
3. If it asks:
   - `Are you sure you want to continue connecting (yes/no)?` -> Type `yes` and press Enter.
   - If prompted for a password -> Enter your WSL password.
   - If prompted to install or select session -> Confirm with Enter.
4. Once completed, the `wsl` machine is saved and will appear active in Herdr Desktop.

Alternatively, you can add WSL without SSH using Herdr's direct WSL bridge:
```powershell
hc machine add --via "wsl.exe -e sh -c" --name wsl
```

### Connection Refused (`port 2222: Connection refused`)
- Verify that `sshd` is running in WSL2:
  ```bash
  systemctl status ssh
  ```
- If stopped, run:
  ```bash
  sudo systemctl restart ssh
  ```
- Check that WSL2 has systemd enabled in `/etc/wsl.conf`:
  ```ini
  [boot]
  systemd=true
  ```
  If you recently changed this, restart WSL from PowerShell via `wsl --shutdown`.

### Password Prompt on Every Connection
- Ensure file permissions in WSL2 are strict:
  ```bash
  chmod 700 ~/.ssh
  chmod 600 ~/.ssh/authorized_keys
  ```
- Ensure the Windows public key line inside `~/.ssh/authorized_keys` is exactly one line without broken formatting.

### WSL IP / Localhost Mapping
- By default, WSL2 forwards ports bound to `0.0.0.0` or `127.0.0.1` to Windows `localhost`.
- If you use Mirrored networking (`networkingMode=mirrored` in `%USERPROFILE%\.wslconfig`), `localhost:2222` works directly and seamlessly.
