#requires -version 5
<# Одноразовая сборка стека под Windows. Исполни:
   powershell -ExecutionPolicy Bypass -File tools\bootstrap.ps1 [# категории скиллов...] #>
$ErrorActionPreference = 'Stop'
$ROOT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

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

$env:PI_STICK_ROOT = $ROOT
$env:NPM_CONFIG_PREFIX = "$ROOT\npm-global"
$env:NPM_CONFIG_CACHE  = "$ROOT\tmp\npm-cache"
New-Item -ItemType Directory -Force "$ROOT\tmp","$ROOT\sessions","$ROOT\config\skills","$ROOT\npm-global" | Out-Null

# ----------------------------------------------------------------- Pi ------
Step 'Установка pi-coding-agent'
& "$ROOT\node\npm.cmd" install -g --ignore-scripts --no-fund --no-audit '@earendil-works/pi-coding-agent'

# -------------------------------------------------- Python + skillbridge ---
Step 'Сборка venv и установка skillbridge'
$py = if (Get-Command py -ErrorAction SilentlyContinue) { 'py','-3' } else { 'python',@() }
& $py[0] $py[1] -m venv "$ROOT\venv"
& "$ROOT\venv\Scripts\pip.exe" install --quiet --upgrade pip
& "$ROOT\venv\Scripts\pip.exe" install --quiet -r "$ROOT\skillbridge\requirements.txt"
if ($env:FULL -eq '1') { & "$ROOT\venv\Scripts\pip.exe" install --quiet skillware }
& "$ROOT\venv\Scripts\pip.exe" install --quiet --force-reinstall --no-deps "$ROOT\skillbridge"
& "$ROOT\venv\Scripts\skillbridge.exe" --root "$ROOT\skills" --selftest

# -------------------------------------------------------- Скиллы Pi --------
Step 'Синхронизация маркдаун-скиллов'
& powershell -ExecutionPolicy Bypass -File "$ROOT\tools\sync-skills.ps1" @args

Step 'Готово. Подключите модель: bin\run-pi.bat auth login <provider> --api-key'
