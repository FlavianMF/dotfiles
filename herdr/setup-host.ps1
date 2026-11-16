<#
.SYNOPSIS
    Automates Herdr Desktop and WSL2 SSH configuration on Windows (Option C).

.DESCRIPTION
    1. Installs Herdr Desktop on Windows (if not already installed).
    2. Ensures a Windows OpenSSH keypair exists (~/.ssh/id_ed25519).
    3. Authorizes the Windows public key inside WSL2 (~/.ssh/authorized_keys).
    4. Configures ~/.ssh/config on Windows for 'Host wsl'.
    5. Tests the SSH connection from Windows to WSL2.
    6. Registers WSL as a machine in Herdr.

.PARAMETER WslUser
    The username inside WSL2. Defaults to auto-detecting via 'wsl.exe whoami'.

.PARAMETER WslPort
    The SSH port configured in WSL2. Defaults to 2222.

.PARAMETER SkipHerdrInstall
    Skips the automatic installation of Herdr Desktop.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\herdr\setup-host.ps1
#>

[CmdletBinding()]
param(
    [string]$WslUser,
    [int]$WslPort = 2222,
    [switch]$SkipHerdrInstall,
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"

function Write-Info { Write-Host "[INFO] $args" -ForegroundColor Green }
function Write-Warn { Write-Host "[WARN] $args" -ForegroundColor Yellow }
function Write-Error-Custom { Write-Host "[ERROR] $args" -ForegroundColor Red }

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  Herdr Desktop & WSL2 SSH Automation (Option C)  " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Detect WSL2 Environment
Write-Info "Checking WSL availability..."
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Write-Error-Custom "wsl.exe not found. Please ensure WSL2 is enabled."
    exit 1
}

if (-not $WslUser) {
    try {
        $DetectedUser = (wsl.exe -e whoami 2>$null).Trim()
        if ($DetectedUser) {
            $WslUser = $DetectedUser
            Write-Info "Auto-detected WSL username: $WslUser"
        }
    } catch {
        $WslUser = $env:USERNAME
        Write-Warn "Could not auto-detect WSL username. Falling back to: $WslUser"
    }
} else {
    Write-Info "Using specified WSL username: $WslUser"
}

# 2. Check / Install Herdr Desktop on Windows
$HerdrCmd = Get-Command herdr -ErrorAction SilentlyContinue
$HerdrExePath = "$env:LOCALAPPDATA\Programs\Herdr\herdr.exe"
$IsHerdrInstalled = ($null -ne $HerdrCmd) -or (Test-Path $HerdrExePath)

if (-not $IsHerdrInstalled -and -not $SkipHerdrInstall) {
    Write-Info "Herdr Desktop not detected on Windows. Starting installation..."
    try {
        Invoke-RestMethod https://releases.herdr.dev/app/install.ps1 | Invoke-Expression
        Write-Info "Herdr Desktop installed successfully."
    } catch {
        Write-Warn "Automatic installation encountered an error: $_"
        Write-Warn "You can download the Windows app manually from: https://github.com/herdrdev/herdr-app/releases"
    }
} else {
    Write-Info "Herdr Desktop is already installed (or installation was skipped)."
}

# 3. Ensure Windows SSH Key
$SshDir = Join-Path $env:USERPROFILE ".ssh"
if (-not (Test-Path $SshDir)) {
    New-Item -ItemType Directory -Path $SshDir -Force | Out-Null
}

$KeyPath = Join-Path $SshDir "id_ed25519"
$PubKeyPath = Join-Path $SshDir "id_ed25519.pub"

if (-not (Test-Path $PubKeyPath)) {
    # Check if another public key exists
    $ExistingPub = Get-ChildItem -Path $SshDir -Filter "*.pub" | Select-Object -First 1
    if ($ExistingPub) {
        $PubKeyPath = $ExistingPub.FullName
        $KeyPath = $PubKeyPath -replace '\.pub$', ''
        Write-Info "Using existing SSH key: $PubKeyPath"
    } else {
        Write-Info "Generating new ED25519 SSH keypair for Windows..."
        ssh-keygen -t ed25519 -f $KeyPath -N "" -q
        Write-Info "Generated key: $KeyPath"
    }
} else {
    Write-Info "Using SSH key: $PubKeyPath"
}

$PubKeyContent = (Get-Content -Path $PubKeyPath -Raw).Trim()

# 4. Authorize Windows Public Key inside WSL2
Write-Info "Authorizing Windows SSH key inside WSL2 for user '$WslUser'..."
try {
    # Run setup script in WSL to ensure sshd is ready
    wsl.exe -u $WslUser -e bash -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    
    # Check if key is already authorized
    $KeyAuthorized = wsl.exe -u $WslUser -e bash -c "grep -qF '$PubKeyContent' ~/.ssh/authorized_keys && echo 'YES' || echo 'NO'"
    if ($KeyAuthorized.Trim() -ne "YES") {
        wsl.exe -u $WslUser -e bash -c "echo '$PubKeyContent' >> ~/.ssh/authorized_keys"
        Write-Info "Windows public key added to WSL ~/.ssh/authorized_keys."
    } else {
        Write-Info "Windows public key is already authorized in WSL."
    }
} catch {
    Write-Warn "Could not automatically write to WSL ~/.ssh/authorized_keys: $_"
}

# 5. Configure Windows ~/.ssh/config for Host 'wsl'
$ConfigFile = Join-Path $SshDir "config"
$PosixKeyPath = ($KeyPath -replace '\\', '/')
$ConfigBlock = @"

# Herdr WSL2 SSH Configuration
Host wsl
    HostName localhost
    Port $WslPort
    User $WslUser
    IdentityFile "$PosixKeyPath"
    StrictHostKeyChecking accept-new
"@

$HasWslHost = $false
if (Test-Path $ConfigFile) {
    $ExistingConfig = Get-Content -Path $ConfigFile -Raw
    if ($ExistingConfig -match "(?m)^Host\s+wsl\b") {
        $HasWslHost = $true
        Write-Info "Host 'wsl' already present in $ConfigFile."
    }
}

if (-not $HasWslHost) {
    Write-Info "Appending 'Host wsl' to $ConfigFile..."
    Add-Content -Path $ConfigFile -Value $ConfigBlock
    Write-Info "Added 'Host wsl' configuration."
}

# 6. Test SSH Connection
Write-Info "Testing SSH connection to WSL2 (ssh -p $WslPort $WslUser@localhost)..."
try {
    $TestResult = ssh -p $WslPort -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$WslUser@localhost" "echo 'SSH_CONNECTION_SUCCESS'" 2>&1
    if ($TestResult -match "SSH_CONNECTION_SUCCESS") {
        Write-Host "[OK] SSH connection from Windows to WSL2 verified successfully!" -ForegroundColor Green
    } else {
        Write-Warn "SSH returned unexpected response: $TestResult"
        Write-Warn "Please verify that the SSH server in WSL2 is running (port $WslPort)."
    }
} catch {
    Write-Warn "SSH connection failed: $_"
    Write-Warn "Make sure the WSL SSH service is active by running 'make herdr-ssh-setup' inside WSL."
}

# 7. Add WSL Machine to Herdr Desktop
Write-Info "Checking Herdr machine registration..."
if (Get-Command herdr -ErrorAction SilentlyContinue) {
    try {
        herdr machine add wsl --label WSL
        Write-Host "[OK] Machine 'WSL' registered in Herdr successfully!" -ForegroundColor Green
    } catch {
        # If it was already added or requires user input
        Write-Info "Herdr machine command executed (verify in Herdr UI or run 'herdr machine list')."
    }
} else {
    Write-Info "Herdr CLI is not in Windows PATH yet."
    Write-Info "You can add it in Herdr Desktop GUI:"
    Write-Host "  1. Open Herdr Desktop." -ForegroundColor Cyan
    Write-Host "  2. Click '+' or 'Add Machine' in the left sidebar." -ForegroundColor Cyan
    Write-Host "  3. Label: WSL  |  Target: wsl (or ssh -p $WslPort $WslUser@localhost)" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  Setup Complete!                                " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "You can now connect to WSL directly with:"
Write-Host "  ssh wsl" -ForegroundColor Yellow
Write-Host "And select 'WSL' from the Herdr Desktop sidebar to manage agents."
Write-Host ""
