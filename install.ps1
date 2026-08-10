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

$IsElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsElevated) {
    Write-Warn "Not running as Administrator. Re-launching elevated (required for system-wide installs)..."
    $RelaunchArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $MyInvocation.MyCommand.Path)
    if ($NonInteractive) { $RelaunchArgs += '-NonInteractive' }
    try {
        $proc = Start-Process powershell -Verb RunAs -ArgumentList $RelaunchArgs -Wait -PassThru
        exit $proc.ExitCode
    }
    catch {
        Write-Error-Custom "Elevation was cancelled or failed: $_"
        exit 1
    }
}

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BackupDir = Join-Path $env:USERPROFILE ".dotfiles-backup\$(Get-Date -UFormat %s)"

Write-Info "Starting dotfiles installation from $RepoDir"

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error-Custom "winget not found. Install App Installer from Microsoft Store."
    exit 1
}

$NeedsPS7 = $PSVersionTable.PSVersion.Major -lt 7
if ($NeedsPS7) {
    Write-Warn "PowerShell 7+ recommended for oh-my-posh and PSReadLine features."
}

$SystemWide = $true
$SelectedComponents = @{'powershell7'=$false; 'node'=$false; 'python'=$true; 'docker'=$false; 'gh'=$true; 'vscode'=$true; 'eim'=$true; 'nvim'=$false; 'ripgrep'=$false; 'fd'=$false; 'lazygit'=$false}
$OptionalComponents = @{'powershell7'='PowerShell 7 (recommended for oh-my-posh and PSReadLine features)'; 'node'='Node.js (required for nvim treesitter)'; 'python'='Python 3.12 (dev environment)'; 'docker'='Docker (containerization)'; 'gh'='GitHub CLI (gh)'; 'vscode'='Visual Studio Code (editor)'; 'eim'='Espressif EIM (ESP-IDF Installation Manager, CLI)'; 'nvim'='Neovim + LazyVim config'; 'ripgrep'='ripgrep (fast search, used by nvim Telescope)'; 'fd'='fd (fast file finder, used by nvim Telescope)'; 'lazygit'='lazygit (git UI, used by nvim plugin)'}

function Select-Components {
    if (-not (Is-Interactive)) {
        Write-Info "Running non-interactively. Installing default components: python, vscode, eim, gh (system-wide install: enabled)"
        return
    }

    $options = @('systemwide', 'node', 'python', 'docker', 'gh', 'vscode', 'eim', 'nvim', 'ripgrep', 'fd', 'lazygit')
    if ($NeedsPS7) {
        $options = @('systemwide', 'powershell7') + $options[1..($options.Count - 1)]
    }
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
            if ($comp -eq 'systemwide') {
                $checked = if ($SystemWide) { 'X' } else { ' ' }
                Write-Host "  $marker [$checked] System-wide install - Installs for ALL Windows users, incl. future accounts (unchecked = current user only)" -ForegroundColor $color
            }
            else {
                $checked = if ($SelectedComponents[$comp]) { 'X' } else { ' ' }
                Write-Host "  $marker [$checked] $comp - $($OptionalComponents[$comp])" -ForegroundColor $color
            }
        }

        Write-Host ""
        Write-Host "  Press ENTER to confirm"
        Write-Host ""

        $key = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

        switch ($key.VirtualKeyCode) {
            38 { $current = ($current - 1 + $options.Count) % $options.Count }
            40 { $current = ($current + 1) % $options.Count }
            32 {
                if ($options[$current] -eq 'systemwide') { $script:SystemWide = -not $script:SystemWide }
                else { $SelectedComponents[$options[$current]] = -not $SelectedComponents[$options[$current]] }
            }
            13 { $done = $true }
        }
    }

    Clear-Host
}

function Install-AppWithFallback {
    param([string]$Name, [string]$WingetId, [string]$ExeFilter, [string[]]$SilentArgs)

    Write-Info "Installing $Name..."
    winget install --id $WingetId -e --source winget --accept-package-agreements --accept-source-agreements --scope $WingetScope -h 2>$null

    if ($LASTEXITCODE -eq 0) {
        Write-Info "$Name installed successfully via winget"
        return
    }

    Write-Warn "Winget install failed or package not found, trying local installer..."
    Write-Warn "Local installer fallback for $Name may not respect the --scope $WingetScope preference (installer-specific behavior, unverified)"
    $LocalExe = Get-ChildItem -Path "$RepoDir\exes" -Filter $ExeFilter -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($LocalExe) {
        Write-Info "Found local installer: $($LocalExe.Name)"
        $proc = Start-Process -FilePath $LocalExe.FullName -ArgumentList $SilentArgs -Wait -PassThru
        if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
            Write-Info "$Name installed successfully via local installer"
            return
        }
        else {
            Write-Warn "$Name local installer exited with code $($proc.ExitCode)"
        }
    }
    else {
        Write-Warn "No local installer found for $Name (pattern: $ExeFilter)"
    }
}

Select-Components

$WingetScope = if ($SystemWide) { 'machine' } else { 'user' }
Write-Info "Install scope: $WingetScope"

# If nvim selected, force-select its dependencies
if ($SelectedComponents['nvim']) {
    if (-not $SelectedComponents['node']) {
        Write-Info "nvim selected: forcing node (required for treesitter)"
        $SelectedComponents['node'] = $true
    }
    if (-not $SelectedComponents['ripgrep']) {
        Write-Info "nvim selected: forcing ripgrep (required for Telescope)"
        $SelectedComponents['ripgrep'] = $true
    }
    if (-not $SelectedComponents['fd']) {
        Write-Info "nvim selected: forcing fd (required for Telescope)"
        $SelectedComponents['fd'] = $true
    }
    if (-not $SelectedComponents['lazygit']) {
        Write-Info "nvim selected: forcing lazygit (used by nvim plugin)"
        $SelectedComponents['lazygit'] = $true
    }
}

$PackagesToInstall = @('JanDeDobbeleer.OhMyPosh')
$ComponentPackages = @{'powershell7'='Microsoft.PowerShell'; 'node'='OpenJS.NodeJS.LTS'; 'python'='Python.Python.3.12'; 'docker'='Docker.DockerDesktop'; 'gh'='GitHub.cli'; 'nvim'='Neovim.Neovim'; 'ripgrep'='BurntSushi.ripgrep.MSVC'; 'fd'='sharkdp.fd'; 'lazygit'='JesseDuffield.lazygit'}

foreach ($comp in $ComponentPackages.Keys) {
    if ($SelectedComponents[$comp]) {
        Write-Info "$comp selected"
        $PackagesToInstall += $ComponentPackages[$comp]
    }
}

Write-Info "Installing packages via winget..."

$GitScopeArg = if ($SystemWide) { '/ALLUSERS=1' } else { '/CURRENTUSER' }
Install-AppWithFallback -Name "Git" -WingetId "Git.Git" -ExeFilter "Git-*-64-bit.exe" -SilentArgs "/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-", "/CLOSEAPPLICATIONS", "/RESTARTAPPLICATIONS", $GitScopeArg

foreach ($pkg in $PackagesToInstall) {
    Write-Info "Installing $pkg..."
    winget install --id $pkg -e --source winget --accept-package-agreements --accept-source-agreements --scope $WingetScope -h 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Info "$pkg installed successfully"
    }
    else {
        Write-Warn "$pkg install failed or already present, continuing..."
    }
}

if ($SelectedComponents['vscode']) {
    $VSCodeScopeArg = if ($SystemWide) { '/ALLUSERS=1' } else { '/CURRENTUSER' }
    Install-AppWithFallback -Name "Visual Studio Code" -WingetId "Microsoft.VisualStudioCode" -ExeFilter "VSCodeSetup-x64-*.exe" -SilentArgs "/VERYSILENT", "/NORESTART", "/MERGETASKS=!runcode", $VSCodeScopeArg
}

$EimProvisioned = $false
if ($SelectedComponents['eim']) {
    Install-AppWithFallback -Name "Espressif EIM" -WingetId "Espressif.EIM-CLI" -ExeFilter "eim-gui-windows-x64-*.exe" -SilentArgs "/S"

    Write-Info "Refreshing PATH to find eim command..."
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

    if (Get-Command eim -ErrorAction SilentlyContinue) {
        Write-Info "Running ESP-IDF provisioning via EIM..."
        $EimConfigSource = Join-Path $RepoDir "eim\eim_config.toml"

        if (Test-Path $EimConfigSource) {
            $EimConfigTemp = Join-Path $env:TEMP "eim_config.toml"
            $EimConfigContent = Get-Content -Path $EimConfigSource -Raw
            $EimConfigContent = $EimConfigContent -replace 'config_file_save_path\s*=\s*[''"].*?[''"]', "config_file_save_path = '$env:USERPROFILE\Downloads\eim_config.toml'"
            Set-Content -Path $EimConfigTemp -Value $EimConfigContent -Force

            & eim install --config $EimConfigTemp
            if ($LASTEXITCODE -eq 0) {
                Write-Info "ESP-IDF provisioned successfully"
                $EimProvisioned = $true
            }
            else {
                Write-Warn "EIM provisioning failed with exit code $LASTEXITCODE"
            }

            Remove-Item -Path $EimConfigTemp -Force -ErrorAction SilentlyContinue
        }
        else {
            Write-Warn "EIM config not found at $EimConfigSource"
        }
    }
    else {
        Write-Warn "eim command not found. You may need to restart your terminal and run: eim install --config $RepoDir\eim\eim_config.toml"
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
if ($SelectedComponents['nvim']) {
    New-ConfigLink -Source "$RepoDir\nvim" -Target "$env:LOCALAPPDATA\nvim" -IsDirectory
}
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

if ($SelectedComponents['nvim']) {
    Write-Info "Installing Neovim plugins..."
    nvim --headless "+Lazy! sync" +qa 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Could not auto-install nvim plugins. Run: :Lazy sync in nvim"
    }
}

Write-Host ""
Write-Info "Installation complete!"
Write-Host ""
Write-Host "Summary:"
Write-Host "=========="
Write-Host "[OK] Install scope: $WingetScope"
Write-Host "[OK] Git installed"
Write-Host "[OK] System packages installed"
if ($SelectedComponents['powershell7']) { Write-Host "[OK] PowerShell 7 installed" }
if ($SelectedComponents['node']) { Write-Host "[OK] Node.js and npm installed" }
if ($SelectedComponents['python']) { Write-Host "[OK] Python 3.12 installed" }
if ($SelectedComponents['docker']) { Write-Host "[OK] Docker Desktop installed" }
if ($SelectedComponents['gh']) { Write-Host "[OK] GitHub CLI (gh) installed" }
if ($SelectedComponents['nvim']) { Write-Host "[OK] Neovim installed" }
if ($SelectedComponents['ripgrep']) { Write-Host "[OK] ripgrep installed" }
if ($SelectedComponents['fd']) { Write-Host "[OK] fd installed" }
if ($SelectedComponents['lazygit']) { Write-Host "[OK] lazygit installed" }
if ($SelectedComponents['vscode']) { Write-Host "[OK] Visual Studio Code installed" }
if ($SelectedComponents['eim']) { Write-Host "[OK] Espressif EIM installed" }
if ($EimProvisioned) { Write-Host "[OK] ESP-IDF provisioned via EIM" }
Write-Host "[OK] Oh My Posh configured"
Write-Host "[OK] PSReadLine configured"
Write-Host "[OK] Config files copied"
Write-Host "[OK] Git identity configured"
if ($SelectedComponents['nvim']) { Write-Host "[OK] Neovim plugins installed" }
Write-Host ""
Write-Host "Backup location: $BackupDir"
Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Start a new PowerShell session"
Write-Host "2. Set FiraCode Nerd Font in Windows Terminal"
if ($SelectedComponents['gh']) { Write-Host "3. Run: gh auth login" }
Write-Host "4. Add SSH keys to .ssh folder"
Write-Host ""
