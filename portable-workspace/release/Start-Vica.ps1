#requires -Version 5.1
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Bootstrap.Common.ps1')
Assert-VicaPlatform
$package = Split-Path -Parent $PSScriptRoot
$root = Join-Path $package 'Runtime'
$temp = Join-Path $package '.tmp'; New-Item -ItemType Directory -Path $temp -Force | Out-Null
$env:TEMP = $temp; $env:TMP = $temp
Initialize-VicaDependency $package (Join-Path (Split-Path -Parent $package) 'VIC-A-Updated')
$ps = Join-Path $PSHOME 'powershell.exe'
& $ps -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Test-ContainedSession.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Containment check failed. No real operations enabled.' }
$language = 'ru'; $style = 'eye'
. (Join-Path $package 'VicA.Intro.ps1')
function Splash {
    try { Show-VicAIntro -Style $style -Language $language }
    catch { Write-Host 'VIC-A | animation unavailable; opening console.' -ForegroundColor Cyan }
}
function T([string]$Ru,[string]$En) { if ($language -eq 'ru') { return $Ru }; return $En }
Splash
while ($true) {
    Clear-Host
    Write-Host '  ╔══════════════════════════════════════════════════════════╗' -ForegroundColor DarkCyan
    Write-Host '  ║                       V I C - A                        ║' -ForegroundColor Cyan
    Write-Host '  ╚══════════════════════════════════════════════════════════╝' -ForegroundColor DarkCyan
    $ready = Test-Path -LiteralPath (Join-Path $root 'private\workspace.vault')
    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort 17890 -ErrorAction SilentlyContinue)
    $state = T 'НЕ НАСТРОЕНО' 'NOT CONFIGURED'
    if ($ready) { $state = T 'ПАРОЛЬ + РЕЗЕРВНАЯ ФРАЗА' 'PASSWORD + RECOVERY' }
    Write-Host ('  VAULT  : ' + $state) -ForegroundColor Yellow
    Write-Host ('  SOCKS  : ' + $listeners.Count + (T ' слушателей; это не проверка доступа в Интернет' ' listeners; not proof of Internet connectivity'))
    Write-Host ('  ROOT   : ' + $root)
    Write-Host ''
    Write-Host ('  1  ' + (T 'Открыть браузер' 'Open browser')) -ForegroundColor Green
    Write-Host ('  2  ' + (T 'Проверить подписку без записи' 'Check subscription without writes'))
    Write-Host ('  3  ' + (T 'Обновить подписку' 'Update subscription'))
    Write-Host ('  4  ' + (T 'Проверить сейф и конфиг без сети' 'Validate vault/config offline'))
    Write-Host ('  5  ' + (T 'Восстановить / сменить пароль по 10 словам' 'Recover / change password with ten words'))
    Write-Host ('  6  ' + (T 'Первоначальная настройка и импорт рабочей копии' 'Initial setup and import working copy')) -ForegroundColor Yellow
    Write-Host ('  L  ' + (T 'Язык RU / EN' 'Language RU / EN'))
    Write-Host ('  I  ' + (T 'Заставка: глаз / архив' 'Intro: eye / archive'))
    Write-Host ('  0  ' + (T 'Выход' 'Exit'))
    Write-Host ''
    $choice = Read-Host 'VIC-A >'
    $code = 0
    if ($choice -eq '0') { return }
    if ($choice -in @('l','L')) { if ($language -eq 'ru') { $language = 'en' } else { $language = 'ru' }; continue }
    if ($choice -in @('i','I')) { if ($style -eq 'eye') { $style = 'archive' } else { $style = 'eye' }; Splash; continue }
    if ($choice -in @('1','2','3','4','5') -and -not $ready) { Write-Warning (T 'Сначала пункт 6. Старые данные не удаляются.' 'Use option6 first. Originals are not deleted.'); [void](Read-Host 'Enter'); continue }
    switch ($choice) {
        '1' { & $ps -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Start-VicaSession.ps1') -Root $root; $code = $LASTEXITCODE }
        '2' { & $ps -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Update-VicaSubscription.ps1') -Root $root; $code = $LASTEXITCODE }
        '3' { & $ps -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Update-VicaSubscription.ps1') -Root $root -Apply; $code = $LASTEXITCODE }
        '4' { & $ps -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Start-VicaSession.ps1') -Root $root -ValidateOnly; $code = $LASTEXITCODE }
        '5' { & $ps -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Reset-VicaPassword.ps1') -Root $root; $code = $LASTEXITCODE }
        '6' { & $ps -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Initialize-Vica.ps1') -Root $root; $code = $LASTEXITCODE }
        default { continue }
    }
    if ($code -ne 0) { Write-Warning (T 'Операция остановлена. Не присылайте пароли, слова или конфиги.' 'Operation stopped. Do not send credentials or configs.') }
    [void](Read-Host (T 'Enter — вернуться в меню' 'Enter — return to menu'))
}
