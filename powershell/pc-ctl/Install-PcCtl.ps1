<#
.SYNOPSIS
  Instala os scripts de controle de energia do pc-ctl em C:\ProgramData\pc-ctl com ACL restrita.
.DESCRIPTION
  - Cria o diretório C:\ProgramData\pc-ctl\ caso não exista.
  - Copia Set-PowerProfile.ps1 e Set-LenovoLlmBoost.ps1 para C:\ProgramData\pc-ctl\.
  - Configura ACLs de segurança: apenas Administradores e SYSTEM podem alterar/escrever scripts.
  - Concede permissão de escrita/modificação aos Usuários apenas no arquivo request.json.
#>
[CmdletBinding()]
param(
  [string]$InstallDir = 'C:\ProgramData\pc-ctl'
)

$ErrorActionPreference = 'Stop'

function Test-Admin {
  ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
  throw 'Instalação do pc-ctl requer privilégios de Administrador.'
}

# 1. Criação do diretório de destino
if (-not (Test-Path $InstallDir)) {
  New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# 2. Cópia dos scripts versionados
$currentDir = $PSScriptRoot
$setPowerProfileSrc = Join-Path $currentDir 'Set-PowerProfile.ps1'
$llmBoostSrc = Join-Path (Join-Path $currentDir '..') 'Set-LenovoLlmBoost.ps1'

if (Test-Path $setPowerProfileSrc) {
  Copy-Item -Path $setPowerProfileSrc -Destination (Join-Path $InstallDir 'Set-PowerProfile.ps1') -Force
}

if (Test-Path $llmBoostSrc) {
  Copy-Item -Path $llmBoostSrc -Destination (Join-Path $InstallDir 'Set-LenovoLlmBoost.ps1') -Force
}

# 3. Criação de request.json inicial se inexistente
$requestFile = Join-Path $InstallDir 'request.json'
if (-not (Test-Path $requestFile)) {
  "{}" | Set-Content -Path $requestFile -Encoding UTF8
}

# 4. Ajuste de ACL: Scripts e diretório restritos a Admin e SYSTEM; Users com RX
# Use SIDs: os nomes de grupo mudam com o idioma do Windows (pt-BR: Administradores, Usuários).
# S-1-5-32-544 = Administradores, S-1-5-18 = SYSTEM, S-1-5-32-545 = Usuários
$icaclsOut = & icacls.exe $InstallDir /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)(F)' '*S-1-5-18:(OI)(CI)(F)' '*S-1-5-32-545:(OI)(CI)(RX)' 2>&1
if ($LASTEXITCODE -ne 0) {
  throw "icacls falhou ao restringir $InstallDir (código $LASTEXITCODE): $icaclsOut"
}

# Concede aos usuários permissão de escrita/modificação apenas no request.json
$icaclsOut = & icacls.exe $requestFile /grant '*S-1-5-32-545:(M)' 2>&1
if ($LASTEXITCODE -ne 0) {
  throw "icacls falhou ao liberar $requestFile (código $LASTEXITCODE): $icaclsOut"
}

Write-Output "pc-ctl instalado com sucesso em $InstallDir."
