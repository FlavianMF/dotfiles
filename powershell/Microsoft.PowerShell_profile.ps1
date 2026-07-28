# PowerShell 7+ profile with oh-my-posh and PSReadLine

# ===== Oh My Posh Initialization =====
$ThemePath = "$HOME\.spaceship.omp.json"
if (Test-Path $ThemePath) {
    oh-my-posh init pwsh --config $ThemePath | Invoke-Expression
}

# ===== PSReadLine Configuration =====
Import-Module PSReadLine

# Enable predictive IntelliSense (requires PSReadLine 2.2+)
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView

# Syntax highlighting colors
$PSReadLineOptions = @{
    Colors = @{
        Command             = 'Cyan'
        Parameter           = 'Gray'
        Operator            = 'Magenta'
        String              = 'Green'
        Number              = 'Yellow'
        Member              = 'Cyan'
        Keyword             = 'Blue'
        Comment             = 'DarkGray'
        Variable            = 'Green'
        ContinuationPrompt  = 'Cyan'
    }
}
Set-PSReadLineOption @PSReadLineOptions

# ===== Editor =====
$env:EDITOR = 'nvim'
$env:VISUAL = 'nvim'

# ===== Aliases =====
Set-Alias vim nvim
Set-Alias vi nvim
Set-Alias l ls

# ===== PATH Additions =====
$pathsToAdd = @(
    "$HOME\.cargo\bin",
    "$HOME\.local\bin"
)

foreach ($path in $pathsToAdd) {
    if ((Test-Path $path) -and $env:PATH -notlike "*$path*") {
        $env:PATH = "$path;$env:PATH"
    }
}

# ===== Functions =====
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Show admin indicator in prompt if needed
function prompt {
    if (Test-Administrator) {
        Write-Host "[ADMIN] " -ForegroundColor Red -NoNewline
    }
    "$('> ')"
}
