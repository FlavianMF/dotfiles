#Requires -Version 5.1

param(
    [string]$Branch = "master",
    [string]$DownloadPath = "$env:USERPROFILE\Downloads\dotfiles",
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"

function Write-Info { Write-Host "[INFO] $args" -ForegroundColor Green }
function Write-Warn { Write-Host "[WARN] $args" -ForegroundColor Yellow }
function Write-Error-Custom { Write-Host "[ERROR] $args" -ForegroundColor Red }

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Dotfiles Setup Installer" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Info "Downloading dotfiles from GitHub (branch: $Branch)..."
$RepoUrl = "https://github.com/FlavianMF/dotfiles/archive/refs/heads/$Branch.zip"
$ZipPath = Join-Path $env:TEMP "dotfiles-$Branch.zip"

try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $RepoUrl -OutFile $ZipPath -UseBasicParsing
    Write-Info "Download complete"
}
catch {
    Write-Error-Custom "Failed to download repo: $_"
    exit 1
}

Write-Info "Extracting to $DownloadPath..."
$ExtractPath = Split-Path $DownloadPath
if (-not (Test-Path $ExtractPath)) {
    New-Item -ItemType Directory -Path $ExtractPath -Force | Out-Null
}

if (Test-Path $DownloadPath) {
    Remove-Item -Path $DownloadPath -Recurse -Force -ErrorAction SilentlyContinue
}

Expand-Archive -Path $ZipPath -DestinationPath $ExtractPath -Force
$ExtractedDir = Join-Path $ExtractPath "dotfiles-$Branch"
if (Test-Path $ExtractedDir) {
    Move-Item -Path $ExtractedDir -Destination $DownloadPath -Force
    Write-Info "Extraction complete"
}

Remove-Item -Path $ZipPath -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Info "Running install.ps1..."
Write-Host ""

$InstallScript = Join-Path $DownloadPath "install.ps1"
if (-not (Test-Path $InstallScript)) {
    Write-Error-Custom "install.ps1 not found at $InstallScript"
    exit 1
}

$args_list = @()
if ($NonInteractive) {
    $args_list += "-NonInteractive"
}

& powershell -NoProfile -ExecutionPolicy Bypass -File $InstallScript @args_list

if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "install.ps1 exited with code $LASTEXITCODE"
    exit 1
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Setup Complete!" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Info "Dotfiles extracted to: $DownloadPath"
Write-Host ""
Write-Host "Extracted files are in:"
Write-Host "  $DownloadPath"
Write-Host ""

if (-not $NonInteractive) {
    $cleanup = Read-Host "Delete extracted files? (y/n)"
    if ($cleanup -eq 'y' -or $cleanup -eq 'Y') {
        Remove-Item -Path $DownloadPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Info "Cleaned up $DownloadPath"
    }
    else {
        Write-Host "Keeping files in $DownloadPath for review"
    }
}

Write-Host ""
