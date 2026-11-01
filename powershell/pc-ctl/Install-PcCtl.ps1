<#
.SYNOPSIS
  Instala os scripts de controle de energia do pc-ctl em C:\ProgramData\pc-ctl com ACL restrita.
.DESCRIPTION
  - Cria o diretório C:\ProgramData\pc-ctl\ caso não exista.
  - Copia Set-PowerProfile.ps1 e Set-LenovoLlmBoost.ps1 para C:\ProgramData\pc-ctl\.
  - Configura ACLs de segurança: apenas Administradores e SYSTEM podem alterar/escrever scripts.
  - Concede permissão de escrita/modificação aos Usuários apenas no arquivo request.json.
  - Habilita os temporizadores de ativação (powercfg) na tomada e na bateria.
  - Registra a tarefa pc-ctl-power (RunLevel Highest) com Register-ScheduledTask.
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

# 5. Wake timers: habilita "Permitir temporizadores de ativação" na tomada (AC) e na bateria (DC)
$wakeTimerGuid = 'BD3B718A-0680-4D9D-8AB2-E1D2B4AC806D'
foreach ($mode in '/setacvalueindex', '/setdcvalueindex') {
  $powercfgOut = & powercfg.exe $mode SCHEME_CURRENT SUB_SLEEP $wakeTimerGuid 1 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "powercfg $mode falhou (código $LASTEXITCODE): $powercfgOut"
  }
}
$powercfgOut = & powercfg.exe /setactive SCHEME_CURRENT 2>&1
if ($LASTEXITCODE -ne 0) {
  throw "powercfg /setactive falhou (código $LASTEXITCODE): $powercfgOut"
}

# 6. Tarefa pc-ctl-power: o usuário a dispara com `schtasks /run`, sem UAC. Sem gatilho e sem argumentos livres.
$taskName = 'pc-ctl-power'
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$powerScript = Join-Path $InstallDir 'Set-PowerProfile.ps1'
$taskAction = New-ScheduledTaskAction -Execute $psExe -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$powerScript`""
$taskUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$taskPrincipal = New-ScheduledTaskPrincipal -UserId $taskUser -LogonType Interactive -RunLevel Highest
$taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
Register-ScheduledTask -TaskName $taskName -Action $taskAction -Principal $taskPrincipal -Settings $taskSettings -Description 'pc-ctl: aplica o perfil de energia pedido em request.json' -Force | Out-Null

Write-Output "pc-ctl instalado com sucesso em $InstallDir."
