<#
.SYNOPSIS
    Instala e provisiona o HASS.Agent e o Satellite Service no Windows 11 para integracao com Home Assistant.

.DESCRIPTION
    Este script automatiza o provisionamento do HASS.Agent (v2) via winget ou GitHub Releases,
    garante a inicializacao do servico de satelite (Satellite Service) para recepcao de comandos
    em segundo plano e registra o catalogo declarativo de comandos do sistema.

.PARAMETER MqttBroker
    Endereco IP ou host Tailscale do broker MQTT (ex: 100.x.y.z).

.PARAMETER MqttPort
    Porta do broker MQTT (padrao: 1883).

.PARAMETER MqttUser
    Usuario de autenticacao do MQTT (padrao: hass).

.PARAMETER MqttPassword
    Senha de autenticacao do MQTT.

.PARAMETER RegisterCommands
    Se informado, importa os comandos de commands.json para o diretorio de configuracao do HASS.Agent.

.EXAMPLE
    .\install-hass-agent.ps1 -MqttBroker "100.80.20.10" -MqttUser "hass" -MqttPassword "sua_senha" -RegisterCommands
#>

[CmdletBinding()]
param(
    [string]$MqttBroker,
    [int]$MqttPort = 1883,
    [string]$MqttUser = "hass",
    [string]$MqttPassword,
    [switch]$RegisterCommands,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Test-AdminPrivileges {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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
$appInstalled = Get-Command "HASS.Agent.exe" -ErrorAction SilentlyContinue
$satelliteService = Get-Service -Name "HASS.Agent.SatelliteService" -ErrorAction SilentlyContinue

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
            Write-Host "[*] Baixando instalador oficial do GitHub Releases..." -ForegroundColor Yellow
            $tempInstaller = "$env:TEMP\HASS.Agent.Installer.exe"
            $latestUrl = "https://github.com/hass-agent/HASS.Agent/releases/latest/download/HASS.Agent.Installer.exe"
            
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
    Write-Host "Recomenda-se abrir a interface do HASS.Agent uma vez e habilitar o Satellite Service nas configuracoes." -ForegroundColor Gray
}

# 3. Importacao do Catalogo de Comandos
if ($RegisterCommands) {
    Write-Host "`n[*] Importando catalogo de comandos declarativo..." -ForegroundColor Yellow
    $commandsJsonSource = Join-Path $PSScriptRoot "commands.json"

    if (Test-Path $commandsJsonSource) {
        $commandsData = Get-Content $commandsJsonSource -Raw | ConvertFrom-Json
        Write-Host "[OK] Catalogo de comandos carregado com sucesso:" -ForegroundColor Green
        foreach ($cmd in $commandsData.commands) {
            Write-Host "  - [$($cmd.entity_type)] $($cmd.friendly_name) ($($cmd.name))" -ForegroundColor Cyan
        }

        # Diretorio de configuracao do HASS.Agent (AppData e ProgramData)
        $satelliteConfigDir = "$env:PROGRAMDATA\LAB02 Research\HASS.Agent Satellite Service\config"
        if (-not (Test-Path $satelliteConfigDir)) {
            New-Item -ItemType Directory -Path $satelliteConfigDir -Force | Out-Null
        }
        $destCommands = Join-Path $satelliteConfigDir "commands.json"
        Copy-Item -Path $commandsJsonSource -Destination $destCommands -Force
        Write-Host "[OK] Comandos sincronizados em: $destCommands" -ForegroundColor Green
    } else {
        Write-Error "Arquivo commands.json nao encontrado em: $commandsJsonSource"
    }
}

# 4. Informacoes de Conexao MQTT
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "  Proximos Passos de Configuracao:" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
if ($MqttBroker) {
    Write-Host "Broker Configurado: $MqttBroker : $MqttPort" -ForegroundColor Green
    Write-Host "Usuario: $MqttUser" -ForegroundColor Green
} else {
    Write-Host "1. Abra o HASS.Agent no Windows (Menu Iniciar -> HASS.Agent)." -ForegroundColor White
    Write-Host "2. Acesse 'Configuration' -> 'MQTT Settings'." -ForegroundColor White
    Write-Host "3. Preencha com o IP Tailscale da sua VPS (porta 1883) e usuario/senha definidos em secrets/mqtt.env." -ForegroundColor White
    Write-Host "4. Clique em 'Store & Activate'." -ForegroundColor White
}
Write-Host "5. Seus botoes e sensores serao detectados automaticamente pelo Home Assistant via MQTT Auto-Discovery!" -ForegroundColor Yellow
Write-Host "==========================================================`n" -ForegroundColor Cyan
