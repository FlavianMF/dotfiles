<#
.SYNOPSIS
  Aplica perfis de energia e refrigeração no Windows host (Lenovo LOQ / Legion).
.DESCRIPTION
  - eco: Plano Equilibrado, SmartFanMode silencioso (1), Dynamic Boost desligado (0 W).
  - balanced: Plano Equilibrado padrão, SmartFanMode automático (2), Dynamic Boost desligado (0 W).
  - llm-boost: Reaproveita Set-LenovoLlmBoost.ps1 (Equilibrado, SmartFanMode 3, Dynamic Boost 15 W, clocks GPU, Ollama).
  - max: Plano Desempenho Máximo, SmartFanMode performance (3), Dynamic Boost 15 W.
  Lê request.json de C:\ProgramData\pc-ctl\ quando executado via tarefa agendada sem argumentos.
  Se o computador estiver na bateria, llm-boost e max são recusados.
#>
[CmdletBinding()]
param(
  [ValidateSet('eco', 'balanced', 'llm-boost', 'max')]
  [string]$Profile,

  [int]$TtlMinutes = 0,

  [string]$ConfigDir = 'C:\ProgramData\pc-ctl',

  [switch]$FromRequest
)

$ErrorActionPreference = 'Stop'
$BalancedGuid = '381b4222-f694-41f0-9685-ff5bb260df2e'
$MaxPerfGuid  = 'e1333eac-b627-4404-8a76-6b36e55112fe'

function Test-Admin {
  ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-LenovoWmi {
  param([int]$SmartFanMode, [int]$DynamicBoostWatts)
  try {
    $fan = Get-CimInstance -Namespace root\WMI -ClassName LENOVO_GAMEZONE_DATA -ErrorAction SilentlyContinue
    if ($fan) {
      Invoke-CimMethod -InputObject $fan -MethodName SetSmartFanMode -Arguments @{ Data = [int32]$SmartFanMode } | Out-Null
    }
  } catch {
    Write-Warning "Falha ao definir SmartFanMode: $_"
  }

  try {
    $oth = Get-CimInstance -Namespace root\WMI -ClassName LENOVO_OTHER_METHOD -ErrorAction SilentlyContinue
    if ($oth) {
      Invoke-CimMethod -InputObject $oth -MethodName SetFeatureValue -Arguments @{ IDs = [uint32]0x02010300; value = [uint32]$DynamicBoostWatts } | Out-Null
    }
  } catch {
    Write-Warning "Falha ao definir DynamicBoost: $_"
  }
}

# 1. Leitura de request.json caso Profile não tenha sido passado na linha de comando
$RequestFile = Join-Path $ConfigDir 'request.json'
if (-not $Profile -or $FromRequest) {
  if (Test-Path $RequestFile) {
    try {
      $req = Get-Content -Path $RequestFile -Raw | ConvertFrom-Json
      if ($req.profile) {
        $Profile = [string]$req.profile
      }
      if ($req.ttl_minutes) {
        $TtlMinutes = [int]$req.ttl_minutes
      }
      Remove-Item -Path $RequestFile -Force -ErrorAction SilentlyContinue
    } catch {
      throw "Falha ao processar request.json: $_"
    }
  } else {
    throw "Nenhum perfil especificado e request.json não encontrado em $RequestFile"
  }
}

# 2. Validação de perfil
$validProfiles = @('eco', 'balanced', 'llm-boost', 'max')
if ($Profile -notin $validProfiles) {
  throw "Perfil inválido: '$Profile'. Perfis suportados: $($validProfiles -join ', ')"
}

# 3. Verificação de bateria / tomada
Add-Type -AssemblyName System.Windows.Forms
$powerStatus = [System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus
if ($powerStatus -ne 'Online' -and ($Profile -eq 'llm-boost' -or $Profile -eq 'max')) {
  throw "Perfil '$Profile' recusado: computador operando na bateria ($powerStatus)."
}

# 4. Validação de TTL
if ($Profile -in @('llm-boost', 'max')) {
  if ($TtlMinutes -le 0) {
    $TtlMinutes = 120 # Padrão: 2 horas
  }
  if ($TtlMinutes -gt 240) {
    throw "TTL excede o limite máximo permitido de 240 minutos (4 horas): $TtlMinutes"
  }
} else {
  $TtlMinutes = 0
}

# 5. Aplicação do Perfil
switch ($Profile) {
  'eco' {
    powercfg /setactive $BalancedGuid
    Set-LenovoWmi -SmartFanMode 1 -DynamicBoostWatts 0
  }
  'balanced' {
    powercfg /setactive $BalancedGuid
    Set-LenovoWmi -SmartFanMode 2 -DynamicBoostWatts 0
  }
  'llm-boost' {
    $llmBoostCandidates = @(
      (Join-Path $ConfigDir 'Set-LenovoLlmBoost.ps1'),
      (Join-Path $PSScriptRoot 'Set-LenovoLlmBoost.ps1'),
      (Join-Path (Join-Path $PSScriptRoot '..') 'Set-LenovoLlmBoost.ps1')
    )
    $scriptFound = $false
    foreach ($cand in $llmBoostCandidates) {
      if (Test-Path $cand) {
        & $cand -Elevated
        $scriptFound = $true
        break
      }
    }
    if (-not $scriptFound) {
      powercfg /setactive $BalancedGuid
      Set-LenovoWmi -SmartFanMode 3 -DynamicBoostWatts 15
    }
  }
  'max' {
    powercfg /setactive $MaxPerfGuid
    Set-LenovoWmi -SmartFanMode 3 -DynamicBoostWatts 15
  }
}

# 6. Agendamento de reversão para balanced se houver TTL
if ($TtlMinutes -gt 0) {
  $revertTime = (Get-Date).AddMinutes($TtlMinutes)
  $timeStr = $revertTime.ToString('HH:mm')
  $dateStr = $revertTime.ToString('yyyy/MM/dd')
  $revertScript = Join-Path $ConfigDir 'Set-PowerProfile.ps1'
  $revertAction = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$revertScript`" -Profile balanced"

  schtasks.exe /create /tn "pc-ctl-power-revert" /tr $revertAction /sc once /st $timeStr /sd $dateStr /ru SYSTEM /rl HIGHEST /f | Out-Null
} else {
  schtasks.exe /delete /tn "pc-ctl-power-revert" /f 2>$null | Out-Null
}

# 7. Gravação do estado atual em state.json
if (-not (Test-Path $ConfigDir)) {
  New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}

$StateFile = Join-Path $ConfigDir 'state.json'
$expiresAt = if ($TtlMinutes -gt 0) {
  (Get-Date).AddMinutes($TtlMinutes).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
} else {
  $null
}

$stateObj = [ordered]@{
  active_profile = $Profile
  applied_at     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  ttl_minutes    = $TtlMinutes
  expires_at     = $expiresAt
}

$stateObj | ConvertTo-Json | Set-Content -Path $StateFile -Encoding UTF8
Write-Output "Perfil '$Profile' aplicado com sucesso. (TTL: $TtlMinutes min)"
