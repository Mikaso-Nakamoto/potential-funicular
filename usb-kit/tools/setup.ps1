#requires -version 5
<# Единая точка входа для Windows.
   Два режима сборки:
     1) двухэтапный (по умолчанию) — сборка в C:\usb-kit-build, затем перенос на носитель
        одним заходом. Нужен потому, что npm/pip создают ~20 тысяч мелких файлов, и на
        флешках USB 2.0 это занимает часы вместо минут.
     2) на месте — если запускаем с обычного диска (ответ n).
   Русский текст здесь, а не в .bat: SETUP.bat чисто ASCII и лечит BOM перед запуском. #>
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$ROOT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
try { $Host.UI.RawUI.WindowTitle = "USB-KIT: $ROOT" } catch {}

function Line { Write-Host ('-' * 64) -ForegroundColor DarkGray }
function Step($m) { Write-Host ''; Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  $m" -ForegroundColor Yellow }
function Bad($m)  { Write-Host "  $m" -ForegroundColor Red }

$piCmd = "$ROOT\npm-global\pi.cmd"
$piCli = "$ROOT\npm-global\node_modules\@earendil-works\pi-coding-agent\dist\bundle\cli.js"
$sbExe = "$ROOT\venv\Scripts\skillbridge.exe"
$vpy   = "$ROOT\venv\Scripts\python.exe"
$buildRoot = "$env:SystemDrive\usb-kit-build"

Line
Write-Host '  USB-KIT: переносной агентный стек (Pi + skillbridge)' -ForegroundColor Cyan
Write-Host "  Папка: $ROOT"
Line

$rebuild = $true
if ((Test-Path "$ROOT\node\node.exe") -and (Test-Path $sbExe) -and ((Test-Path $piCmd) -or (Test-Path $piCli))) {
  Ok 'Стек уже собран (node + pi + venv на месте).'
  $a = Read-Host '  Пересобрать/обновить? [y/N]'
  if ($a -notmatch '^\s*[yYдД]') { $rebuild = $false }
}

if ($rebuild) {
  Step 'Как собираем'
  Write-Host '  npm и pip создают ~20 000 мелких файлов. На диске C: это 5-10 минут,'
  Write-Host '  на флешке USB 2.0 — часы. Поэтому по умолчанию:'
  Write-Host "     1) сборка в $buildRoot  (быстро)"
  Write-Host '     2) перенос готового стека на флешку — одним заходом'
  Write-Host '     3) правка путей и самотест уже на флешке'
  Write-Host ''
  Write-Host '  Если запускаете с обычного диска (не с флешки) — ответьте n.'
  $mode = Read-Host '  Собирать через C: и перенести? [Y/n]'
  $twoStage = $mode -notmatch '^\s*[nNнН]'

  if ($twoStage) {
    try {
      $freeGb = ([IO.DriveInfo](Split-Path -Qualifier $env:SystemDrive)).AvailableFreeSpace / 1073741824
      Write-Host ('  Свободно на {0} {1:N1} ГБ' -f (Split-Path -Qualifier $env:SystemDrive), $freeGb)
      if ($freeGb -lt 1.5) {
        Warn 'Свободного места меньше 1.5 ГБ — собираю на месте (медленнее).'
        $twoStage = $false
      }
    } catch {
      Warn "Не удалось проверить свободное место на $env:SystemDrive — собираю на месте."
      $twoStage = $false
    }
  }

  try {
    if ($twoStage) {
      if (Test-Path $buildRoot) {
        $a = Read-Host "  $buildRoot уже есть. Удалить его и начать заново? [Y/n]"
        if ($a -match '^\s*[nNнН]') { $buildRoot = $buildRoot + '-' + (Get-Date -Format 'HHmmss') }
        else { Remove-Item -Recurse -Force $buildRoot -ErrorAction SilentlyContinue }
      }

      Step "Копирую исходники в $buildRoot"
      $null = & robocopy $ROOT $buildRoot /E /R:1 /W:1 /NFL /NDL /NJH /NP `
                /XD "$ROOT\node" "$ROOT\venv" "$ROOT\npm-global" "$ROOT\tmp" "$ROOT\sessions" /XF "*.log"
      if ($LASTEXITCODE -ge 8) { throw "robocopy (копирование в $buildRoot) вернул код $LASTEXITCODE" }

      Step 'Сборка на локальном диске (5-10 минут)'
      & "$buildRoot\tools\bootstrap.ps1"

      Step 'Перенос готового стека на флешку'
      Write-Host '  Единственный медленный шаг: ~20 000 файлов, но одним заходом.'
      Write-Host '  Не отключайте флешку. Прогресса не будет — это нормально, оно идёт.'
      $null = & robocopy $buildRoot $ROOT /E /R:1 /W:1 /NFL /NDL /NJH /NP /XD "$buildRoot\tmp"
      if ($LASTEXITCODE -ge 8) { throw "robocopy (перенос на флешку) вернул код $LASTEXITCODE" }

      Step 'Правка путей и самотест на флешке'
      & $vpy -m pip install --quiet --force-reinstall --no-deps "$ROOT\skillbridge"
      & $vpy -m skillbridge --root "$ROOT\skills" --selftest
      if ($LASTEXITCODE -ne 0) { throw 'Самотест моста на флешке не прошёл (см. вывод выше).' }
      Write-Host ''
      Ok "Копия сборки осталась в $buildRoot — можно удалить, освободит ~600 МБ."
    }
    else {
      Step 'Сборка на месте'
      & "$ROOT\tools\bootstrap.ps1"
    }
  }
  catch {
    Write-Host ''
    Bad "[ОШИБКА] $($_.Exception.Message)"
    Write-Host '  Частые причины: нет интернета/мешает прокси, антивирус удалил node.exe'
    Write-Host '  или python.exe, Python старше 3.10 или не установлен, мало места на диске.'
    Write-Host '  Скопируйте весь вывод этого окна и пришлите мне — разберём.'
    exit 1
  }

  if (-not ((Test-Path $piCmd) -or (Test-Path $piCli))) {
    Bad '[ОШИБКА] pi-coding-agent не установился (нет pi.cmd и dist\bundle\cli.js).'
    exit 1
  }
  Write-Host ''
  Ok '[OK] Сборка завершена и лежит на носителе.'
}

Write-Host ''
Line
Write-Host '  Дальше:' -ForegroundColor Cyan
Write-Host '   1) подключить модель один раз своим API-ключом:'
Write-Host "        `"$ROOT\bin\run-pi.bat`" auth login anthropic --api-key"
Write-Host '   2) запускать агента:'
Write-Host "        `"$ROOT\bin\run-pi.bat`""
Write-Host '   3) после работы на чужом хосте — почистить кэши:'
Write-Host "        `"$ROOT\tools\wipe-temp.bat`""
Line
if (-not (Test-Path "$ROOT\config\auth.json")) {
  Warn 'Ключ модели пока не сохранён — сначала auth login (шаг 1).'
}
Write-Host ''
$run = Read-Host '  Запустить Pi сейчас? [y/N]'
if ($run -match '^\s*[yYдД]') { & "$ROOT\bin\run-pi.bat" }
exit 0
