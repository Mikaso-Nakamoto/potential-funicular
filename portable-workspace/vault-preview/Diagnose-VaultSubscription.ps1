#requires -Version 5.1
[CmdletBinding()]
param([string]$Root = 'Z:\Iran\Browser\Working-Vault-Preview\WorkingRuntime')
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Use 64-bit Windows PowerShell 5.1.' }
. (Join-Path $PSScriptRoot 'VaultRefresh.Common.ps1')
. (Join-Path $PSScriptRoot 'VaultRefresh.Diagnostics.ps1')
$lock = $null; $password = $null; $document = $null; $text = $null; $lines = $null
$oldTemp = $env:TEMP; $oldTmp = $env:TMP
$phase = 'preflight'
try {
    $Root = Get-Workspace $Root
    $lock = [IO.File]::Open((Join-Path $Root '.session.lock'),'OpenOrCreate','ReadWrite','None')
    if (Test-ProfileBusy (Join-Path $Root 'private\profile')) { throw 'Profile busy.' }
    $tmp = Join-Path $Root 'private\tmp'
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $env:TEMP = $tmp; $env:TMP = $tmp
    $phase = 'unlock'
    $password = Read-Host 'Vault passphrase (hidden)' -AsSecureString
    $path = Join-Path $Root 'private\workspace.vault'
    $before = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $document = Read-Vault $path $password
    $phase = 'fetch'
    Write-Host 'READ-ONLY diagnosis: makes a live HTTPS request using stored URL/HWID over current Windows connection; does not update vault or run Xray/browser.'
    $text = Get-SubscriptionText -Uri ([Uri]$document.subscription.url) -DeviceHwid $document.subscription.hwid
    $phase = 'diagnose'
    Get-RefreshResponseDiagnostics $text
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $before) { throw 'Vault changed externally.' }
    Write-Host 'DIAGNOSTIC: vault ciphertext unchanged; no response/config was saved.'
} catch {
    throw ('Read-only diagnosis stopped at: ' + $phase + '. Details suppressed. Do not share secrets.')
} finally {
    if ($password) { $password.Dispose() }
    $document = $null; $text = $null; $lines = $null
    $env:TEMP = $oldTemp; $env:TMP = $oldTmp
    if ($lock) { $lock.Dispose() }
}
