#requires -Version 5.1
# One command: an installation failure stops this script before the tests.
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5) {
    throw 'Use 64-bit Windows PowerShell 5.1.'
}
$report = Join-Path $PSScriptRoot 'vault-install-report.txt'
try {
    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'lib')) {
        throw 'This folder already has lib. Use a new empty test folder; no previous dependency will be reused.'
    }
    & (Join-Path $PSScriptRoot 'Install-VaultDependency.ps1')
    [IO.File]::WriteAllText($report, 'PASS: official MSVC dependency installed and import gate passed. See vault-test-report.txt for tests.')
} catch {
    [IO.File]::WriteAllText($report, ('STOP: dependency installation failed. No tests started.' + [Environment]::NewLine + $_.Exception.Message))
    Write-Host 'STOP. No tests started. Send vault-install-report.txt. No Runtime access.' -ForegroundColor Red
    throw
}
& (Join-Path $PSScriptRoot 'Run-VaultTests.ps1')
