<#
.SYNOPSIS
  Aplica o estado de performance otimo para LLM no Lenovo LOQ 15IRX11 (83UX) + RTX 5050 Laptop.
.DESCRIPTION
  - Plano de energia Equilibrado (evita o teto de 35 W do Intel IPF / Dynamic Boost).
  - SmartFanMode = 3 (Performance) e Dynamic Boost = 15 W via WMI (exige Admin).
  - nvidia-smi -rgc / -rmc para liberar o boost automatico (P2).
  - Variaveis de ambiente do Ollama no escopo do usuario.
  Use -Status para so mostrar o estado atual, sem alterar nada.
#>
[CmdletBinding()]
param([switch]$Status, [switch]$Elevated)

$ErrorActionPreference = 'Stop'
$BalancedGuid = '381b4222-f694-41f0-9685-ff5bb260df2e'
$OllamaEnv = [ordered]@{
  OLLAMA_FLASH_ATTENTION   = '1'
  OLLAMA_KV_CACHE_TYPE     = 'q8_0'
  OLLAMA_CONTEXT_LENGTH    = '16384'
  OLLAMA_MAX_LOADED_MODELS = '1'
  OLLAMA_NUM_PARALLEL      = '1'
}

# A leitura WMI da Lenovo exige Admin. O ultimo estado lido como Admin fica neste arquivo.
$StateFile = Join-Path $env:TEMP 'llm-boost-state.txt'

function Test-Admin {
  ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-NvidiaSmi {
  $cmd = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $p = Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'
  if (Test-Path $p) { $p }
}

function Show-State {
  $fan = Get-CimInstance -Namespace root\WMI -ClassName LENOVO_GAMEZONE_DATA -ErrorAction SilentlyContinue
  $oth = Get-CimInstance -Namespace root\WMI -ClassName LENOVO_OTHER_METHOD -ErrorAction SilentlyContinue
  $mode = if ($fan) { (Invoke-CimMethod -InputObject $fan -MethodName GetSmartFanMode).Data } else { 'n/a' }
  $boost = if ($oth) { (Invoke-CimMethod -InputObject $oth -MethodName GetFeatureValue -Arguments @{ IDs = [uint32]0x02010300 }).Value } else { 'n/a' }
  $plan = (powercfg /getactivescheme) -replace '^.*:\s*', ''
  $out = @("SmartFanMode=$mode", "DynamicBoost=$boost", "PowerPlan=$plan")
  if (Test-Admin) { $out | Set-Content $StateFile }
  $out
}

if ($Status) {
  if (Test-Admin) { Show-State }
  elseif (Test-Path $StateFile) { Get-Content $StateFile; "(estado em cache; WMI exige Admin)" }
  else { "PowerPlan=" + ((powercfg /getactivescheme) -replace '^.*:\s*', ''); "SmartFanMode/DynamicBoost: rode llm-boost uma vez como Admin." }
  return
}

if (-not (Test-Admin)) {
  if ($Elevated) { throw 'Elevacao falhou: o processo continua sem privilegio de Administrador.' }
  $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Elevated')
  $p = Start-Process powershell.exe -Verb RunAs -ArgumentList $args -Wait -PassThru
  exit $p.ExitCode
}

# 1. Plano Equilibrado
powercfg /setactive $BalancedGuid

# 2. WMI Lenovo
$fan = Get-CimInstance -Namespace root\WMI -ClassName LENOVO_GAMEZONE_DATA
Invoke-CimMethod -InputObject $fan -MethodName SetSmartFanMode -Arguments @{ Data = [int32]3 } | Out-Null
$oth = Get-CimInstance -Namespace root\WMI -ClassName LENOVO_OTHER_METHOD
Invoke-CimMethod -InputObject $oth -MethodName SetFeatureValue -Arguments @{ IDs = [uint32]0x02010300; value = [uint32]15 } | Out-Null

# 3. Reset de clocks da GPU
$smi = Get-NvidiaSmi
if ($smi) { & $smi -rgc | Out-Null; & $smi -rmc | Out-Null } else { Write-Warning 'nvidia-smi.exe nao encontrado.' }

# 4. Ollama (escopo do usuario)
foreach ($k in $OllamaEnv.Keys) { [Environment]::SetEnvironmentVariable($k, $OllamaEnv[$k], 'User') }

Show-State
