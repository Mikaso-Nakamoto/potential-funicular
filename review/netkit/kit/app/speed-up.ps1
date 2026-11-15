# speed-up.ps1 — почему проводник тормозит на этой флешке и что с этим делать.
# 1) замеряет, сколько файлов в папках комплекта и сколько времени уходит на их обход;
# 2) замеряет скорость мелких операций записи (главный тормоз дешёвых флешек);
# 3) по желанию применяет настройки проводника, которые убирают лишнюю работу:
#    значки вместо эскизов, без индексации съёмного диска, без списка недавних файлов.
# Ничего не удаляет и не трогает браузер.
param(
    [switch]$Apply,     # применить настройки без вопросов
    [switch]$NoThumbs,  # отключить эскизы (по умолчанию спрашивает)
    [switch]$Hide       # скрыть служебные папки в проводнике
)
$ErrorActionPreference = 'Stop'

$App  = $PSScriptRoot
$Root = Split-Path -Parent $App
$Vpn  = Join-Path $Root 'vpn'

function Say([string]$t, [string]$c = 'Gray') { Write-Host $t -ForegroundColor $c }
function Head([string]$t) {
    Write-Host ''
    Say ('=== ' + $t + ' ===') 'Cyan'
}

Head 'Ускорение флешки'

# ---------------------------------------------------------------- 1. листинг
function Measure-Dir([string]$path, [switch]$TopOnly) {
    if (-not (Test-Path $path)) { return $null }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $n = 0
    $bytes = 0
    try {
        $items = @(Get-ChildItem -LiteralPath $path -Force -File -ErrorAction SilentlyContinue)
        if (-not $TopOnly) {
            $items += @(Get-ChildItem -LiteralPath $path -Recurse -Force -File -ErrorAction SilentlyContinue)
        }
        foreach ($f in $items) {
            $n++
            $bytes += $f.Length
        }
    } catch { }
    $sw.Stop()
    return @{ Files = $n; Ms = [int]$sw.Elapsed.TotalMilliseconds; MB = [math]::Round($bytes / 1MB, 1) }
}

Say 'Читаю папки комплекта (это и есть та работа, которую делает проводник):' 'Gray'
$rows = @()
$targets = @(
    @('корень флешки', $Root),
    @('app\LibreWolf', (Join-Path $App 'LibreWolf')),
    @('profile', (Join-Path $Root 'profile')),
    @('app', $App),
    @('vpn', $Vpn)
)
foreach ($t in $targets) {
    $m = Measure-Dir $t[1] -TopOnly:($t[0] -eq 'корень флешки')
    if ($null -eq $m) { continue }
    $rows += , @($t[0], $m.Files, $m.MB, $m.Ms)
}

Write-Host ''
Write-Host ('  {0,-18} {1,8} {2,10} {3,10}' -f 'папка', 'файлов', 'МБ', 'обход, мс') -ForegroundColor DarkGray
$worst = $null
foreach ($r in $rows) {
    $color = 'Gray'
    if ($r[1] -ge 3000) { $color = 'Red' }
    elseif ($r[1] -ge 800) { $color = 'Yellow' }
    Write-Host ('  {0,-18} {1,8} {2,10} {3,10}' -f $r[0], $r[1], $r[2], $r[3]) -ForegroundColor $color
    if ($r[1] -ge 800 -and ($null -eq $worst -or $r[1] -gt $worst[1])) { $worst = $r }
}

# ---------------------------------------------------------------- 2. мелкая запись
Head 'Скорость мелких операций'
$tmp = Join-Path $App ('.speedtest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$small = 150
$size = 4096
Say ('Пишу ' + $small + ' файлов по 4 КБ...') 'DarkGray'
$ms = 0
try {
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $buf = New-Object byte[] $size
    (New-Object Random).NextBytes($buf)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    for ($i = 0; $i -lt $small; $i++) {
        [IO.File]::WriteAllBytes((Join-Path $tmp ('f' + $i + '.tmp')), $buf)
    }
    $sw.Stop()
    $ms = [int]$sw.Elapsed.TotalMilliseconds
} catch {
    Say ('  замер не удался: ' + $_.Exception.Message) 'Yellow'
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$verdict = ''
$vcolor = 'Gray'
if ($ms -gt 0) {
    $perFile = [math]::Round($ms / [double]$small, 1)
    Write-Host ('  ' + $small + ' файлов: ' + $ms + ' мс  (' + $perFile + ' мс на файл)') -ForegroundColor White
    if ($ms -lt 1500) { $verdict = 'быстро — флешка тут не виновата'; $vcolor = 'Green' }
    elseif ($ms -lt 4500) { $verdict = 'терпимо — проводник будет задумываться на больших папках'; $vcolor = 'Yellow' }
    else { $verdict = 'медленно — это и есть причина лагов проводника'; $vcolor = 'Red' }
    Say ('  вывод: ' + $verdict) $vcolor
}

# ---------------------------------------------------------------- 3. вывод
Head 'Что происходит'
if ($null -ne $worst) {
    Say ('  Больше всего файлов в «' + $worst[0] + '»: ' + $worst[1] + ' шт.') 'Yellow'
    Say '  Проводник при входе в такую папку читает свойства каждого файла и строит значки,' 'Gray'
    Say '  а флешка на мелких операциях в десятки раз медленнее диска. Отсюда «не отвечает».' 'Gray'
} else {
    Say '  Крупных папок не нашлось — если лагает всё равно, дело в самой флешке или антивирусе.' 'Yellow'
}
$prof = @($rows | Where-Object { $_[0] -eq 'profile' })
if ($prof.Count -gt 0 -and $prof[0][1] -ge 3000) {
    Say ('  Профиль браузера — ' + $prof[0][1] + ' файлов на флешке. Это история, кэш и сессии.') 'Yellow'
    Say '  Он нужен для сохранения входа, но именно он сильнее всего тормозит вход в корень.' 'Gray'
    Say '  Чистка профиля: пункт 6 с параметром -Scrub (сотрёт историю и входы).' 'Gray'
}
if ($ms -ge 4500) {
    Say '  Запись мелких файлов медленная: антивирус проверяет каждую запись, флешка дешёвая' 'Yellow'
    Say '  или порт USB 2.0. Помогает: порт USB 3.0 (синий), другая флешка, исключение в антивирусе.' 'Yellow'
}

# ---------------------------------------------------------------- 4. настройки
Head 'Настройки проводника'
if (-not $env:SystemRoot) {
    Say '  Это Windows-настройки; здесь (не Windows) они пропущены.' 'DarkGray'
    Write-Host ''
    exit 0
}

$changes = @(
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'IconsOnly', 1,
      'значки вместо эскизов — папки с картинками открываются мгновенно'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'Start_TrackDocs', 0,
      'не запоминать недавние документы'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'ShowSuperHidden', 0,
      'не показывать системные файлы'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'ExtendedUIHoverTime', 800,
      'подсказки появляются позже и не тормозят список')
)

Say '  Предлагаю применить (только текущий пользователь, откат — обратные значения):' 'Gray'
foreach ($c in $changes) { Say ('   · ' + $c[3]) 'White' }
Say '   · не индексировать флешку (attrib +I) — Windows Search перестанет её обходить' 'White'
if ($NoThumbs -or $Hide) {
    if ($NoThumbs) { Say '   · полностью отключить эскизы (DisableThumbnails)' 'White' }
    if ($Hide) { Say '   · скрыть служебные папки app, vpn, profile, _download' 'White' }
}

$doIt = $Apply
if (-not $doIt) {
    Write-Host ''
    Write-Host '  Применить? [y/N] ' -ForegroundColor Green -NoNewline
    $ans = (Read-Host).Trim()
    $doIt = ($ans -eq 'y' -or $ans -eq 'Y' -or $ans -eq 'да')
}
if (-not $doIt) {
    Say '  Ничего не менял.' 'DarkGray'
    Write-Host ''
    exit 0
}

$applied = 0
foreach ($c in $changes) {
    try {
        if (-not (Test-Path $c[0])) { New-Item -Path $c[0] -Force | Out-Null }
        New-ItemProperty -Path $c[0] -Name $c[1] -Value $c[2] -PropertyType DWord -Force | Out-Null
        $applied++
    } catch {
        Say ('  [!] не удалось: ' + $c[1] + ' — ' + $_.Exception.Message) 'Red'
    }
}

if ($NoThumbs) {
    try {
        $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
        if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
        New-ItemProperty -Path $k -Name 'DisableThumbnails' -Value 1 -PropertyType DWord -Force | Out-Null
        $applied++
    } catch { Say '  [!] DisableThumbnails не применился' 'Red' }
}

# не индексировать содержимое флешки
try {
    & "$env:SystemRoot\System32\attrib.exe" +I "$Root\*" /S /D 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $applied++ } else { Say '  [!] attrib +I вернул ошибку' 'Yellow' }
} catch {
    Say '  [!] attrib.exe недоступен — пропускаю' 'Yellow'
}

if ($Hide) {
    foreach ($p in @('app', 'vpn', 'profile', '_download')) {
        $full = Join-Path $Root $p
        if (Test-Path $full) {
            try { (Get-Item $full -Force).Attributes = 'Directory,Hidden,System' } catch { }
        }
    }
    Say '  Служебные папки скрыты (видны при включённом «показывать скрытые»).' 'DarkGray'
}

Say ('  Применено настроек: ' + $applied) 'Green'
Say '  Перезапусти проводник (или войди заново), чтобы настройки подхватились.' 'DarkGray'
Write-Host ''
Say 'Откат: IconsOnly=0, Start_TrackDocs=1, ExtendedUIHoverTime=400, DisableThumbnails удалить.' 'DarkGray'
exit 0
