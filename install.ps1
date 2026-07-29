#Requires -Version 5.1
[CmdletBinding()]
param([switch]$NonInteractive)

$ErrorActionPreference = "Stop"

function Write-Info { Write-Host "[INFO] $args" -ForegroundColor Green }
function Write-Warn { Write-Host "[WARN] $args" -ForegroundColor Yellow }
function Write-Error-Custom { Write-Host "[ERROR] $args" -ForegroundColor Red }

function Is-Interactive {
    if ($NonInteractive) { return $false }
    return [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
}

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BackupDir = Join-Path $env:USERPROFILE ".dotfiles-backup\$(Get-Date -UFormat %s)"

Write-Info "Starting dotfiles installation from $RepoDir"

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
            Write-Warn "Please relaunch in pwsh and run this script again."
            exit 0
        }
    }
}

$SelectedComponents = @{'node'=$true; 'python'=$true; 'docker'=$false; 'gh'=$false}
$OptionalComponents = @{'node'='Node.js (required for nvim treesitter)'; 'python'='Python 3.12 (dev environment)'; 'docker'='Docker (containerization)'; 'gh'='GitHub CLI (gh)'}

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
        Write-Host "Select components (up/down arrow, SPACE to toggle, ENTER to confirm):"
        Write-Host ""

        for ($i = 0; $i -lt $options.Count; $i++) {
            $comp = $options[$i]
            $marker = if ($i -eq $current) { '>' } else { ' ' }
            $color = if ($i -eq $current) { 'Cyan' } else { 'Gray' }
            $checked = if ($SelectedComponents[$comp]) { 'X' } else { ' ' }
            Write-Host "  $marker [$checked] $comp - $($OptionalComponents[$comp])" -ForegroundColor $color
        }

        Write-Host ""
        Write-Host "  Press ENTER to confirm"
        Write-Host ""

        $key = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

        switch ($key.VirtualKeyCode) {
            38 { $current = ($current - 1 + $options.Count) % $options.Count }
            40 { $current = ($current + 1) % $options.Count }
            32 { $SelectedComponents[$options[$current]] = -not $SelectedComponents[$options[$current]] }
            13 { $done = $true }
        }
    }

    Clear-Host
}

Select-Components

$PackagesToInstall = @('Git.Git', 'Neovim.Neovim', 'JanDeDobbeleer.OhMyPosh')
$ComponentPackages = @{'node'='OpenJS.NodeJS.LTS'; 'python'='Python.Python.3.12'; 'docker'='Docker.DockerDesktop'; 'gh'='GitHub.cli'}

foreach ($comp in $ComponentPackages.Keys) {
    if ($SelectedComponents[$comp]) {
        Write-Info "$comp selected"
        $PackagesToInstall += $ComponentPackages[$comp]
    }
}

Write-Info "Installing packages via winget..."

foreach ($pkg in $PackagesToInstall) {
    Write-Info "Installing $pkg..."
    winget install --id $pkg -e --source winget --accept-package-agreements --accept-source-agreements -h 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Info "$pkg installed successfully"
    }
    else {
        Write-Warn "$pkg install failed or already present, continuing..."
    }
}

Write-Info "Installing PSReadLine module..."
$psReadLineVersion = (Get-Module PSReadLine -ListAvailable | Select-Object -ExpandProperty Version | Sort-Object -Descending | Select-Object -First 1)
if (-not $psReadLineVersion -or $psReadLineVersion -lt [version]'2.3.0') {
    Install-Module PSReadLine -Force -SkipPublisherCheck -AllowClobber 2>$null
}

Write-Info "Installing oh-my-posh fonts..."
oh-my-posh font install FiraCode 2>$null
Write-Warn "Remember to set FiraCode Nerd Font in Windows Terminal settings"

Write-Info "Creating backup of existing configs..."
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

$ConfigItems = @($PROFILE, "$env:USERPROFILE\.gitconfig", "$env:USERPROFILE\.config\git\ignore", "$env:LOCALAPPDATA\nvim", "$env:USERPROFILE\.claude\settings.json")

foreach ($item in $ConfigItems) {
    if (Test-Path $item) {
        Write-Warn "Backing up $item"
        Copy-Item -Path $item -Destination $BackupDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-ConfigLink {
    param([string]$Source, [string]$Target, [switch]$IsDirectory)

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
        Write-Warn "Symlink failed, copying instead: $Target"
        if ($IsDirectory) {
            Copy-Item -Path $Source -Destination $Target -Recurse -Force
        }
        else {
            Copy-Item -Path $Source -Destination $Target -Force
        }
    }
}

Write-Info "Creating/copying config files..."
New-ConfigLink -Source "$RepoDir\powershell\Microsoft.PowerShell_profile.ps1" -Target $PROFILE
New-ConfigLink -Source "$RepoDir\powershell\spaceship.omp.json" -Target "$env:USERPROFILE\.spaceship.omp.json"
New-ConfigLink -Source "$RepoDir\git\.gitconfig-windows" -Target "$env:USERPROFILE\.gitconfig"
New-ConfigLink -Source "$RepoDir\git\ignore" -Target "$env:USERPROFILE\.config\git\ignore"
New-ConfigLink -Source "$RepoDir\nvim" -Target "$env:LOCALAPPDATA\nvim" -IsDirectory
New-ConfigLink -Source "$RepoDir\claude\settings.json" -Target "$env:USERPROFILE\.claude\settings.json"

if (-not (Test-Path "$env:USERPROFILE\.gitconfig.local")) {
    Write-Info "Setting up git identity..."

    $git_name = $env:GIT_NAME
    $git_email = $env:GIT_EMAIL

    if ((Is-Interactive) -and -not $git_name) {
        $git_name = Read-Host "Enter your git user name"
        $git_email = Read-Host "Enter your git email"
    }

    if ($git_name -and $git_email) {
        $gitconfig = "[user]`n`tname = $git_name`n`temail = $git_email"
        Set-Content -Path "$env:USERPROFILE\.gitconfig.local" -Value $gitconfig
        Write-Info "Created .gitconfig.local"
    }
    else {
        Write-Warn "Skipping git identity"
    }
}

Write-Info "Installing Neovim plugins..."
nvim --headless "+Lazy! sync" +qa 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Warn "Could not auto-install nvim plugins. Run: :Lazy sync in nvim"
}

Write-Host ""
Write-Info "Installation complete!"
Write-Host ""
Write-Host "Summary:"
Write-Host "=========="
Write-Host "[OK] System packages installed"
Write-Host "[OK] Neovim installed"
if ($SelectedComponents['node']) { Write-Host "[OK] Node.js and npm installed" }
if ($SelectedComponents['python']) { Write-Host "[OK] Python 3.12 installed" }
if ($SelectedComponents['docker']) { Write-Host "[OK] Docker Desktop installed" }
if ($SelectedComponents['gh']) { Write-Host "[OK] GitHub CLI (gh) installed" }
Write-Host "[OK] Oh My Posh configured"
Write-Host "[OK] PSReadLine configured"
Write-Host "[OK] Config files copied"
Write-Host "[OK] Git identity configured"
Write-Host "[OK] Neovim plugins installed"
Write-Host ""
Write-Host "Backup location: $BackupDir"
Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Start a new PowerShell session"
Write-Host "2. Set FiraCode Nerd Font in Windows Terminal"
if ($SelectedComponents['gh']) { Write-Host "3. Run: gh auth login" }
Write-Host "4. Add SSH keys to .ssh folder"
Write-Host ""
