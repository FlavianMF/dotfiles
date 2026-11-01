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
  [Alias('Profile')]
  [ValidateSet('eco', 'balanced', 'llm-boost', 'max')]
  [string]$PowerProfile,

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
if (-not $PowerProfile -or $FromRequest) {
  if (Test-Path $RequestFile) {
    try {
      $req = Get-Content -Path $RequestFile -Raw | ConvertFrom-Json
      if ($req.profile) {
        $PowerProfile = [string]$req.profile
      }
      if ($req.ttl_minutes) {
        $TtlMinutes = [int]$req.ttl_minutes
      }
      # Sobrescreva em vez de apagar: o usuário só tem RX na pasta e precisa reescrever o arquivo no próximo pedido.
      '{}' | Set-Content -Path $RequestFile -Encoding UTF8
    } catch {
      throw "Falha ao processar request.json: $_"
    }
  } else {
    throw "Nenhum perfil especificado e request.json não encontrado em $RequestFile"
  }
}

# 2. Validação de perfil
$validProfiles = @('eco', 'balanced', 'llm-boost', 'max')
if ($PowerProfile -notin $validProfiles) {
  throw "Perfil inválido: '$PowerProfile'. Perfis suportados: $($validProfiles -join ', ')"
}

# 3. Verificação de bateria / tomada
Add-Type -AssemblyName System.Windows.Forms
$powerStatus = [System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus
if ($powerStatus -ne 'Online' -and ($PowerProfile -eq 'llm-boost' -or $PowerProfile -eq 'max')) {
  throw "Perfil '$PowerProfile' recusado: computador operando na bateria ($powerStatus)."
}

# 4. Validação de TTL
if ($PowerProfile -in @('llm-boost', 'max')) {
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
switch ($PowerProfile) {
  'eco' {
    powercfg /setactive $BalancedGuid
    Set-LenovoWmi -SmartFanMode 1 -DynamicBoostWatts 0
  }
  'balanced' {
    powercfg /setactive $BalancedGuid
    Set-LenovoWmi -SmartFanMode 2 -DynamicBoostWatts 0
  }
  'llm-boost' {
    # Execute só a cópia protegida em ConfigDir (ACL: só Admin e SYSTEM escrevem). Nunca procure fora dela.
    $llmBoostScript = Join-Path $ConfigDir 'Set-LenovoLlmBoost.ps1'
    if (-not (Test-Path $llmBoostScript)) {
      throw "Set-LenovoLlmBoost.ps1 não encontrado em $ConfigDir. Rode 'pc-ctl wake-setup' para reinstalar."
    }
    & $llmBoostScript -Elevated
  }
  'max' {
    powercfg /setactive $MaxPerfGuid
    Set-LenovoWmi -SmartFanMode 3 -DynamicBoostWatts 15
  }
}

# 6. Agendamento de reversão para balanced se houver TTL
# Use Register-ScheduledTask: o formato de data do schtasks /sd depende da localidade (pt-BR: dd/MM/yyyy).
$revertTaskName = 'pc-ctl-power-revert'
if ($TtlMinutes -gt 0) {
  $revertTime = (Get-Date).AddMinutes($TtlMinutes)
  $revertScript = Join-Path $ConfigDir 'Set-PowerProfile.ps1'
  $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $systemAccount = ([Security.Principal.SecurityIdentifier]'S-1-5-18').Translate([Security.Principal.NTAccount]).Value

  $revertAction = New-ScheduledTaskAction -Execute $psExe -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$revertScript`" -PowerProfile balanced"
  $revertTrigger = New-ScheduledTaskTrigger -Once -At $revertTime
  $revertPrincipal = New-ScheduledTaskPrincipal -UserId $systemAccount -LogonType ServiceAccount -RunLevel Highest
  $revertSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
  Register-ScheduledTask -TaskName $revertTaskName -Action $revertAction -Trigger $revertTrigger -Principal $revertPrincipal -Settings $revertSettings -Force | Out-Null
} else {
  Unregister-ScheduledTask -TaskName $revertTaskName -Confirm:$false -ErrorAction SilentlyContinue
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
  active_profile = $PowerProfile
  applied_at     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  ttl_minutes    = $TtlMinutes
  expires_at     = $expiresAt
}

$stateObj | ConvertTo-Json | Set-Content -Path $StateFile -Encoding UTF8
Write-Output "Perfil '$PowerProfile' aplicado com sucesso. (TTL: $TtlMinutes min)"
