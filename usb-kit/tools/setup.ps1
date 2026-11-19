#requires -version 5
<# Единая точка входа для Windows: понятный интерфейс + запуск bootstrap.
   Вызывается из SETUP.bat в корне usb-kit. Русский текст здесь, а не в .bat,
   чтобы не зависеть от кодовой страницы консоли. #>
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$ROOT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
try { $Host.UI.RawUI.WindowTitle = "USB-KIT: $ROOT" } catch {}
function Line { Write-Host ('-' * 64) -ForegroundColor DarkGray }
function Ok($m) { Write-Host "  $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  $m" -ForegroundColor Yellow }
function Bad($m) { Write-Host "  $m" -ForegroundColor Red }

$piJs  = "$ROOT\npm-global\node_modules\@earendil-works\pi-coding-agent\bin\pi.js"
$sbExe = "$ROOT\venv\Scripts\skillbridge.exe"

Line
Write-Host '  USB-KIT: переносной агентный стек (Pi + skillbridge)' -ForegroundColor Cyan
Write-Host "  Папка: $ROOT"
Line
Write-Host ''

$rebuild = $true
if ((Test-Path "$ROOT\node\node.exe") -and (Test-Path $sbExe) -and (Test-Path $piJs)) {
  Ok 'Стек уже собран (node + pi + venv на месте).'
  $ans = Read-Host '  Пересобрать/обновить? [y/N]'
  if ($ans -notmatch '^\s*[yYдД]') { $rebuild = $false }
}

if ($rebuild) {
  Write-Host ''
  Warn 'Сейчас скачается Node.js LTS (~30 МБ), установится Pi, затем пакеты моста.'
  Write-Host '  Нужен интернет. Ориентир: 2-5 минут.'
  Write-Host '  Если антивирус или SmartScreen спросит про powershell.exe / node.exe —'
  Write-Host '  разрешите: это и есть установка.'
  Write-Host ''
  try {
    & "$ROOT\tools\bootstrap.ps1"
  } catch {
    Write-Host ''
    Bad "[ОШИБКА] $($_.Exception.Message)"
    Write-Host '  Частые причины: нет интернета/мешает прокси, антивирус удалил node.exe'
    Write-Host '  или python.exe, Python старше 3.10 или не установлен.'
    Write-Host '  Скопируйте весь вывод этого окна и пришлите мне — разберём.'
    exit 1
  }
  if (-not (Test-Path $piJs)) {
    Bad '[ОШИБКА] pi-coding-agent не установился (файл pi.js отсутствует).'
    exit 1
  }
  Write-Host ''
  Ok '[OK] Сборка завершена.'
}

Write-Host ''
Line
Write-Host '  Дальше:' -ForegroundColor Cyan
Write-Host '   1) подключить модель один раз своим API-ключом:'
Write-Host "        `"$ROOT\bin\run-pi.bat`" auth login anthropic --api-key"
Write-Host '   2) запускать агента:'
Write-Host "        `"$ROOT\bin\run-pi.bat`""
Write-Host '   3) на чужом хосте после работы:'
Write-Host "        `"$ROOT\tools\wipe-temp.bat`""
Line
if (-not (Test-Path "$ROOT\config\auth.json")) {
  Warn 'Ключ модели пока не сохранён — сначала auth login (шаг 1).'
}
Write-Host ''
$run = Read-Host '  Запустить Pi сейчас? [y/N]'
if ($run -match '^\s*[yYдД]') { & "$ROOT\bin\run-pi.bat" }
exit 0
