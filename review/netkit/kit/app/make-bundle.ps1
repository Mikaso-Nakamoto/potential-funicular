# make-bundle.ps1 — собрать ПОЛНУЮ сборку (браузер + xray + скрипты) в один zip.
# Нужна, чтобы не перекачивать и не перезаписывать браузер при каждом обновлении:
# обновляешь только скрипты (маленький архив), а полную сборку делаешь этой кнопкой.
param(
    [string]$OutFile = '',
    [switch]$NoSecrets        # не класть в архив vpn\sub.txt и vpn\config.json
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$App  = $PSScriptRoot
$Root = Split-Path -Parent $App

function Say([string]$text, [string]$color = 'Gray') { Write-Host $text -ForegroundColor $color }

$exePath  = Join-Path $App 'LibreWolf\LibreWolf.exe'
$xrayPath = Join-Path $Root 'vpn\xray.exe'

Say ''
Say '=== Сборка полного архива ===' 'Cyan'
Say ''
if (Test-Path $exePath) { Say ('браузер: ' + $exePath) }
else { Say '[!] Браузер не найден (app\LibreWolf\LibreWolf.exe) — архив будет без него.' 'Yellow' }
if (Test-Path $xrayPath) { Say ('xray: ' + $xrayPath) }
else { Say '[!] Xray не найден (vpn\xray.exe) — архив будет без него.' 'Yellow' }

$hasSub = Test-Path (Join-Path $Root 'vpn\sub.txt')
$hasCfg = Test-Path (Join-Path $Root 'vpn\config.json')
if (($hasSub -or $hasCfg) -and $NoSecrets) {
    Say '[-NoSecrets] vpn\sub.txt и vpn\config.json в архив НЕ попадут: на новой флешке ключ или подписку нужно будет ввести заново.' 'Yellow'
} elseif ($hasSub -or $hasCfg) {
    Say ''
    Say '[!] В архив попадут vpn\sub.txt и vpn\config.json — это твоя подписка (URL с токеном)' 'Red'
    Say '    и ключи узлов. Такую сборку нельзя никому передавать и нельзя выкладывать в облака.' 'Red'
    Say '    Нужен архив без секретов: запусти СОБРАТЬ-СБОРКУ.bat -NoSecrets' 'Red'
}

$out = $OutFile
if (-not $out) {
    $out = Join-Path $Root ('LibreWolf-USB-full-' + (Get-Date -Format 'yyyyMMdd-HHmm') + '.zip')
}

# что не тащим в архив: профиль, логи, кэш загрузок и прошлые сборки
$skipNames = @('profile', 'logs', '_download', 'dist', '__pycache__')
$files = New-Object System.Collections.ArrayList
foreach ($f in @(Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue)) {
    $rel = $f.FullName.Substring($Root.Length + 1)
    $parts = $rel -split '[\\/]'
    $skip = $false
    foreach ($p in $parts) {
        if ($skipNames -contains $p) { $skip = $true }
        if ($p -like '_speedtest_*') { $skip = $true }
    }
    if ($rel -like 'LibreWolf-USB-full-*.zip') { $skip = $true }
    if ($NoSecrets -and ($rel -match '^vpn[\\/](sub\.txt|config\.json)$')) { $skip = $true }
    if (-not $skip) { [void]$files.Add($f) }
}

Say ''
Say ('[..] Упаковываю файлов: ' + $files.Count + ' — на большом браузере это может занять пару минут...') 'DarkGray'
if (Test-Path $out) { Remove-Item $out -Force }
$zip = [IO.Compression.ZipFile]::Open($out, [IO.Compression.ZipArchiveMode]::Create)
try {
    $i = 0
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($Root.Length + 1)
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip, $f.FullName, $rel, [IO.Compression.CompressionLevel]::Optimal)
        $i++
        if (($i % 500) -eq 0) { Say ('     файлов: ' + $i) 'DarkGray' }
    }
}
finally {
    $zip.Dispose()
}

$size = (Get-Item $out).Length
$hash = (Get-FileHash $out -Algorithm SHA256).Hash.ToLower()
Say ''
Say ('[OK] Готово: ' + $out) 'Green'
Say ('     размер: ' + [Math]::Round($size / 1MB, 1) + ' МБ')
Say ('     sha256: ' + $hash)
Say ''
Say 'Эту сборку можно распаковать на любую флешку — браузер и xray уже внутри.'
