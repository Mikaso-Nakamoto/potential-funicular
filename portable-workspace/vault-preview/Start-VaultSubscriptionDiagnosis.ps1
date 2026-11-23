#requires -Version 5.1
[CmdletBinding()]
param([string]$Root = 'Z:\Iran\Browser\Working-Vault-Preview\WorkingRuntime')
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Use 64-bit Windows PowerShell 5.1.' }
$ps = Join-Path $PSHOME 'powershell.exe'
& $ps -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Test-VaultRefreshDiagnostics.ps1')
if ($LASTEXITCODE -ne 0) { throw 'STOP: synthetic diagnostic checks failed; no live fetch was started.' }
& (Join-Path $PSScriptRoot 'Install-VaultDependency.ps1')
& $ps -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Diagnose-VaultSubscription.ps1') -Root $Root
if ($LASTEXITCODE -ne 0) { throw 'Read-only diagnosis stopped. Do not send secrets or raw server response.' }
