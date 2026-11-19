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
$piCmd = "$ROOT\npm-global\pi.cmd"
$piCli = "$ROOT\npm-global\node_modules\@earendil-works\pi-coding-agent\dist\bundle\cli.js"
if (-not (Test-Path $piCmd) -and -not (Test-Path $piCli)) {
  throw "pi-coding-agent не установился. Проверьте сеть/антивирус. Ожидался $piCmd (или dist\bundle\cli.js)"
}

# -------------------------------------------------- Python + skillbridge ---
Step 'Выбор Python и сборка venv'

# Проверка кандидата: возвращает "3.14", если интерпретатор рабочий и >= 3.10, иначе $null.
# Тонкость: при $ErrorActionPreference='Stop' любой вывод в stderr от native-команды
# (например, "py -3.12" когда 3.12 не установлен) валит скрипт — поэтому локально
# переключаемся на 'Continue' и читаем stdout+stderr вместе, а версию ищем регуляркой.
function Test-Py([string]$Exe, [string[]]$Prefix) {
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $lines = @()
  try {
    $path = $null
    if (Test-Path -LiteralPath $Exe) {
      $path = $Exe
    } else {
      $found = Get-Command $Exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($found) { if ($found.Path) { $path = $found.Path } else { $path = $found.Source } }
    }
    if (-not $path) { $ErrorActionPreference = $prevEap; return $null }
    $a = @($Prefix) + @('-c', 'import sys;print("%d.%d" % sys.version_info[:2])')
    $lines = @(& $path @a 2>&1 | ForEach-Object { "$_" })
  } catch {
    $lines = @()
  }
  $ErrorActionPreference = $prevEap
  foreach ($l in $lines) {
    $t = ("$l").Trim()
    if ($t -match '^3\.(\d+)$') {
      if ([int]$Matches[1] -ge 10) { return $t }
      return $null
    }
  }
  return $null
}

# 3.12/3.13 — самая проверенная связка с mcp/pydantic; 3.14 берём последней из «py -3».
# Последние кандидаты — обход типовых мест установки на случай, если PATH не настроен.
$cands = @()
if ($env:PYTHON) { $cands += [pscustomobject]@{ Exe = $env:PYTHON; Args = @(); Label = 'PYTHON' } }
$cands += [pscustomobject]@{ Exe = 'py';      Args = @('-3.12'); Label = 'py -3.12' }
$cands += [pscustomobject]@{ Exe = 'py';      Args = @('-3.13'); Label = 'py -3.13' }
$cands += [pscustomobject]@{ Exe = 'py';      Args = @('-3');    Label = 'py -3' }
$cands += [pscustomobject]@{ Exe = 'python';  Args = @();        Label = 'python' }
$cands += [pscustomobject]@{ Exe = 'python3'; Args = @();        Label = 'python3' }
foreach ($g in @("$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe",
                 "C:\Python3*\python.exe",
                 "$env:ProgramFiles\Python3*\python.exe")) {
  foreach ($f in @(Get-ChildItem -Path $g -ErrorAction SilentlyContinue)) {
    $cands += [pscustomobject]@{ Exe = $f.FullName; Args = @(); Label = $f.FullName }
  }
}

$pyExe = $null; $pyPrefix = @(); $pyVer = $null
foreach ($c in $cands) {
  $v = Test-Py $c.Exe $c.Args
  if ($v) {
    $pyExe = $c.Exe; $pyPrefix = $c.Args; $pyVer = $v
    Write-Host "  Python $v  ($($c.Label))" -ForegroundColor Green
    break
  }
  Write-Host "    $($c.Label): не подошёл" -ForegroundColor DarkGray
}
if (-not $pyExe) {
  throw @"
Python 3.10+ не найден ни одним способом.
  Проверьте в этом же окне:   py -3 --version
  Если версия печатается — пришлите мне вывод, доработаю определение.
  Если нет — установите:      winget install -e --id Python.Python.3.12
"@
}
if ($pyVer -match '^3\.(1[4-9])$') {
  Warn "Python $pyVer очень свежий: если pip ниже упадёт на сборке колёс (pydantic), поставьте 3.12 и удалите venv."
}

if (Test-Path "$ROOT\venv\Scripts\python.exe") {
  $venvVer = '?'
  try {
    $prevEap2 = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $venvVer = ((& "$ROOT\venv\Scripts\python.exe" -c 'import sys;print("%d.%d" % sys.version_info[:2])' 2>&1 |
                 ForEach-Object { "$_" }) -join '').Trim()
    $ErrorActionPreference = $prevEap2
  } catch { }
  Write-Host "  venv уже есть (Python $venvVer) — переиспользую"
} else {
  $prevEap3 = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & $pyExe @pyPrefix -m venv "$ROOT\venv"
  $venvRc = $LASTEXITCODE
  $ErrorActionPreference = $prevEap3
  if ($venvRc -ne 0 -or -not (Test-Path "$ROOT\venv\Scripts\python.exe")) {
    throw "Не удалось создать venv (код $venvRc). Для python.org-сборки нужен модуль venv (обычно он есть)."
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
