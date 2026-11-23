#requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('Prepare','Validate')][string]$Action = 'Validate', [string]$InstalledRoot = 'Z:\Iran\Browser\Runtime', [switch]$ConfirmOfficialInstalledBinaries)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Use 64-bit Windows PowerShell 5.1.' }
$ps = Join-Path $PSHOME 'powershell.exe'
if ($Action -eq 'Prepare') {
    if (-not $ConfirmOfficialInstalledBinaries) { throw 'Confirm official installed binary sources first.' }
    & (Join-Path $PSScriptRoot 'Install-VaultDependency.ps1')
    & $ps -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Prepare-WorkingVault.ps1') -InstalledRoot $InstalledRoot -ConfirmOfficialInstalledBinaries
} else {
    $directory = Split-Path -Parent $PSScriptRoot
    & $ps -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $directory 'Start-VaultWorkspace.ps1') -Root (Join-Path $directory 'WorkingRuntime') -ValidateOnly
}
if ($LASTEXITCODE -ne 0) { throw 'STOP: working vault step failed. Do not send passwords, URLs, config or vault contents.' }
