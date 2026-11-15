# usb-speed.ps1 — замер флешки, на которой лежит комплект.
# Отвечает на вопрос «почему всё тормозит»: последовательные операции против мелких файлов.
# Пишет до 64 МБ во временную папку на флешке и удаляет её за собой.
param([int]$Megabytes = 24)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot

function Say([string]$text, [string]$color = 'Gray') { Write-Host $text -ForegroundColor $color }

Say ''
Say '=== Скорость флешки ===' 'Cyan'
Say ''

# --- диск и файловая система ---
try {
    $vol = Get-Volume -FilePath (Join-Path $Root '.') -ErrorAction Stop
    Say ('диск: ' + $vol.DriveLetter + ':  файловая система: ' + $vol.FileSystemType) 'White'
    Say ('свободно: ' + [Math]::Round($vol.SizeRemaining / 1GB, 1) + ' ГБ из ' + [Math]::Round($vol.Size / 1GB, 1) + ' ГБ')
} catch { Say ('диск: ' + (Split-Path -Qualifier $Root)) }
try {
    $dd = Get-CimInstance Win32_DiskDrive -ErrorAction Stop |
          Where-Object { "$($_.InterfaceType)" -match 'USB' } | Select-Object -First 1
    if ($dd) { Say ('модель: ' + "$($dd.Model)".Trim() + '   интерфейс: ' + $dd.InterfaceType) }
} catch {}

$dir = Join-Path $Root ('_speedtest_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Path $dir -Force | Out-Null

try {
    $mb = [Math]::Min([Math]::Max($Megabytes, 4), 64)
    $buf = New-Object byte[] (1MB)
    (New-Object System.Random).NextBytes($buf)

    Say ''
    Say ('[..] Пишу ' + $mb + ' МБ на флешку (потом удалю)...') 'DarkGray'
    $big = Join-Path $dir 'big.bin'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $fs = [IO.File]::Create($big)
    for ($i = 0; $i -lt $mb; $i++) { $fs.Write($buf, 0, $buf.Length) }
    $fs.Flush($true)
    $fs.Close()
    $sw.Stop()
    $wSpeed = [Math]::Round($mb / [Math]::Max($sw.Elapsed.TotalSeconds, 0.01), 1)

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $fs = [IO.File]::OpenRead($big)
    $out = New-Object byte[] (1MB)
    $read = 0
    while (($n = $fs.Read($out, 0, $out.Length)) -gt 0) { $read += $n }
    $fs.Close()
    $sw.Stop()
    $rSpeed = [Math]::Round((($read / 1MB) / [Math]::Max($sw.Elapsed.TotalSeconds, 0.01)), 1)

    Say '[..] Проверяю мелкие файлы (200 штук по 2 КБ)...' 'DarkGray'
    $small = New-Object byte[] 2048
    (New-Object System.Random).NextBytes($small)
    $count = 200
    $sw = [Diagnostics.Stopwatch]::StartNew()
    for ($i = 0; $i -lt $count; $i++) {
        [IO.File]::WriteAllBytes((Join-Path $dir ('s' + $i + '.dat')), $small)
    }
    $sw.Stop()
    $createMs = [Math]::Round($sw.Elapsed.TotalMilliseconds / $count, 1)

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $files = @(Get-ChildItem -Path $dir -Filter 's*.dat' -ErrorAction SilentlyContinue)
    $sw.Stop()
    $listMs = [Math]::Round($sw.Elapsed.TotalMilliseconds / [Math]::Max($files.Count, 1), 1)

    $sw = [Diagnostics.Stopwatch]::StartNew()
    foreach ($f in $files) { Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue }
    $sw.Stop()
    $delMs = [Math]::Round($sw.Elapsed.TotalMilliseconds / [Math]::Max($files.Count, 1), 1)

    Say ''
    Say ('последовательная запись ' + $mb + ' МБ: ' + $wSpeed + ' МБ/с')
    Say ('последовательное чтение: ' + $rSpeed + ' МБ/с')
    Say ('мелкий файл 2 КБ: создание ' + $createMs + ' мс, удаление ' + $delMs + ' мс, перечисление ' + $listMs + ' мс')
    Say ''
    if ($createMs -le 8 -and $wSpeed -ge 10) {
        Say 'ВЕРДИКТ: флешка нормальная — профиль браузера на ней терпим.' 'Green'
    } elseif ($createMs -le 25) {
        Say 'ВЕРДИКТ: флешка медленная на мелких файлах — браузер будет стартовать долго.' 'Yellow'
        Say '         Запускай START.bat -Fast: профиль будет на локальном диске.' 'Yellow'
    } else {
        Say 'ВЕРДИКТ: флешка очень медленная на мелких файлах (обычно USB 2.0 или дешёвая флешка).' 'Red'
        Say '         Проводник и браузер с неё будут тормозить. Запускай START.bat -Fast.' 'Red'
    }
    Say ''
    Say 'Что помогает:' 'Cyan'
    Say '  1. START.bat -Fast — профиль браузера на локальном диске, флешка только для хранения.'
    Say '  2. Вставить флешку в синий порт USB 3.0, не через USB-хаб и не через переднюю панель.'
    Say '  3. Проводник: Вид -> Подробности; отключить эскизы (Свойства папки -> Вид).'
    Say '  4. Не держать открытым окно проводника на флешке, пока работает браузер.'
    Say '  5. Антивирус: добавить букву флешки в исключения (нужны права администратора).'
}
finally {
    if (Test-Path $dir) {
        foreach ($f in @(Get-ChildItem $dir -ErrorAction SilentlyContinue)) {
            Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $dir -Force -ErrorAction SilentlyContinue
    }
}
Say ''
