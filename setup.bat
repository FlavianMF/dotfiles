@echo off
REM Quick installer wrapper for dotfiles
REM Downloads, extracts, and runs install.ps1

setlocal enabledelayedexpansion

echo.
echo ============================================
echo  Dotfiles Setup Installer
echo ============================================
echo.

REM Get script directory
set "SCRIPT_DIR=%~dp0"
if exist "%SCRIPT_DIR%setup.ps1" (
    echo Running local setup.ps1...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%setup.ps1"
) else (
    echo Running remote setup.ps1 from GitHub...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "iex (iwr 'https://raw.githubusercontent.com/FlavianMF/dotfiles/master/setup.ps1' -UseBasicParsing).Content"
)

if errorlevel 1 (
    echo.
    echo [ERROR] Setup failed. Check the PowerShell output above.
    pause
    exit /b 1
)

echo.
echo [OK] Setup complete!
pause
