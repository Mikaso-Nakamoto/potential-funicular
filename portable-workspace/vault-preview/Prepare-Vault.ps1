#requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('Create','Check')][string]$Action = 'Check', [string]$Root = '')
$ErrorActionPreference = 'Stop'
$workspaceDirectory = Split-Path -Parent $PSScriptRoot
if (-not $Root) { $Root = Join-Path $workspaceDirectory 'Runtime' }
. (Join-Path $workspaceDirectory 'Workspace.Common.ps1')
. (Join-Path $PSScriptRoot 'Vault.Common.ps1')
$Root = Get-Workspace $Root
$path = Join-Path $Root 'private\workspace.vault'
$lock = $null; $password = $null; $confirmation = $null; $generated = $null
function Read-HiddenText([string]$Prompt) {
    $secret = Read-Host $Prompt -AsSecureString
    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    } finally {
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
        $secret.Dispose()
    }
}
try {
    Initialize-VaultCrypto
    $lock = [IO.File]::Open((Join-Path $Root '.session.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    if (Test-ProfileBusy (Join-Path $Root 'private\profile')) { throw 'Close the browser before testing migration.' }
    if ($Action -eq 'Create') {
        if (Test-Path -LiteralPath $path) { throw 'Vault exists. Use Check. No existing vault will be overwritten.' }
        $configPath = Join-Path $Root 'private\xray.json'
        Assert-ConfigPolicy $configPath
        Write-Warning 'PREVIEW: creates an encrypted COPY. Old xray.json and browser profile remain readable; password is NOT yet enforced by Start-Workspace.ps1.'
        $url = Read-HiddenText 'Complete HTTPS subscription URL (hidden, saved only inside vault)'
        $uri = $null
        if (-not [Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Fragment) { throw 'A complete HTTPS subscription URL without userinfo/fragment is required.' }
        $hwid = Convert-DeviceHwid (Read-HiddenText 'Your existing device HWID UUID/GUID (hidden)')
        Write-Warning 'Creates a six-word random passphrase. No recovery. Do not run in a transcript, recording or shared console. The phrase will be visible in scrollback.'
        $generated = New-VaultPassphrase
        $displayPassword = $generated.CopyPassword()
        $pointer = [IntPtr]::Zero
        try {
            $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($displayPassword)
            Write-Host ('Write down securely: ' + [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)) -ForegroundColor Yellow
            $confirmation = Read-Host 'Re-enter the complete generated phrase, six words with single spaces' -AsSecureString
        } finally {
            if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
            $displayPassword.Dispose()
        }
        $document = @{
            version = 1; createdAtUtc = [DateTime]::UtcNow.ToString('o')
            subscription = @{ url = $url; hwid = $hwid }
            activeConfig = ([IO.File]::ReadAllText($configPath) | ConvertFrom-Json)
        }
        Write-NewVault $path $document $generated $confirmation
        Write-Host 'Encrypted copy created and read-back verified. Originals were NOT removed. Test Check in a NEW PowerShell process.' -ForegroundColor Green
    } else {
        $password = Read-Host 'Vault passphrase' -AsSecureString
        $document = Read-Vault $path $password
        $names = @($document.PSObject.Properties.Name)
        if ('subscription' -notin $names -or 'activeConfig' -notin $names) { throw 'Expected migration payload was not found.' }
        $null = Convert-DeviceHwid $document.subscription.hwid
        Write-Host 'Vault authenticated and decrypted. Subscription and configuration are present; values are NOT displayed.' -ForegroundColor Green
        Write-Warning 'This is a read-only check. Current launcher still uses plaintext xray.json. Browser profile is not encrypted.'
    }
} finally {
    $url = $null; $uri = $null; $hwid = $null; $document = $null
    if ($generated) { $generated.Dispose() }
    if ($password) { $password.Dispose() }
    if ($confirmation) { $confirmation.Dispose() }
    if ($lock) { $lock.Dispose() }
}
