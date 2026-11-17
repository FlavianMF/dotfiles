<#
.SYNOPSIS
    Configure Windows to use the WSL2 SSH SOCKS5 proxy (127.0.0.1:1080).

.EXAMPLE
    .\tailscale-proxy.ps1 on
    .\tailscale-proxy.ps1 off
    .\tailscale-proxy.ps1 browser -Browser chrome
    .\tailscale-proxy.ps1 browser -Browser msedge
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet("on", "off", "browser", "status")]
    [string]$Action = "status",

    [ValidateSet("chrome", "msedge")]
    [string]$Browser = "chrome",

    [int]$Port = 1080
)

$RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
$ProxyAddr = "127.0.0.1:$Port"

switch ($Action) {
    "on" {
        Set-ItemProperty -Path $RegPath -Name ProxyEnable -Value 1
        Set-ItemProperty -Path $RegPath -Name ProxyServer -Value "socks=$ProxyAddr"
        Write-Host "Windows SOCKS5 proxy enabled: socks=$ProxyAddr" -ForegroundColor Green
    }
    "off" {
        Set-ItemProperty -Path $RegPath -Name ProxyEnable -Value 0
        Write-Host "Windows proxy disabled." -ForegroundColor Yellow
    }
    "browser" {
        $Exe = if ($Browser -eq "msedge") { "msedge.exe" } else { "chrome.exe" }
        Start-Process $Exe -ArgumentList @(
            "--proxy-server=socks5://$ProxyAddr",
            "--host-resolver-rules=MAP * ~NOTFOUND , EXCLUDE 127.0.0.1"
        )
        Write-Host "Launched $Exe with SOCKS5 proxy socks5://$ProxyAddr" -ForegroundColor Green
    }
    "status" {
        $props = Get-ItemProperty -Path $RegPath
        Write-Host "ProxyEnable: $($props.ProxyEnable)"
        Write-Host "ProxyServer: $($props.ProxyServer)"
    }
}
