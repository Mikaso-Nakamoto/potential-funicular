#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Workspace.Common.ps1')
. (Join-Path $PSScriptRoot 'Bootstrap.Common.ps1')
. (Join-Path $PSScriptRoot 'Native.Common.ps1')
. (Join-Path $PSScriptRoot 'VaultV03.Common.ps1')
Assert-VicaPlatform
$lock = $null; $recovery = $null; $password = $null; $confirm = $null; $plain = $null; $owned = $false
$oldTemp = $env:TEMP; $oldTmp = $env:TMP; $phase = 'preflight'
try {
    $Root = Get-Workspace $Root
    $lock = [IO.File]::Open((Join-Path $Root '.session.lock'),'OpenOrCreate','ReadWrite','None')
    if (Test-ProfileBusy (Join-Path $Root 'private\profile')) { throw 'Close browser.' }
    $temp = Join-Path $Root 'private\tmp'; New-Item -ItemType Directory -Path $temp -Force | Out-Null
    $env:TEMP = $temp; $env:TMP = $temp
    Initialize-PasswordPreview
    $path = Join-Path $Root 'private\workspace.vault'
    $bytes = Read-V03Bytes $path; $before = Get-TestCipherHash $bytes
    $phase = 'recovery-authentication'
    $recovery = Read-Host 'TEN recovery words (hidden)' -AsSecureString
    $plain = [VicaPasswordPreview.Envelope]::Open($bytes,$recovery,$true)
    $doc = (New-Object Text.UTF8Encoding($false,$true)).GetString($plain) | ConvertFrom-Json
    Assert-VaultDocument $doc
    Write-Host 'RECOVERY OK' -ForegroundColor Green
    $password = Read-Host 'NEW password, minimum 8 characters (hidden)' -AsSecureString
    $confirm = Read-Host 'Repeat NEW password (hidden)' -AsSecureString
    $phase = 'fresh-key-password-reset'
    $next = [VicaPasswordPreview.Envelope]::ChangePassword($bytes,$recovery,$true,$password,$confirm,$recovery)
    $stage = $path + '.reset-' + [Guid]::NewGuid().ToString('N'); $owned = $true
    Write-V03Stage $stage $next $confirm $recovery
    if ((Read-Host 'Type RESET to publish; anything else cancels') -cne 'RESET') { return }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $before) { throw 'Vault changed externally.' }
    $backup = $path + '.backup-' + [Guid]::NewGuid().ToString('N')
    $phase = 'encrypted-publication'
    [IO.File]::Replace($stage,$path,$backup)
    Write-Host 'PASSWORD RESET OK. Fresh data key; recovery words unchanged.' -ForegroundColor Green
    Write-Host ('Encrypted previous version: ' + $backup)
} catch { throw ('Password reset stopped at: ' + $phase + '. Details suppressed; keep encrypted backups.') }
finally {
    if ($plain) { [Array]::Clear($plain,0,$plain.Length) }
    foreach ($item in @($recovery,$password,$confirm)) { if ($null -ne $item) { $item.Dispose() } }
    if ($owned -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Force }
    $doc = $null
    $env:TEMP = $oldTemp; $env:TMP = $oldTmp
    if ($lock) { $lock.Dispose() }
}
