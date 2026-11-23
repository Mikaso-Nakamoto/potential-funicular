#requires -Version 5.1
[CmdletBinding()]
param([string]$Root = '')
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Join-Path (Split-Path -Parent $PSScriptRoot) 'Runtime' }
$Root = [IO.Path]::GetFullPath($Root)
$ps = Join-Path $PSHOME 'powershell.exe'
& $ps -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Test-WorkspaceJob.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Job lifecycle self-check failed. Real Runtime was not started. See job-lifecycle-report.txt.' }
& (Join-Path $PSScriptRoot 'Workspace-Console.ps1') -Root $Root
