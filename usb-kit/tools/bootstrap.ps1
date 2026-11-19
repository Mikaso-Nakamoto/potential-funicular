#requires -version 5
<# Одноразовая сборка стека под Windows. Исполни:
   powershell -ExecutionPolicy Bypass -File tools\bootstrap.ps1 [# категории скиллов...] #>
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# Старые Windows/PowerShell 5.1 по умолчанию любят TLS 1.0 — nodejs.org/pypi требуют 1.2+
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
# Русский текст в консоли: файл в UTF-8 (с BOM), консоль тоже переводим в UTF-8
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$ROOT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Warn($msg) { Write-Host "  ! $msg" -ForegroundColor Yellow }

# ------------------------------------------------------------- Node.js -----
if (-not (Test-Path "$ROOT\node\node.exe")) {
  Step 'Установка портативного Node.js'
  $arch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
  if ($env:NODE_VERSION) { $ver = $env:NODE_VERSION } else {
    $idx = Invoke-RestMethod 'https://nodejs.org/dist/index.json'
    $ver = ($idx | Where-Object lts | Select-Object -First 1).version
  }
  $zip = "$env:TEMP\node-$ver-win-$arch.zip"
  Invoke-WebRequest "https://nodejs.org/dist/$ver/node-$ver-win-$arch.zip" -OutFile $zip
  Expand-Archive $zip "$ROOT\node-tmp" -Force
  Move-Item "$ROOT\node-tmp\node-$ver-win-$arch" "$ROOT\node" -Force
  Remove-Item -Recurse -Force "$ROOT\node-tmp", $zip
}
& "$ROOT\node\node.exe" --version
if (-not (Test-Path "$ROOT\node\node.exe")) { throw "Node.js не распаковался в $ROOT\node" }

$env:PI_STICK_ROOT = $ROOT
$env:NPM_CONFIG_PREFIX = "$ROOT\npm-global"
$env:NPM_CONFIG_CACHE  = "$ROOT\tmp\npm-cache"
New-Item -ItemType Directory -Force "$ROOT\tmp","$ROOT\sessions","$ROOT\config\skills","$ROOT\npm-global" | Out-Null

# ----------------------------------------------------------------- Pi ------
Step 'Установка pi-coding-agent'
& "$ROOT\node\npm.cmd" install -g --ignore-scripts --no-fund --no-audit '@earendil-works/pi-coding-agent'
$piJs = "$ROOT\npm-global\node_modules\@earendil-works\pi-coding-agent\bin\pi.js"
if (-not (Test-Path $piJs)) {
  throw "pi-coding-agent не установился. Проверьте сеть/антивирус. Ожидался файл: $piJs"
}

# -------------------------------------------------- Python + skillbridge ---
Step 'Выбор Python и сборка venv'

# Возвращает "3.12" если интерпретатор рабочий и >= 3.10, иначе $null
function Get-PyVersion([string]$Cmd, [string[]]$Prefix) {
  $a = @($Prefix) + @('-c', 'import sys;print("%d.%d" % sys.version_info[:2])')
  try { $o = & $Cmd @a 2>$null } catch { return $null }
  if ($LASTEXITCODE -ne 0 -or -not $o) { return $null }
  $v = ("$o" -split "`r?`n")[0].Trim()
  if ($v -match '^(\d+)\.(\d+)$' -and [int]$Matches[1] -eq 3 -and [int]$Matches[2] -ge 10) { return $v }
  return $null
}

# 3.12/3.13 — самая проверенная связка с mcp/pydantic; 3.14 берём последней из «py -3»
$cands = @(
  @{ Cmd = 'py';     Prefix = @('-3.12') },
  @{ Cmd = 'py';     Prefix = @('-3.13') },
  @{ Cmd = 'py';     Prefix = @('-3') },
  @{ Cmd = 'python'; Prefix = @() }
)
if ($env:PYTHON) { $cands = @(@{ Cmd = $env:PYTHON; Prefix = @() }) + $cands }

$pyCmd = $null; $pyPrefix = @(); $pyVer = $null
foreach ($c in $cands) {
  $v = Get-PyVersion $c.Cmd $c.Prefix
  if ($v) { $pyCmd = $c.Cmd; $pyPrefix = $c.Prefix; $pyVer = $v; break }
}
if (-not $pyCmd) {
  throw "Python 3.10+ не найден. Установите: winget install -e --id Python.Python.3.12  (или python.org, галочка 'Add to PATH')"
}
Write-Host "  Python $pyVer ($pyCmd $($pyPrefix -join ' '))"
if ($pyVer -match '^3\.(1[4-9])$') {
  Warn "Python $pyVer очень свежий: если pip ниже упадёт на сборке колёс (pydantic и т.п.), поставьте 3.12: winget install -e --id Python.Python.3.12"
}

if (Test-Path "$ROOT\venv\Scripts\python.exe") {
  $venvVer = (& "$ROOT\venv\Scripts\python.exe" -c 'import sys;print("%d.%d" % sys.version_info[:2])') -join ''
  Write-Host "  venv уже есть (Python $venvVer) — переиспользую"
} else {
  & $pyCmd @pyPrefix -m venv "$ROOT\venv"
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path "$ROOT\venv\Scripts\python.exe")) {
    throw "Не удалось создать venv. Для python.org-сборки нужен модуль venv (обычно он есть)."
  }
}

$vpy = "$ROOT\venv\Scripts\python.exe"
& $vpy -m pip install --quiet --upgrade pip
& $vpy -m pip install --quiet -r "$ROOT\skillbridge\requirements.txt"
if ($LASTEXITCODE -ne 0) {
  throw "pip не поставил зависимости (mcp, PyYAML). Если ошибка про сборку колёс/Rust — установите Python 3.12 и удалите папку venv, затем повторите."
}
if ($env:FULL -eq '1') { & $vpy -m pip install --quiet skillware }
& $vpy -m pip install --quiet --force-reinstall --no-deps "$ROOT\skillbridge"
$sbExe = "$ROOT\venv\Scripts\skillbridge.exe"
if (Test-Path $sbExe) { & $sbExe --root "$ROOT\skills" --selftest }
else { & $vpy -m skillbridge --root "$ROOT\skills" --selftest }
if ($LASTEXITCODE -ne 0) { throw "skillbridge selftest не прошёл — см. вывод выше." }

# -------------------------------------------------------- Скиллы Pi --------
Step 'Синхронизация маркдаун-скиллов'
& powershell -ExecutionPolicy Bypass -File "$ROOT\tools\sync-skills.ps1" @args

Step 'Готово. Подключите модель: bin\run-pi.bat auth login <provider> --api-key'
