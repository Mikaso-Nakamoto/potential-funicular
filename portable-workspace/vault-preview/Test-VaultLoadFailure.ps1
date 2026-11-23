#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ToolDirectory,
      [Parameter(Mandatory=$true)][ValidateSet('dll','manifest','source','gate','pe')][string]$Case)
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $ToolDirectory 'Vault.Common.ps1')
    $expected = switch ($Case) {
        'dll' { 'Crypto dependency integrity check failed.' }
        'manifest' { 'Crypto dependency integrity check failed.' }
        'source' { 'Crypto source integrity check failed.' }
        'gate' { 'Vault support integrity check failed.' }
        'pe' { 'Vault support integrity check failed.' }
    }
    $message = $null
    try { Initialize-VaultCrypto } catch { $message = $_.Exception.Message }
    if ($message -cne $expected) { throw 'Mutation was not rejected at the expected integrity gate.' }
    Write-Host ('PASS: isolated ' + $Case + ' integrity rejection')
    exit 0
} catch {
    Write-Host ('FAIL: isolated ' + $Case + ' integrity rejection')
    exit 1
}
