#requires -Version 5.1
[CmdletBinding()]
param([string]$Root = '',[string]$ExistingSupport = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Bootstrap.Common.ps1')
Assert-VicaPlatform
$package = Split-Path -Parent $PSScriptRoot
$installation = Split-Path -Parent $package
if (-not $Root) { $Root = Join-Path $installation 'Working-Vault-Preview\WorkingRuntime' }
if (-not $ExistingSupport) { $ExistingSupport = Join-Path $installation 'Working-Vault-Preview' }
$Root = [IO.Path]::GetFullPath($Root)
if (-not (Test-Path -LiteralPath (Join-Path $Root 'private\workspace.vault') -PathType Leaf)) { throw 'Existing working encrypted vault required. No creation, migration or plaintext fallback.' }
$ps = Join-Path $PSHOME 'powershell.exe'
Write-Host 'Checking contained native transport before enabling real sessions...'
& $ps -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Test-ContainedSession.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Containment self-check failed. No real session/update enabled. Keep the working old package.' }
Initialize-VicaDependency $package $ExistingSupport
# Every operation uses a fresh process: no stale compiled helper or secret documents retained by the menu.
while ($true) {
    Write-Host ''
    Write-Host 'VIC-A | зашифрованная рабочая среда / encrypted workspace' -ForegroundColor Cyan
    Write-Host ('Runtime: ' + $Root)
    Write-Host '1. Браузер / Browser'
    Write-Host '2. Проверить подписку без записи / Check subscription'
    Write-Host '3. Обновить подписку с подтверждением / Update subscription'
    Write-Host '4. Проверить vault и конфиг без сети / Validate offline'
    Write-Host '5. Проверить изоляцию процессов без Runtime и сети / Self-check'
    Write-Host '0. Выход / Exit'
    $choice = Read-Host '>'
    $code = 0
    switch ($choice) {
        '0' { return }
        '1' { & $ps -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Start-VicaSession.ps1') -Root $Root; $code = $LASTEXITCODE }
        '2' { & $ps -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Update-VicaSubscription.ps1') -Root $Root; $code = $LASTEXITCODE }
        '3' { & $ps -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Update-VicaSubscription.ps1') -Root $Root -Apply; $code = $LASTEXITCODE }
        '4' { & $ps -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Start-VicaSession.ps1') -Root $Root -ValidateOnly; $code = $LASTEXITCODE }
        '5' { & $ps -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Test-ContainedSession.ps1'); $code = $LASTEXITCODE }
        default { Write-Host 'Choose 0-5.'; continue }
    }
    if ($code -ne 0) { Write-Warning 'Operation stopped. Do not send passwords, URLs, HWID, vault or raw configs.' }
    [void](Read-Host 'Enter to return to menu')
}
