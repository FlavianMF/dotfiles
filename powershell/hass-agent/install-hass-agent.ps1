<#
.SYNOPSIS
    Instala e provisiona o HASS.Agent e o Satellite Service no Windows 11 para integracao com Home Assistant.

.DESCRIPTION
    Este script automatiza o provisionamento do HASS.Agent (v2) via winget ou GitHub Releases,
    garante a inicializacao do servico de satelite (Satellite Service) quando instalado,
    grava as configuracoes de conexao MQTT no HASS.Agent (appsettings.json e servicemqttsettings.json),
    registra os sensores padrao do sistema (bateria, carga da CPU) em sensors.json,
    e importa o catalogo declarativo de comandos de commands.json para o formato compativel
    com o HASS.Agent (commands.json).

.PARAMETER MqttBroker
    Endereco IP ou host Tailscale do broker MQTT (ex: 100.x.y.z). Pode ser definido via variavel de ambiente MQTT_BROKER.

.PARAMETER MqttPort
    Porta do broker MQTT (padrao: 1883). Pode ser definida via variavel de ambiente MQTT_PORT.

.PARAMETER MqttUser
    Usuario de autenticacao do MQTT (padrao: hass). Pode ser definido via variavel de ambiente MQTT_USER.

.PARAMETER MqttPassword
    Senha de autenticacao do MQTT. Pode ser definida via variavel de ambiente MQTT_PASSWORD.

.PARAMETER RegisterCommands
    Habilita a importacao do catalogo de commands.json (ativo por padrao caso o arquivo exista).

.PARAMETER SkipCommands
    Se informado, pula a importacao e conversao do catalogo de comandos.

.PARAMETER SkipSensors
    Se informado, pula o cadastro dos sensores padrao (bateria e carga da CPU).

.PARAMETER WriteServiceMqtt
    Grava tambem servicemqttsettings.json nas pastas do Satellite Service. Desligado por padrao,
    pois o nome e o formato desse arquivo nao foram confirmados na documentacao oficial.

.PARAMETER DryRun
    Se informado, simula as acoes do script sem alterar o sistema, criar arquivos ou iniciar servicos.

.EXAMPLE
    .\install-hass-agent.ps1 -MqttBroker "100.80.20.10" -MqttUser "hass" -MqttPassword "sua_senha"
    
.EXAMPLE
    $env:MQTT_BROKER = "100.80.20.10"
    $env:MQTT_PASSWORD = "sua_senha"
    .\install-hass-agent.ps1 -DryRun
#>

[CmdletBinding()]
param(
    [string]$MqttBroker = $env:MQTT_BROKER,
    [int]$MqttPort = $(if ($env:MQTT_PORT) { [int]$env:MQTT_PORT } else { 1883 }),
    [string]$MqttUser = $(if ($env:MQTT_USER) { $env:MQTT_USER } else { "hass" }),
    [string]$MqttPassword = $env:MQTT_PASSWORD,
    [switch]$RegisterCommands,
    [switch]$SkipCommands,
    [switch]$SkipSensors,
    [switch]$WriteServiceMqtt,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Test-AdminPrivileges {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DeterministicGuid([string]$seed) {
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes("hassagent-$seed")
    $hash = $md5.ComputeHash($bytes)
    return ([System.Guid]::new($hash)).ToString()
}

function Backup-ConfigFile([string]$path, [switch]$IsDryRun) {
    if (Test-Path $path) {
        $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
        $backupFile = "$path.bak.$timestamp"
        if ($IsDryRun) {
            Write-Host "[DRYRUN] Faria backup de $path para $backupFile" -ForegroundColor Gray
        } else {
            Copy-Item -Path $path -Destination $backupFile -Force
            Write-Host "[OK] Backup criado: $backupFile" -ForegroundColor Green
        }
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Provisionamento do HASS.Agent (Windows 11 Remote Control)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

if (-not (Test-AdminPrivileges)) {
    Write-Warning "Este script necessita de privilegios administrativos para instalar servicos de sistema."
    Write-Warning "Por favor, execute este script em um terminal PowerShell como Administrador."
    exit 1
}

# 1. Verificacao de instalacao existente
$appDataDir = if ($env:APPDATA) { $env:APPDATA } else { [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData) }
$localAppDataDir = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData) }
$agentExeCandidates = @(
    (Join-Path $localAppDataDir "HASS.Agent\Client\HASS.Agent.exe"),
    (Join-Path $appDataDir "LAB02 Research\HASS.Agent\HASS.Agent.exe")
)
$defaultAppExe = $agentExeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $defaultAppExe) { $defaultAppExe = $agentExeCandidates[0] }
$appInstalled = (Get-Command "HASS.Agent.exe" -ErrorAction SilentlyContinue) -or (Test-Path $defaultAppExe)

if ($appInstalled) {
    Write-Host "[OK] HASS.Agent ja detectado no sistema." -ForegroundColor Green
} else {
    Write-Host "[*] Instalando HASS.Agent..." -ForegroundColor Yellow

    if ($DryRun) {
        Write-Host "[DRYRUN] Simulando instalacao via winget ou download direto." -ForegroundColor Gray
    } else {
        $hasWinget = Get-Command "winget.exe" -ErrorAction SilentlyContinue
        $installedSuccessfully = $false

        if ($hasWinget) {
            Write-Host "[*] Tentando instalacao via Windows Package Manager (winget)..." -ForegroundColor Yellow
            try {
                $wingetResult = winget install --id "LAB02Research.HASS.Agent" -e --silent --accept-source-agreements --accept-package-agreements 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[OK] HASS.Agent instalado com sucesso via winget." -ForegroundColor Green
                    $installedSuccessfully = $true
                }
            } catch {
                Write-Warning "Falha ao instalar via winget. Tentando instalador direto do GitHub Releases..."
            }
        }

        if (-not $installedSuccessfully) {
            Write-Host "[*] Baixando instalador oficial do GitHub Releases (LAB02-Research/HASS.Agent)..." -ForegroundColor Yellow
            $tempInstaller = "$env:TEMP\HASS.Agent.Installer.exe"
            $latestUrl = "https://github.com/LAB02-Research/HASS.Agent/releases/latest/download/HASS.Agent.Installer.exe"
            
            Invoke-WebRequest -Uri $latestUrl -OutFile $tempInstaller -UseBasicParsing
            Write-Host "[*] Executando instalacao silenciosa..." -ForegroundColor Yellow
            Start-Process -FilePath $tempInstaller -ArgumentList "/VERYSILENT /NORESTART" -Wait
            Remove-Item -Path $tempInstaller -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] Instalacao do executavel concluida." -ForegroundColor Green
        }
    }
}

# 2. Verificacao e Habilitacao do Satellite Service
Write-Host "`n[*] Verificando HASS.Agent Satellite Service..." -ForegroundColor Yellow
$service = Get-Service -Name "HASS.Agent.SatelliteService" -ErrorAction SilentlyContinue

if ($service) {
    Write-Host "[OK] Satellite Service instalado. Status: $($service.Status)" -ForegroundColor Green
    if ($service.Status -ne "Running" -and -not $DryRun) {
        Write-Host "[*] Iniciando o servico..." -ForegroundColor Yellow
        Start-Service -Name "HASS.Agent.SatelliteService"
        Set-Service -Name "HASS.Agent.SatelliteService" -StartupType Automatic
    }
} else {
    Write-Warning "Satellite Service nao encontrado automaticamente."
    Write-Host "Recomenda-se abrir a interface do HASS.Agent uma vez e habilitar o Satellite Service nas configuracoes se necessario." -ForegroundColor Gray
}

# 2b. Fecha o HASS.Agent antes de gravar, pois o app regrava a configuracao ao sair
$script:AgentWasRunning = $false
$script:AgentExePath = $null
$script:AgentRestarted = $false

function Start-HassAgentIfNeeded {
    if ($script:AgentRestarted -or -not $script:AgentWasRunning) { return }
    $script:AgentRestarted = $true
    $exe = if ($script:AgentExePath -and (Test-Path $script:AgentExePath)) { $script:AgentExePath } else { $defaultAppExe }
    if ($DryRun) {
        Write-Host "[DRYRUN] Reabriria o HASS.Agent: $exe" -ForegroundColor Gray
    } elseif (Test-Path $exe) {
        Write-Host "[*] Reabrindo o HASS.Agent..." -ForegroundColor Yellow
        Start-Process -FilePath $exe
    } else {
        Write-Warning "HASS.Agent.exe nao encontrado. Abra o app manualmente."
    }
}

# Reabre o app mesmo se o script falhar depois do fechamento
trap { Start-HassAgentIfNeeded; break }

$willWriteConfig = [bool]$MqttBroker -or (-not $SkipSensors) -or (-not $SkipCommands)
$runningAgent = Get-Process -Name "HASS.Agent" -ErrorAction SilentlyContinue
if ($willWriteConfig -and $runningAgent) {
    $script:AgentWasRunning = $true
    $script:AgentExePath = ($runningAgent | Select-Object -First 1).Path
    if ($DryRun) {
        Write-Host "[DRYRUN] Fecharia o HASS.Agent antes de gravar a configuracao." -ForegroundColor Gray
    } else {
        Write-Host "[*] Fechando o HASS.Agent para gravar a configuracao..." -ForegroundColor Yellow
        $runningAgent | Stop-Process -Force
        $runningAgent | Wait-Process -Timeout 15 -ErrorAction SilentlyContinue
    }
}

# 3. Diretorios de configuracao do HASS.Agent
# A pasta config fica ao lado do HASS.Agent.exe (ClickOnce em Local) ou em Roaming (instalacao antiga)
$configCandidates = @()
if ($script:AgentExePath) { $configCandidates += Join-Path (Split-Path $script:AgentExePath -Parent) "config" }
if ($defaultAppExe) { $configCandidates += Join-Path (Split-Path $defaultAppExe -Parent) "config" }
$configCandidates += Join-Path $appDataDir "LAB02 Research\HASS.Agent\config"
$userConfigDir = $configCandidates | Where-Object { Test-Path (Join-Path $_ "appsettings.json") } | Select-Object -First 1
if (-not $userConfigDir) { $userConfigDir = $configCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1 }
if (-not $userConfigDir) {
    Write-Warning "Pasta de configuracao do HASS.Agent nao encontrada. Abra o app uma vez e rode o script de novo."
    Start-HassAgentIfNeeded
    exit 1
}
Write-Host "[*] Pasta de configuracao do HASS.Agent: $userConfigDir" -ForegroundColor Cyan

if (-not (Test-Path $userConfigDir)) {
    if ($DryRun) {
        Write-Host "[DRYRUN] Criaria diretorio de configuracao: $userConfigDir" -ForegroundColor Gray
    } else {
        New-Item -ItemType Directory -Path $userConfigDir -Force | Out-Null
    }
}

# Diretorios adicionais para sincronizacao do Satellite Service (se presente)
$serviceConfigDirs = @()
$progFilesX86 = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFilesX86)
$progFiles = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)

if ($progFilesX86) {
    $p86 = Join-Path $progFilesX86 "LAB02 Research\HASS.Agent Satellite Service\config"
    if (Test-Path (Split-Path $p86 -Parent)) { $serviceConfigDirs += $p86 }
}
if ($progFiles) {
    $p64 = Join-Path $progFiles "LAB02 Research\HASS.Agent Satellite Service\config"
    if (Test-Path (Split-Path $p64 -Parent)) { $serviceConfigDirs += $p64 }
}

# 4. Gravacao da Configuracao MQTT (appsettings.json)
$mqttWritten = $false
$appSettingsFile = Join-Path $userConfigDir "appsettings.json"

if ($MqttBroker) {
    Write-Host "`n[*] Gravando configuracoes de MQTT..." -ForegroundColor Yellow
    
    Backup-ConfigFile -path $appSettingsFile -IsDryRun:$DryRun

    $appSettings = $null
    if (Test-Path $appSettingsFile) {
        try {
            $rawContent = Get-Content $appSettingsFile -Raw -Encoding UTF8
            if (-not [string]::IsNullOrWhiteSpace($rawContent)) {
                $appSettings = $rawContent | ConvertFrom-Json
            }
        } catch {
            Write-Warning "Falha ao ler appsettings.json existente. Gerando nova configuracao."
        }
    }

    if (-not $appSettings) {
        $appSettings = [ordered]@{
            OnboardingStatus                  = 9
            DeviceName                        = $env:COMPUTERNAME
            SanitizeName                      = $true
            InterfaceLanguage                 = ""
            EnableStateNotifications          = $true
            CheckForUpdates                   = $true
            LastUpdateNotificationShown       = ""
            EnableExecuteUpdateInstaller      = $true
            ShowBetaUpdates                   = $false
            DisconnectedGracePeriodSeconds    = 60
            ImageCacheRetentionDays           = 7
            AudioCacheRetentionDays           = 7
            WebViewCacheRetentionDays         = 0
            WebViewCacheLastCleared           = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            TrayIconShowDefaultMenu           = $true
            TrayIconShowWebView               = $false
            TrayIconWebViewWidth              = 700
            TrayIconWebViewHeight             = 560
            TrayIconWebViewUrl                = ""
            TrayIconWebViewBackgroundLoading  = $false
            TrayIconWebViewShowMenuOnLeftClick= $false
            ServiceAuthId                     = ""
            BrowserName                       = ""
            BrowserBinary                     = ""
            BrowserIncognitoArg               = ""
            CustomExecutorName                = ""
            CustomExecutorBinary              = ""
            LocalApiEnabled                   = $false
            LocalApiPort                      = 5115
            NotificationsEnabled              = $true
            NotificationsIgnoreImageCertificateErrors = $false
            MediaPlayerEnabled                = $true
            HassUri                           = "http://homeassistant.local:8123"
            HassToken                         = ""
            HassAutoClientCertificate         = $false
            HassAllowUntrustedCertificates    = $true
            HassClientCertificate             = ""
            QuickActionsHotKeyEnabled         = $true
            QuickActionsHotKey                = ""
            MqttEnabled                       = $true
            MqttAddress                       = $MqttBroker
            MqttPort                          = $MqttPort
            MqttUseTls                        = $false
            MqttAllowUntrustedCertificates    = $true
            MqttUsername                      = $MqttUser
            MqttPassword                      = $(if ($MqttPassword) { $MqttPassword } else { "" })
            MqttDiscoveryPrefix               = "homeassistant"
            MqttClientId                      = ""
            MqttUseRetainFlag                 = $true
            MqttRootCertificate               = ""
            MqttClientCertificate             = ""
        }
    } else {
        $appSettings.OnboardingStatus = 9
        $appSettings.MqttEnabled = $true
        $appSettings.MqttAddress = $MqttBroker
        $appSettings.MqttPort = $MqttPort
        $appSettings.MqttUsername = $MqttUser
        if ($MqttPassword) {
            $appSettings.MqttPassword = $MqttPassword
        }
    }

    if ($DryRun) {
        Write-Host "[DRYRUN] Gravaria configuracoes MQTT em $appSettingsFile" -ForegroundColor Gray
    } else {
        $appSettingsJson = ConvertTo-Json $appSettings -Depth 10
        Set-Content -Path $appSettingsFile -Value $appSettingsJson -Encoding UTF8
        Write-Host "[OK] Configuracao MQTT gravada em: $appSettingsFile" -ForegroundColor Green
    }

    # Atualiza servicemqttsettings.json do Satellite Service apenas com -WriteServiceMqtt
    $mqttSvcDirs = if ($WriteServiceMqtt) { $serviceConfigDirs } else { @() }
    if (-not $WriteServiceMqtt -and $serviceConfigDirs.Count -gt 0) {
        Write-Host "[*] servicemqttsettings.json ignorado. Use -WriteServiceMqtt para gravar no Satellite Service." -ForegroundColor Gray
    }
    foreach ($svcDir in $mqttSvcDirs) {
        $svcMqttFile = Join-Path $svcDir "servicemqttsettings.json"
        Backup-ConfigFile -path $svcMqttFile -IsDryRun:$DryRun
        
        $svcMqtt = [ordered]@{
            MqttAddress                    = $MqttBroker
            MqttPort                       = $MqttPort
            MqttUseTls                     = $false
            MqttAllowUntrustedCertificates = $true
            MqttUsername                   = $MqttUser
            MqttPassword                   = $(if ($MqttPassword) { $MqttPassword } else { "" })
            MqttDiscoveryPrefix            = "homeassistant"
            MqttClientId                   = ""
            MqttUseRetainFlag              = $true
            MqttRootCertificate            = ""
            MqttClientCertificate          = ""
        }

        if ($DryRun) {
            Write-Host "[DRYRUN] Gravaria servicemqttsettings.json em $svcMqttFile" -ForegroundColor Gray
        } else {
            if (-not (Test-Path $svcDir)) { New-Item -ItemType Directory -Path $svcDir -Force | Out-Null }
            $svcJson = ConvertTo-Json $svcMqtt -Depth 10
            Set-Content -Path $svcMqttFile -Value $svcJson -Encoding UTF8
            Write-Host "[OK] Satellite Service MQTT configurado em: $svcMqttFile" -ForegroundColor Green
        }
    }

    $mqttWritten = $true
} else {
    Write-Host "`n[!] Parametro -MqttBroker nao informado. Pulando gravacao de MQTT." -ForegroundColor Yellow
}

# 5. Cadastro de Sensores Padrao (sensors.json)
$sensorsRecordedCount = 0
$sensorsFile = Join-Path $userConfigDir "sensors.json"

if (-not $SkipSensors) {
    Write-Host "`n[*] Cadastrando sensores padrao (bateria, carga da CPU)..." -ForegroundColor Yellow
    Backup-ConfigFile -path $sensorsFile -IsDryRun:$DryRun

    $existingSensors = @()
    if (Test-Path $sensorsFile) {
        try {
            $rawContent = Get-Content $sensorsFile -Raw -Encoding UTF8
            if (-not [string]::IsNullOrWhiteSpace($rawContent)) {
                $parsed = $rawContent | ConvertFrom-Json
                if ($parsed -is [System.Collections.IEnumerable] -and $parsed -isnot [string]) {
                    $existingSensors = @($parsed)
                } else {
                    $existingSensors = @($parsed)
                }
            }
        } catch {
            Write-Warning "Falha ao ler sensors.json existente. Iniciando lista vazia."
        }
    }

    $defaultSensors = @(
        [ordered]@{
            Id             = $(Get-DeterministicGuid "sensor_battery")
            Name           = "battery"
            Type           = "BatterySensors"
            UpdateInterval = 30
        },
        [ordered]@{
            Id             = $(Get-DeterministicGuid "sensor_cpuload")
            Name           = "cpuload"
            Type           = "CpuLoadSensor"
            UpdateInterval = 30
        }
    )

    $mergedSensors = [System.Collections.ArrayList]::new()
    
    # Preserva IDs existentes se o sensor ja estiver cadastrado
    foreach ($defSensor in $defaultSensors) {
        $existing = $existingSensors | Where-Object { $_.Type -eq $defSensor.Type -or $_.Name -eq $defSensor.Name } | Select-Object -First 1
        if ($existing -and $existing.Id) {
            $defSensor.Id = $existing.Id
        }
        [void]$mergedSensors.Add($defSensor)
    }

    # Mantem outros sensores configurados anteriormente
    foreach ($exSensor in $existingSensors) {
        $isDuplicate = $mergedSensors | Where-Object { $_.Type -eq $exSensor.Type -or $_.Name -eq $exSensor.Name }
        if (-not $isDuplicate) {
            [void]$mergedSensors.Add($exSensor)
        }
    }

    if ($DryRun) {
        Write-Host "[DRYRUN] Gravaria $($mergedSensors.Count) sensores em $sensorsFile" -ForegroundColor Gray
    } else {
        $sensorsJson = ConvertTo-Json @($mergedSensors) -Depth 10
        Set-Content -Path $sensorsFile -Value $sensorsJson -Encoding UTF8
        Write-Host "[OK] Sensores gravados em: $sensorsFile" -ForegroundColor Green
    }

    # Sincroniza com servico se existir diretorio
    foreach ($svcDir in $serviceConfigDirs) {
        $svcSensorsFile = Join-Path $svcDir "sensors.json"
        Backup-ConfigFile -path $svcSensorsFile -IsDryRun:$DryRun
        if ($DryRun) {
            Write-Host "[DRYRUN] Gravaria sensores em $svcSensorsFile" -ForegroundColor Gray
        } else {
            if (-not (Test-Path $svcDir)) { New-Item -ItemType Directory -Path $svcDir -Force | Out-Null }
            Copy-Item -Path $sensorsFile -Destination $svcSensorsFile -Force
            Write-Host "[OK] Sensores sincronizados no servico: $svcSensorsFile" -ForegroundColor Green
        }
    }

    $sensorsRecordedCount = $mergedSensors.Count
}

# 6. Importacao e Conversao do Catalogo de Comandos (commands.json)
$commandsRecordedCount = 0
$destCommandsFile = Join-Path $userConfigDir "commands.json"
$commandsJsonSource = Join-Path $PSScriptRoot "commands.json"

$shouldProcessCommands = (-not $SkipCommands) -and (($RegisterCommands.IsPresent) -or (Test-Path $commandsJsonSource))

if ($shouldProcessCommands) {
    Write-Host "`n[*] Processando catalogo declarativo de comandos ($commandsJsonSource)..." -ForegroundColor Yellow

    if (Test-Path $commandsJsonSource) {
        Backup-ConfigFile -path $destCommandsFile -IsDryRun:$DryRun

        $commandsCatalog = Get-Content $commandsJsonSource -Raw -Encoding UTF8 | ConvertFrom-Json
        
        $existingCommands = @()
        if (Test-Path $destCommandsFile) {
            try {
                $rawCmd = Get-Content $destCommandsFile -Raw -Encoding UTF8
                if (-not [string]::IsNullOrWhiteSpace($rawCmd)) {
                    $parsed = $rawCmd | ConvertFrom-Json
                    if ($parsed -is [System.Collections.IEnumerable] -and $parsed -isnot [string]) {
                        $existingCommands = @($parsed)
                    } else {
                        $existingCommands = @($parsed)
                    }
                }
            } catch {
                Write-Warning "Falha ao ler commands.json de destino existente."
            }
        }

        $configuredCommandsList = [System.Collections.ArrayList]::new()

        foreach ($cmd in $commandsCatalog.commands) {
            # 1. Determina o GUID (Id)
            $existing = $existingCommands | Where-Object { $_.Name -eq $cmd.name } | Select-Object -First 1
            $cmdGuid = $null
            if ($existing -and $existing.Id) {
                $cmdGuid = $existing.Id
            } else {
                $parsedGuid = [System.Guid]::Empty
                if ([System.Guid]::TryParse($cmd.id, [ref]$parsedGuid)) {
                    $cmdGuid = $cmd.id
                } else {
                    $cmdGuid = Get-DeterministicGuid "cmd_$($cmd.name)"
                }
            }

            # 2. Determina o EntityType
            $entityType = @(switch ($cmd.entity_type) {
                "Button" { "Button" }
                "Switch" { "Switch" }
                "Light"  { "Light" }
                "Lock"   { "Lock" }
                "Siren"  { "Siren" }
                default  { "Button" }
            })[0]

            # 3. Monta a linha de comando completa
            $fullCommandLine = if ($cmd.executable -and $cmd.arguments) {
                "$($cmd.executable) $($cmd.arguments)".Trim()
            } elseif ($cmd.executable) {
                $cmd.executable
            } else {
                $cmd.arguments
            }

            # 4. Determina o CommandType aceito pelo HASS.Agent
            # O switch do PowerShell ignora maiusculas e acumula todas as correspondencias; @()[0] garante um unico valor
            $cmdType = @(switch ($cmd.command_type) {
                "Custom"            { "CustomCommand" }
                "PowerShell"        { "CustomCommand" }
                "PowershellCommand" { "PowershellCommand" }
                "Shutdown"          { if ($cmd.arguments) { "CustomCommand" } else { "ShutdownCommand" } }
                "Restart"           { if ($cmd.arguments) { "CustomCommand" } else { "RestartCommand" } }
                "Sleep"             { "SleepCommand" }
                "Lock"              { "LockCommand" }
                "Hibernate"         { "HibernateCommand" }
                default             {
                    if ($cmd.command_type -match "Command$") { $cmd.command_type } else { "$($cmd.command_type)Command" }
                }
            })[0]

            $commandString = if ($cmdType -in @("SleepCommand", "LockCommand", "HibernateCommand")) { "" } else { $fullCommandLine }

            $configuredCmd = [ordered]@{
                Id                = $cmdGuid
                Name              = $cmd.name
                EntityName        = $cmd.name
                Type              = $cmdType
                EntityType        = $entityType.ToLowerInvariant()
                Command           = $commandString
                KeyCode           = 0
                RunAsLowIntegrity = $false
                Keys              = @()
            }

            [void]$configuredCommandsList.Add($configuredCmd)
            Write-Host "  - [$entityType] $($cmd.friendly_name) ($($cmd.name)) -> $cmdType" -ForegroundColor Cyan
        }

        # Preserva comandos extras que nao estavam no catalogo
        foreach ($exCmd in $existingCommands) {
            $isDuplicate = $configuredCommandsList | Where-Object { $_.Name -eq $exCmd.Name }
            if (-not $isDuplicate) {
                [void]$configuredCommandsList.Add($exCmd)
            }
        }

        if ($DryRun) {
            Write-Host "[DRYRUN] Gravaria $($configuredCommandsList.Count) comandos formatados em $destCommandsFile" -ForegroundColor Gray
        } else {
            $commandsJsonFormatted = ConvertTo-Json @($configuredCommandsList) -Depth 10
            Set-Content -Path $destCommandsFile -Value $commandsJsonFormatted -Encoding UTF8
            Write-Host "[OK] Comandos compativeis com HASS.Agent gravados em: $destCommandsFile" -ForegroundColor Green
        }

        # Sincroniza com Satellite Service se diretorio existir
        foreach ($svcDir in $serviceConfigDirs) {
            $svcCommandsFile = Join-Path $svcDir "commands.json"
            Backup-ConfigFile -path $svcCommandsFile -IsDryRun:$DryRun
            if ($DryRun) {
                Write-Host "[DRYRUN] Gravaria comandos em $svcCommandsFile" -ForegroundColor Gray
            } else {
                if (-not (Test-Path $svcDir)) { New-Item -ItemType Directory -Path $svcDir -Force | Out-Null }
                Copy-Item -Path $destCommandsFile -Destination $svcCommandsFile -Force
                Write-Host "[OK] Comandos sincronizados no servico: $svcCommandsFile" -ForegroundColor Green
            }
        }

        $commandsRecordedCount = $configuredCommandsList.Count
    } else {
        Write-Error "Arquivo commands.json nao encontrado em: $commandsJsonSource"
    }
}

# 6b. Reabre o HASS.Agent se ele estava em execucao
Start-HassAgentIfNeeded

# 7. Resumo do que foi efetivamente gravado
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "  Resumo do Provisionamento do HASS.Agent:" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

if ($mqttWritten) {
    Write-Host $(if ($DryRun) { "[DRYRUN] Configuracoes de MQTT que seriam gravadas:" } else { "[OK] Configuracoes de MQTT gravadas com sucesso:" }) -ForegroundColor Green
    Write-Host "  - Arquivo: $appSettingsFile" -ForegroundColor White
    Write-Host "  - Broker:  $MqttBroker : $MqttPort" -ForegroundColor White
    Write-Host "  - Usuario: $MqttUser" -ForegroundColor White
    if ($MqttPassword) {
        Write-Host "  - Senha:   [definida]" -ForegroundColor White
    } else {
        Write-Host "  - Senha:   [nao informada]" -ForegroundColor Yellow
    }
} else {
    Write-Host "[!] Nenhuma configuracao de MQTT foi gravada." -ForegroundColor Yellow
    Write-Host "    Para gravar, execute informando -MqttBroker <ip> -MqttPassword <senha> ou as variaveis de ambiente correspondentes." -ForegroundColor Gray
}

if ($sensorsRecordedCount -gt 0) {
    Write-Host "`n$(if ($DryRun) { "[DRYRUN] $sensorsRecordedCount sensores seriam gravados" } else { "[OK] $sensorsRecordedCount sensores gravados" }) em: $sensorsFile" -ForegroundColor Green
    Write-Host "  - battery (BatterySensors)" -ForegroundColor Cyan
    Write-Host "  - cpuload (CpuLoadSensor)" -ForegroundColor Cyan
}

if ($commandsRecordedCount -gt 0) {
    Write-Host "`n$(if ($DryRun) { "[DRYRUN] $commandsRecordedCount comandos seriam gravados" } else { "[OK] $commandsRecordedCount comandos gravados" }) em: $destCommandsFile" -ForegroundColor Green
}

if (-not $script:AgentWasRunning) {
    Write-Host "`nObservacao: abra o HASS.Agent para carregar as novas configuracoes." -ForegroundColor Yellow
}
Write-Host "==========================================================`n" -ForegroundColor Cyan
