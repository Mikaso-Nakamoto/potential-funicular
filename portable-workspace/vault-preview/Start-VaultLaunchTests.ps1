#requires -Version 5.1
[CmdletBinding()]
param([string]$XrayExe = '')
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Use 64-bit Windows PowerShell 5.1.' }
$installReport = Join-Path $PSScriptRoot 'vault-launch-install-report.txt'
try {
    & (Join-Path $PSScriptRoot 'Install-VaultDependency.ps1')
    [IO.File]::WriteAllText($installReport,'PASS: official MSVC dependency installed; inspect the two test reports for integration results.')
} catch {
    [IO.File]::WriteAllText($installReport,('STOP: dependency installation failed; no tests started.' + [Environment]::NewLine + $_.Exception.Message))
    throw
}
$ps = Join-Path $PSHOME 'powershell.exe'
if ($XrayExe) {
    & $ps -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Test-XrayPipe.ps1') -XrayExe $XrayExe
} else {
    & $ps -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Test-XrayPipe.ps1')
}
if ($LASTEXITCODE -ne 0) { throw 'STOP: transport tests failed. Send xray-pipe-test-report.txt; integration was not started.' }
& $ps -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Test-VaultLaunch.ps1')
if ($LASTEXITCODE -ne 0) { throw 'STOP: vault launcher integration tests failed. Send vault-launch-test-report.txt.' }
Write-Host 'PASS: implemented synthetic tests completed. Not authorization to migrate or remove the plaintext configuration.' -ForegroundColor Green
