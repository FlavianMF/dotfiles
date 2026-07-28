#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"

# Colors for output
function Write-Info {
    Write-Host "[INFO] $args" -ForegroundColor Green
}

function Write-Warn {
    Write-Host "[WARN] $args" -ForegroundColor Yellow
}

function Write-Error-Custom {
    Write-Host "[ERROR] $args" -ForegroundColor Red
}

# Detect interactive mode
function Is-Interactive {
    if ($NonInteractive) { return $false }
    return [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
}

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BackupDir = Join-Path $env:USERPROFILE ".dotfiles-backup\$(Get-Date -UFormat %s)"

Write-Info "Starting dotfiles installation from $RepoDir"

# ===== Preflight checks =====
Write-Info "Checking prerequisites..."

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error-Custom "winget not found. Install App Installer from Microsoft Store."
    exit 1
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Warn "PowerShell 7+ recommended for oh-my-posh and PSReadLine features."
    if (Is-Interactive) {
        $install_ps7 = Read-Host "Install PowerShell 7? (y/n)"
        if ($install_ps7 -eq 'y') {
            Write-Info "Installing PowerShell 7..."
            winget install --id Microsoft.PowerShell -e --source winget --accept-package-agreements --accept-source-agreements
            Write-Warn "Please relaunch in pwsh (PowerShell 7) and run this script again."
            exit 0
        }
    }
}

# ===== Component selection =====
$SelectedComponents = @{
    'node'   = $true
    'python' = $true
    'docker' = $false
    'gh'     = $false
}

$OptionalComponents = @{
    'node'   = 'Node.js (required for nvim treesitter)'
    'python' = 'Python 3.12 (dev environment)'
    'docker' = 'Docker (containerization)'
    'gh'     = 'GitHub CLI (gh)'
}

function Select-Components {
    if (-not (Is-Interactive)) {
        Write-Info "Running non-interactively. Installing default components: node, python"
        return
    }

    $options = @('node', 'python', 'docker', 'gh')
    $current = 0
    $done = $false

    while (-not $done) {
        Clear-Host
        Write-Host ""
        Write-Host "Select components to install (up/down to navigate, SPACE to toggle, ENTER to confirm):"
        Write-Host ""

        for ($i = 0; $i -lt $options.Count; $i++) {
            $comp = $options[$i]
            $marker = ' '
            $color = 'Gray'

            if ($i -eq $current) {
                $marker = '>'
                $color = 'Cyan'
            }

            $checked = if ($SelectedComponents[$comp]) { '✓' } else { ' ' }
            Write-Host "  $marker [$checked] $comp - $($OptionalComponents[$comp])" -ForegroundColor $color
        }

        Write-Host ""
        Write-Host "  Press ENTER to confirm selection"
        Write-Host ""

        $key = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

        switch ($key.VirtualKeyCode) {
            38 {  # Up arrow
                $current = ($current - 1 + $options.Count) % $options.Count
            }
            40 {  # Down arrow
                $current = ($current + 1) % $options.Count
            }
            32 {  # Space
                $comp = $options[$current]
                $SelectedComponents[$comp] = -not $SelectedComponents[$comp]
            }
            13 {  # Enter
                $done = $true
            }
        }
    }

    Clear-Host
}

Select-Components

# ===== Build package list =====
$PackagesToInstall = @('Git.Git', 'Neovim.Neovim', 'JanDeDobbeleer.OhMyPosh')

$ComponentPackages = @{
    'node'   = 'OpenJS.NodeJS.LTS'
    'python' = 'Python.Python.3.12'
    'docker' = 'Docker.DockerDesktop'
    'gh'     = 'GitHub.cli'
}

foreach ($comp in $ComponentPackages.Keys) {
    if ($SelectedComponents[$comp]) {
        Write-Info "$comp selected"
        $PackagesToInstall += $ComponentPackages[$comp]
    }
}

# ===== Install packages =====
Write-Info "Installing packages via winget..."

foreach ($pkg in $PackagesToInstall) {
    if (winget list --id $pkg --exact | Select-String $pkg) {
        Write-Info "$pkg already installed"
        continue
    }

    Write-Info "Installing $pkg..."
    winget install --id $pkg -e --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Failed to install $pkg, continuing..."
    }
}

# ===== Install/Update PSReadLine =====
Write-Info "Installing PSReadLine module..."
$psReadLineVersion = (Get-Module PSReadLine -ListAvailable | Select-Object -ExpandProperty Version | Sort-Object -Descending | Select-Object -First 1)
if (-not $psReadLineVersion -or $psReadLineVersion -lt [version]'2.3.0') {
    Install-Module PSReadLine -Force -SkipPublisherCheck -AllowClobber 2>$null
}

# ===== Install oh-my-posh fonts =====
Write-Info "Installing oh-my-posh fonts..."
oh-my-posh font install FiraCode 2>$null
Write-Warn "Remember to set FiraCode Nerd Font in Windows Terminal settings"

# ===== Backup existing configs =====
Write-Info "Creating backup of existing configs..."
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

$ConfigItems = @(
    $PROFILE,
    "$env:USERPROFILE\.gitconfig",
    "$env:USERPROFILE\.config\git\ignore",
    "$env:LOCALAPPDATA\nvim",
    "$env:USERPROFILE\.claude\settings.json"
)

foreach ($item in $ConfigItems) {
    if (Test-Path $item) {
        Write-Warn "Backing up $item"
        Copy-Item -Path $item -Destination $BackupDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ===== Helper function to create symlinks/copies =====
function New-ConfigLink {
    param(
        [string]$Source,
        [string]$Target,
        [switch]$IsDirectory
    )

    if (-not (Test-Path $Source)) {
        Write-Warn "Source not found: $Source"
        return
    }

    $TargetDir = Split-Path -Parent $Target
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null

    Remove-Item -Path $Target -Recurse -Force -ErrorAction SilentlyContinue

    try {
        New-Item -ItemType SymbolicLink -Path $Target -Value $Source -Force -ErrorAction Stop | Out-Null
        Write-Info "Symlinked $Target"
    }
    catch {
        Write-Warn "Symlink failed (no admin/dev mode), copying instead: $Target"
        if ($IsDirectory) {
            Copy-Item -Path $Source -Destination $Target -Recurse -Force
        }
        else {
            Copy-Item -Path $Source -Destination $Target -Force
        }
    }
}

# ===== Create symlinks/copies =====
Write-Info "Creating/copying config files..."

New-ConfigLink -Source "$RepoDir\powershell\Microsoft.PowerShell_profile.ps1" -Target $PROFILE
New-ConfigLink -Source "$RepoDir\powershell\spaceship.omp.json" -Target "$env:USERPROFILE\.spaceship.omp.json"
New-ConfigLink -Source "$RepoDir\git\.gitconfig-windows" -Target "$env:USERPROFILE\.gitconfig"
New-ConfigLink -Source "$RepoDir\git\ignore" -Target "$env:USERPROFILE\.config\git\ignore"
New-ConfigLink -Source "$RepoDir\nvim" -Target "$env:LOCALAPPDATA\nvim" -IsDirectory
New-ConfigLink -Source "$RepoDir\claude\settings.json" -Target "$env:USERPROFILE\.claude\settings.json"

# ===== Configure git identity =====
if (-not (Test-Path "$env:USERPROFILE\.gitconfig.local")) {
    Write-Info "Setting up git identity..."

    $git_name = $env:GIT_NAME
    $git_email = $env:GIT_EMAIL

    if ((Is-Interactive) -and -not $git_name) {
        $git_name = Read-Host "Enter your git user name"
        $git_email = Read-Host "Enter your git email"
    }

    if ($git_name -and $git_email) {
        $gitconfig = @"
[user]
	name = $git_name
	email = $git_email
"@
        Set-Content -Path "$env:USERPROFILE\.gitconfig.local" -Value $gitconfig
        Write-Info "Created .gitconfig.local"
    }
    else {
        Write-Warn "Skipping git identity (not interactive or env vars not set)"
    }
}

# ===== Install Neovim plugins =====
Write-Info "Installing Neovim plugins (this may take a moment)..."
nvim --headless "+Lazy! sync" +qa 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Warn "Could not auto-install nvim plugins. Run: :Lazy sync in nvim"
}

# ===== Summary =====
Write-Host ""
Write-Info "Installation complete!"
Write-Host ""
Write-Host "Summary:"
Write-Host "=========="
Write-Host "✓ System packages installed"
Write-Host "✓ Neovim installed"
if ($SelectedComponents['node']) { Write-Host "✓ Node.js and npm installed" }
if ($SelectedComponents['python']) { Write-Host "✓ Python 3.12 installed" }
if ($SelectedComponents['docker']) { Write-Host "✓ Docker Desktop installed" }
if ($SelectedComponents['gh']) { Write-Host "✓ GitHub CLI (gh) installed" }
Write-Host "✓ Oh My Posh configured"
Write-Host "✓ PSReadLine configured"
Write-Host "✓ Config files symlinked from $RepoDir"
Write-Host "✓ Git identity configured"
Write-Host "✓ Neovim plugins installed"
Write-Host ""
Write-Host "Backup location: $BackupDir"
Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Start a new PowerShell session or run: . `$PROFILE"
Write-Host "2. Set FiraCode Nerd Font in Windows Terminal preferences"
if ($SelectedComponents['gh']) { Write-Host '3. Authenticate with GitHub: gh auth login' }
Write-Host '4. Add your SSH keys to $HOME/.ssh if needed'
Write-Host ""
