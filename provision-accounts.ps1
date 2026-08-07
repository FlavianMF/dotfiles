#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Write-Info { Write-Host "[INFO] $args" -ForegroundColor Green }
function Write-Warn { Write-Host "[WARN] $args" -ForegroundColor Yellow }
function Write-Error-Custom { Write-Host "[ERROR] $args" -ForegroundColor Red }

$AdminName = Read-Host "Nome da conta admin [admin]"
if ([string]::IsNullOrWhiteSpace($AdminName)) { $AdminName = "admin" }

$AlunoName = Read-Host "Nome da conta aluno [aluno]"
if ([string]::IsNullOrWhiteSpace($AlunoName)) { $AlunoName = "aluno" }

function Get-SecurePasswordWithConfirmation {
    param([string]$Prompt)

    $maxAttempts = 3
    $attempt = 0

    while ($attempt -lt $maxAttempts) {
        $password1 = Read-Host -AsSecureString -Prompt $Prompt
        $password2 = Read-Host -AsSecureString -Prompt "Confirme a senha"

        $bstr1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password1)
        $plaintext1 = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr1)

        $bstr2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password2)
        $plaintext2 = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr2)

        if ($plaintext1 -eq $plaintext2) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr1)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr2)
            return $password1
        }
        else {
            Write-Warn "Senhas não conferem. Tente novamente."
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr1)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr2)
            $attempt++
        }
    }

    Write-Error-Custom "Limite de tentativas atingido."
    exit 1
}

$AdminPassword = Get-SecurePasswordWithConfirmation "Senha para conta admin"
$AlunoPassword = Get-SecurePasswordWithConfirmation "Senha para conta aluno"

function New-OrUpdateLocalAccount {
    param(
        [string]$Username,
        [securestring]$SecurePassword,
        [string]$FullName,
        [string]$Description,
        [switch]$AsAdmin
    )

    $existingUser = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue

    if ($existingUser) {
        Write-Info "Conta '$Username' já existe, atualizando senha..."
        Set-LocalUser -Name $Username -Password $SecurePassword -PasswordNeverExpires $true
        Write-Info "Senha atualizada para '$Username'"
    }
    else {
        Write-Info "Criando conta '$Username'..."
        New-LocalUser -Name $Username `
            -Password $SecurePassword `
            -FullName $FullName `
            -Description $Description `
            -PasswordNeverExpires `
            -AccountNeverExpires | Out-Null
        Write-Info "Conta '$Username' criada com sucesso"
    }

    if ($AsAdmin) {
        $adminGroup = Get-LocalGroup -Name "Administrators" -ErrorAction SilentlyContinue
        if ($adminGroup) {
            $isMember = Get-LocalGroupMember -Group "Administrators" -Member $Username -ErrorAction SilentlyContinue
            if (-not $isMember) {
                Add-LocalGroupMember -Group "Administrators" -Member $Username -ErrorAction SilentlyContinue
                Write-Info "Usuário '$Username' adicionado ao grupo Administrators"
            }
            else {
                Write-Info "Usuário '$Username' já é membro do grupo Administrators"
            }
        }
    }
}

Write-Info "Iniciando provisionamento de contas locais..."
Write-Host ""

New-OrUpdateLocalAccount -Username $AdminName -SecurePassword $AdminPassword -FullName "Administrator Account" -Description "Conta administrativa" -AsAdmin
Write-Host ""

New-OrUpdateLocalAccount -Username $AlunoName -SecurePassword $AlunoPassword -FullName "Student Account" -Description "Conta de aluno"
Write-Host ""

$guestUser = Get-LocalUser -Name "Guest" -ErrorAction SilentlyContinue
if ($guestUser) {
    if ($guestUser.Enabled) {
        Write-Info "Desabilitando conta Guest..."
        Disable-LocalUser -Name "Guest" -ErrorAction SilentlyContinue
        Write-Info "Conta Guest desabilitada"
    }
    else {
        Write-Info "Conta Guest já está desabilitada"
    }
}

Write-Host ""
Write-Info "Configurando auto-login para conta '$AlunoName'..."

$WinLogonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

try {
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AlunoPassword)
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)

    Set-ItemProperty -Path $WinLogonPath -Name "AutoAdminLogon" -Value "1" -Type String
    Set-ItemProperty -Path $WinLogonPath -Name "DefaultUserName" -Value $AlunoName -Type String
    Set-ItemProperty -Path $WinLogonPath -Name "DefaultPassword" -Value $plainPassword -Type String
    Set-ItemProperty -Path $WinLogonPath -Name "DefaultDomainName" -Value $env:COMPUTERNAME -Type String

    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

    Write-Info "Auto-login configurado para '$AlunoName'"
    Write-Warn "AVISO DE SEGURANÇA: A senha foi armazenada em texto puro no registro do Windows."
    Write-Warn "Para maior segurança, considere usar Sysinternals Autologon.exe (armazena com criptografia LSA)."
}
catch {
    Write-Error-Custom "Erro ao configurar auto-login: $_"
    exit 1
}

Write-Host ""
Write-Info "Provisionamento concluído!"
Write-Host ""
Write-Host "Resumo:"
Write-Host "=========="
Write-Host "[OK] Conta admin '$AdminName' criada/atualizada"
Write-Host "[OK] Conta aluno '$AlunoName' criada/atualizada"
Write-Host "[OK] Conta Guest desabilitada"
Write-Host "[OK] Auto-login configurado para '$AlunoName'"
Write-Host ""
Write-Host "Próximos passos:"
Write-Host "1. Reiniciar a máquina para confirmar auto-login"
Write-Host "2. Fazer login com a conta '$AdminName' para verificar privilégios"
Write-Host "3. Verificar que '$AlunoName' não tem acesso administrativo"
Write-Host ""
