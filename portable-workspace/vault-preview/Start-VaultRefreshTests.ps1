#requires -Version 5.1
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Use 64-bit Windows PowerShell 5.1.' }
& (Join-Path $PSScriptRoot 'Install-VaultDependency.ps1')
& (Join-Path $PSHOME 'powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Test-XrayPipe.ps1')
if ($LASTEXITCODE -ne 0) { throw 'STOP: transport regression failed. Send xray-pipe-test-report.txt. Refresh tests were not started.' }
& (Join-Path $PSHOME 'powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Test-VaultRefresh.ps1')
if ($LASTEXITCODE -ne 0) { throw 'STOP: synthetic refresh tests failed. Send vault-refresh-test-report.txt. No real vault was used.' }
Write-Host 'PASS: implemented synthetic refresh tests completed. Do not use refresh on the working vault yet.' -ForegroundColor Green
