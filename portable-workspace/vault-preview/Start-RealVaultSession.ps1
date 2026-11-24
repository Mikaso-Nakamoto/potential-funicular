#requires -Version 5.1
[CmdletBinding()]
param([string]$InstalledRoot = 'Z:\Iran\Browser\Runtime', [switch]$ConfirmOfficialInstalledBinaries)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Use 64-bit Windows PowerShell 5.1.' }
if (-not $ConfirmOfficialInstalledBinaries) { throw 'Confirm official installed Xray/LibreWolf sources before starting.' }
& (Join-Path $PSScriptRoot 'Install-VaultDependency.ps1')
& (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Test-RealVaultSession.ps1') -InstalledRoot $InstalledRoot -ConfirmOfficialInstalledBinaries
if ($LASTEXITCODE -ne 0) { throw 'Real session test stopped. Send real-vault-session-report.txt. Do not terminate unknown processes.' }
