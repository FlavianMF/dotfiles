@echo off
REM Provision accounts script wrapper
REM Downloads provision-accounts.ps1 from GitHub and runs with admin privileges

setlocal enabledelayedexpansion

echo.
echo ============================================
echo  Provision Accounts Installer
echo ============================================
echo.

REM Check for admin privileges
net session >nul 2>&1
if errorlevel 1 (
    echo [INFO] Requesting administrator privileges...
    echo.

    REM Re-run this script with admin privileges
    powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b 0
)

REM We now have admin privileges
echo [INFO] Administrator privileges confirmed.
echo.

REM Define download URL and temp location
set "GITHUB_URL=https://raw.githubusercontent.com/FlavianMF/dotfiles/master/provision-accounts.ps1"
set "TEMP_SCRIPT=%TEMP%\provision-accounts.ps1"

echo [INFO] Downloading provision-accounts.ps1 from GitHub...

REM Download the script with correct UTF-8 encoding
powershell -NoProfile -Command ^
    "$ProgressPreference = 'SilentlyContinue'; " ^
    "try { " ^
    "  $content = (Invoke-WebRequest -Uri '%GITHUB_URL%' -UseBasicParsing).Content; " ^
    "  [System.IO.File]::WriteAllText('%TEMP_SCRIPT%', $content, [System.Text.Encoding]::UTF8); " ^
    "  exit 0; " ^
    "} catch { " ^
    "  Write-Host '[ERROR] Failed to download script: '$_.Exception.Message -ForegroundColor Red; " ^
    "  exit 1; " ^
    "}"

if errorlevel 1 (
    echo.
    echo [ERROR] Download failed. Check your internet connection and try again.
    pause
    exit /b 1
)

if not exist "%TEMP_SCRIPT%" (
    echo.
    echo [ERROR] Downloaded script not found.
    pause
    exit /b 1
)

echo [INFO] Download complete. Running provisioning script...
echo.

REM Run the downloaded script with admin privileges (already elevated)
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP_SCRIPT%"

set "SCRIPT_EXIT_CODE=!errorlevel!"

echo.

REM Cleanup
echo [INFO] Cleaning up temporary files...
del /f /q "%TEMP_SCRIPT%" 2>nul

if !SCRIPT_EXIT_CODE! equ 0 (
    echo [OK] Provisioning completed successfully!
) else (
    echo [ERROR] Provisioning script exited with code !SCRIPT_EXIT_CODE!
)

echo.
pause
exit /b !SCRIPT_EXIT_CODE!
