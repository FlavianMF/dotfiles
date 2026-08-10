#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Write-Info { Write-Host "[INFO] $args" -ForegroundColor Green }
function Write-Warn { Write-Host "[WARN] $args" -ForegroundColor Yellow }
function Write-Error-Custom { Write-Host "[ERROR] $args" -ForegroundColor Red }

Write-Info "=== Fase 1: Configurar nomes das contas ==="
$AdminName = Read-Host "Nome da conta admin [admin]"
if ([string]::IsNullOrWhiteSpace($AdminName)) { $AdminName = "admin" }
Write-Info "Conta admin: '$AdminName'"

$AlunoName = Read-Host "Nome da conta aluno [aluno]"
if ([string]::IsNullOrWhiteSpace($AlunoName)) { $AlunoName = "aluno" }
Write-Info "Conta aluno: '$AlunoName'"

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

    Write-Host "[DEBUG] Iniciando New-OrUpdateLocalAccount: Username=$Username, FullName=$FullName, AsAdmin=$AsAdmin" -ForegroundColor Cyan

    try {
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
    }
    catch {
        Write-Error-Custom "Erro ao processar conta '$Username': $_"
        Write-Host "[DEBUG] Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
        return
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

function Initialize-UserProfile {
    param(
        [string]$Username,
        [securestring]$SecurePassword
    )

    Write-Info "Pré-criando perfil de usuário para '$Username' (evita que a conta fique 'invisível' na tela de login)..."

    try {
        $credential = New-Object System.Management.Automation.PSCredential($Username, $SecurePassword)
        Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" `
            -ArgumentList "/c", "exit" `
            -Credential $credential `
            -WorkingDirectory "$env:SystemRoot\System32" `
            -WindowStyle Hidden `
            -Wait -ErrorAction Stop

        Write-Info "Perfil de '$Username' inicializado (C:\Users\$Username deve existir agora)"
    }
    catch {
        Write-Warn "Não foi possível pré-inicializar o perfil de '$Username': $_"
        Write-Warn "A conta ainda funciona via 'Outro usuário' na tela de login, mas o perfil só será criado no primeiro login manual."
    }
}

Write-Info "Iniciando provisionamento de contas locais..."
Write-Host ""

New-OrUpdateLocalAccount -Username $AdminName -SecurePassword $AdminPassword -FullName "Administrator Account" -Description "Conta administrativa" -AsAdmin
Write-Host ""

Initialize-UserProfile -Username $AdminName -SecurePassword $AdminPassword
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

$SpecialAccountsPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList"
if (Test-Path $SpecialAccountsPath) {
    foreach ($acct in @($AdminName, $AlunoName)) {
        $existing = Get-ItemProperty -Path $SpecialAccountsPath -Name $acct -ErrorAction SilentlyContinue
        if ($null -ne $existing -and $existing.$acct -eq 0) {
            Write-Warn "Conta '$acct' estava marcada como oculta no registro; removendo restrição..."
            Remove-ItemProperty -Path $SpecialAccountsPath -Name $acct -ErrorAction SilentlyContinue
        }
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
Write-Host "[OK] Perfil de '$AdminName' pré-inicializado"
Write-Host "[OK] Conta aluno '$AlunoName' criada/atualizada"
Write-Host "[OK] Conta Guest desabilitada"
Write-Host "[OK] Auto-login configurado para '$AlunoName'"
Write-Host ""
Write-Host "Próximos passos:"
Write-Host "1. Reiniciar a máquina para confirmar auto-login"
Write-Host "   → Comportamento esperado: Windows boota direto no desktop de '$AlunoName'"
Write-Host "     (a tela de login é pulada automaticamente)"
Write-Host ""
Write-Host "2. Para fazer login com '$AdminName' e verificar privilégios:"
Write-Host "   → Pressione Ctrl+Alt+Del > 'Trocar usuário'"
Write-Host "   → No Windows 11, '$AdminName' pode não aparecer como ícone —"
Write-Host "     clique em 'Outro usuário' e digite '$AdminName' manualmente"
Write-Host "   → Digite a senha (perfil já pré-criado, login deve ser rápido)"
Write-Host "   → IMPORTANTE: Não use 'Sair' nem reinicie — esses fluxos"
Write-Host "     reaplicam o auto-login, levando de volta a '$AlunoName'"
Write-Host ""
Write-Host "3. Verificar permissões:"
Write-Host "   → No PowerShell: whoami /groups (admin deve conter 'Administrators')"
Write-Host "   → Ou Settings > Contas (admin = Administrador, aluno = Usuário padrão)"
Write-Host ""
