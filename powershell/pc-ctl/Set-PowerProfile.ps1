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

$RequestFile = Join-Path $ConfigDir 'request.json'
$StateFile = Join-Path $ConfigDir 'state.json'
$validProfiles = @('eco', 'balanced', 'llm-boost', 'max')
$script:Recorded = $false
$script:RequestedProfile = [string]$PowerProfile

# Grava o resultado real em state.json (o "pc-ctl power-mode status" lê este arquivo).
# Preserva o perfil ativo anterior; JavaScriptSerializer evita converter datas ISO em DateTime.
function Save-State {
  param([hashtable]$Fields)
  $state = [ordered]@{ active_profile = $null; applied_at = $null; ttl_minutes = 0; expires_at = $null }
  if (Test-Path $StateFile) {
    try {
      Add-Type -AssemblyName System.Web.Extensions
      $old = (New-Object System.Web.Script.Serialization.JavaScriptSerializer).DeserializeObject((Get-Content -Path $StateFile -Raw))
      foreach ($k in @($state.Keys)) {
        if ($old.ContainsKey($k) -and $null -ne $old[$k]) { $state[$k] = $old[$k] }
      }
    } catch {
      Write-Warning "state.json ilegível, será recriado: $_"
    }
  }
  foreach ($k in $Fields.Keys) { $state[$k] = $Fields[$k] }
  $state['last_at'] = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
  }
  $state | ConvertTo-Json | Set-Content -Path $StateFile -Encoding UTF8
}

# Recusa o pedido: grava refused com o motivo e aborta.
function Stop-Refused {
  param([string]$Reason, [string]$Message)
  Save-State @{ last_result = 'refused'; last_reason = $Reason; last_profile = $script:RequestedProfile }
  $script:Recorded = $true
  throw $Message
}

try {
  # 1. Leitura de request.json caso o perfil não tenha sido passado na linha de comando
  if (-not $PowerProfile -or $FromRequest) {
    if (-not (Test-Path $RequestFile)) {
      throw "Nenhum perfil especificado e request.json não encontrado em $RequestFile"
    }
    $req = Get-Content -Path $RequestFile -Raw | ConvertFrom-Json
    # Sobrescreva em vez de apagar: o usuário só tem RX na pasta e precisa reescrever o arquivo no próximo pedido.
    '{}' | Set-Content -Path $RequestFile -Encoding UTF8
    $requestedName = [string]$req.profile
    $script:RequestedProfile = $requestedName
    if ($requestedName -notin $validProfiles) {
      Stop-Refused 'invalid_profile' "Perfil inválido no request.json: '$requestedName'. Perfis suportados: $($validProfiles -join ', ')"
    }
    $PowerProfile = $requestedName
    if ($req.ttl_minutes) {
      $TtlMinutes = [int]$req.ttl_minutes
    }
  }

  # 2. Validação de perfil
  $script:RequestedProfile = [string]$PowerProfile
  if ($PowerProfile -notin $validProfiles) {
    Stop-Refused 'invalid_profile' "Perfil inválido: '$PowerProfile'. Perfis suportados: $($validProfiles -join ', ')"
  }

  # 3. Verificação de bateria / tomada
  Add-Type -AssemblyName System.Windows.Forms
  $powerStatus = [string][System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus
  if ($powerStatus -ne 'Online' -and ($PowerProfile -eq 'llm-boost' -or $PowerProfile -eq 'max')) {
    $refuseReason = if ($powerStatus -eq 'Unknown') { 'power_unknown' } else { 'on_battery' }
    Stop-Refused $refuseReason "Perfil '$PowerProfile' recusado: computador operando na bateria ou com estado desconhecido ($powerStatus)."
  }

  # 4. Validação de TTL
  if ($PowerProfile -in @('llm-boost', 'max')) {
    if ($TtlMinutes -le 0) {
      $TtlMinutes = 120 # Padrão: 2 horas
    }
    if ($TtlMinutes -gt 240) {
      Stop-Refused 'ttl_exceeded' "TTL excede o limite máximo permitido de 240 minutos (4 horas): $TtlMinutes"
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
  $expiresAt = if ($TtlMinutes -gt 0) {
    (Get-Date).AddMinutes($TtlMinutes).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  } else {
    $null
  }
  Save-State @{
    active_profile = $PowerProfile
    applied_at     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    ttl_minutes    = $TtlMinutes
    expires_at     = $expiresAt
    last_result    = 'applied'
    last_reason    = 'ok'
    last_profile   = $PowerProfile
  }
  $script:Recorded = $true
  Write-Output "Perfil '$PowerProfile' aplicado com sucesso. (TTL: $TtlMinutes min)"
} catch {
  if (-not $script:Recorded) {
    Save-State @{ last_result = 'failed'; last_reason = [string]$_.Exception.Message; last_profile = $script:RequestedProfile }
  }
  throw
}
