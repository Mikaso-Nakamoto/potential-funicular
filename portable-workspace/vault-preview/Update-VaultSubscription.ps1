#requires -Version 5.1
[CmdletBinding()]
param([string]$Root = 'Z:\Iran\Browser\Working-Vault-Preview\WorkingRuntime', [switch]$ConfirmLiveRefresh)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Use 64-bit Windows PowerShell 5.1.' }
if (-not $ConfirmLiveRefresh) { throw 'Explicit ConfirmLiveRefresh required. Run this package synthetic tests first.' }
. (Join-Path $PSScriptRoot 'VaultRefresh.Common.ps1')
$password = $null; $result = $null
try {
    $Root = Get-Workspace $Root
    if (-not (Test-Path -LiteralPath (Join-Path $Root 'private\workspace.vault') -PathType Leaf)) { throw 'Existing encrypted vault required. No plaintext fallback.' }
    if (@(Get-NetTCPConnection -State Listen -LocalPort 17890 -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Port 17890 is occupied. Close the active session first; no process will be stopped.' }
    if (@(Get-CimInstance Win32_Process -Filter "Name = 'librewolf.exe'" -ErrorAction Stop).Count -gt 0) { throw 'Close all LibreWolf instances before refresh.' }
    if ((Get-FileHash -LiteralPath (Join-Path $Root 'Xray\xray.exe') -Algorithm SHA256).Hash -ne '1ca7a2cf61ba2c5d20b21a80d405b57933939751081cb289f07bd8ddf7cc3185') { throw 'Xray differs from the previously tested binary. Review required; no bypass.' }
    Write-Warning 'LIVE REQUEST: uses URL and existing x-hwid stored in vault. Fetch goes over the current Windows connection/system proxy, NOT this browser tunnel. No redirect or plaintext fallback.'
    Write-Host 'The existing node is retained only for a unique full outbound match. Otherwise choose a node number; private labels/hosts are not printed.'
    $password = Read-Host 'Vault passphrase (hidden)' -AsSecureString
    $result = Invoke-VaultRefresh -Root $Root -Password $password
    Write-Host ('PASS: encrypted vault refreshed; supported=' + $result.supported + '; skipped=' + $result.skipped + '; previous node retained=' + $result.preserved) -ForegroundColor Green
    Write-Host ('Encrypted previous version: ' + $result.backup)
    Write-Warning 'Native -test is not remote connectivity verification. No browser/tunnel launched. Keep the encrypted backup; do not run the legacy updater on this Runtime.'
} finally {
    if ($password) { $password.Dispose() }
    $result = $null
}
