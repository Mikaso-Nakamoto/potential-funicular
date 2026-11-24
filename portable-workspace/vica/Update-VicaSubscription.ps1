#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Root,[switch]$Apply)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Bootstrap.Common.ps1')
Assert-VicaPlatform
. (Join-Path $PSScriptRoot 'Refresh.Common.ps1')
$password = $null
try {
    Assert-VicaXray $Root
    if (@(Get-NetTCPConnection -State Listen -LocalPort 17890 -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Port occupied. Close the current session; no process will be stopped.' }
    Write-Host 'Authenticated fetch: working vault HWID + INCY/3.0.28, through a contained Xray SOCKS5h tunnel. No direct fallback. No F: required.'
    $password = Read-Host 'Vault passphrase (hidden)' -AsSecureString
    $result = Invoke-VaultRefresh -Root $Root -Password $password -CheckOnly:(-not $Apply)
    Write-Host ('PASS: supported=' + $result.supported + '; skipped=' + $result.skipped)
    if ($Apply) {
        Write-Host ('UPDATED. Encrypted previous version: ' + $result.backup)
    } else { Write-Host 'CHECK ONLY: vault unchanged. Candidate passed policy and native validation.' }
} finally { if ($password) { $password.Dispose() }; $result = $null }
