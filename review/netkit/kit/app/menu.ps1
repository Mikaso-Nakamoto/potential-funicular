# menu.ps1 — единое меню комплекта LibreWolf-USB (стиль TempleOS).
# Один батник в корне запускает этот экран; всё остальное — отсюда.
$ErrorActionPreference = 'Stop'

$App     = $PSScriptRoot
$Root    = Split-Path -Parent $App
$Vpn     = Join-Path $Root 'vpn'
$Cfg     = Join-Path $Vpn 'config.json'
$SubFile = Join-Path $Vpn 'sub.txt'

$psExe = 'powershell.exe'
if (-not $env:SystemRoot) {
    $p = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($p) { $psExe = $p.Source }
}

# ---------------------------------------------------------------- оформление
$Logo = @(
    '################################',
    '#::::::::::::::::::::::::::::::#',
    '#:::::::::::::%%%%&::::::::::::#',
    '#:::::::::::::%%%%&::::::::::::#',
    '#:::::::::::::%%%%&::::::::::::#',
    '#:::::::::::::%%%%&::::::::::::#',
    '#:::::::::::oooo~oooo::::::::::#',
    '#:::::::::oo~ooo~ooo~oo::::::::#',
    '#:%%%%%%%%%%%%%%%%&%%%%%%%%%%%:#',
    '#:%%%%%%%%%%%%%%%%&%%%%%%%%%%%:#',
    '#:&&&&&&&&&&&&&&&&&&&&&&&&&&&&:#',
    '#:::::::::oo::%%%%&::oo::::::::#',
    '#:::::::::~oo:%%%%&:oo~::::::::#',
    '#:::::::::o~o:%%%%&:o~o::::::::#',
    '#:::::::::~oo:%%%%&:oo~::::::::#',
    '#:::::::::o~o:%%%%&:o~o::::::::#',
    '#:::::::::~oo:%%%%&:oo~::::::::#',
    '#:::::::::oo::%%%%&::oo::::::::#',
    '#:::::::::oo::%%%%&::oo::::::::#',
    '#:::::::::::::%%%%&::::::::::::#',
    '#:::::::::::::%%%%&::::::::::::#',
    '#:::::::::::::%%%%&::::::::::::#',
    '#::::::::::::::::::::::::::::::#',
    '################################'
)

function Get-Info {
    $lines = @()
    $lines += 'TempleOS 5.03  ·  LibreWolf-USB'
    $lines += '────────────────────────────────'
    $lines += ('Флешка   : ' + $Root)
    if (Test-Path (Join-Path $App 'LibreWolf\LibreWolf.exe')) { $lines += 'Браузер  : установлен' }
    else { $lines += 'Браузер  : НЕТ (нужна подготовка)' }
    if (Test-Path (Join-Path $Vpn 'xray.exe')) { $lines += 'Xray     : установлен' }
    else { $lines += 'Xray     : НЕТ (нужна подготовка)' }
    if (Test-Path $Cfg) {
        $n = 0
        try { $n = @((Get-Content $Cfg -Raw -Encoding UTF8 | ConvertFrom-Json).outbounds).Count } catch {}
        $age = [int]((Get-Date) - (Get-Item $Cfg).LastWriteTime).TotalDays
        $lines += ('Конфиг   : ' + $n + ' сервер(ов), возраст ' + $age + ' дн.')
    } else {
        $lines += 'Конфиг   : нет'
    }
    if ((Test-Path $SubFile) -and ((Get-Content $SubFile -Raw -ErrorAction SilentlyContinue) -match 'url\s*=\s*\S+')) {
        $lines += 'Подписка : настроена'
    } else {
        $lines += 'Подписка : нет'
    }
    if (Test-Path (Join-Path $Root 'profile')) { $lines += 'Профиль  : есть (история на флешке)' }
    else { $lines += 'Профиль  : чистый' }
    try {
        $q = Split-Path -Qualifier $Root
        $d = Get-PSDrive -Name $q.TrimEnd(':') -ErrorAction Stop
        $free = [math]::Round($d.Free / 1GB, 1)
        $lines += ('Свободно : ' + $free + ' ГБ')
    } catch { }
    $lines += 'Сборка   : F-45'
    return $lines
}

function Get-ArtColor([char]$c) {
    switch ($c) {
        '#' { 'Blue' }
        ':' { 'DarkCyan' }
        '%' { 'Yellow' }
        '&' { 'DarkYellow' }
        'o' { 'White' }
        '~' { 'Gray' }
        default { 'Gray' }
    }
}

function Write-ArtRow([string]$row) {
    $i = 0
    while ($i -lt $row.Length) {
        $col = Get-ArtColor $row[$i]
        $sb = New-Object System.Text.StringBuilder
        while ($i -lt $row.Length -and (Get-ArtColor $row[$i]) -eq $col) {
            [void]$sb.Append($row[$i]); $i++
        }
        Write-Host $sb.ToString() -ForegroundColor $col -NoNewline
    }
    $pad = 34 - $row.Length
    if ($pad -gt 0) { Write-Host (' ' * $pad) -NoNewline }
}

function Show-Palette {
    $colors = @('Black','DarkBlue','DarkGreen','DarkCyan','DarkRed','DarkMagenta','DarkYellow','Gray',
                'DarkGray','Blue','Green','Cyan','Red','Magenta','Yellow','White')
    Write-Host '   ' -NoNewline
    foreach ($c in $colors) {
        Write-Host '██' -ForegroundColor $c -NoNewline
    }
    Write-Host ''
}

function Show-Screen {
    if ($env:SystemRoot -or $env:TERM) { Clear-Host }
    $info = Get-Info
    $rows = [Math]::Max($Logo.Count, $info.Count)
    Write-Host ''
    for ($i = 0; $i -lt $rows; $i++) {
        Write-Host '   ' -NoNewline
        if ($i -lt $Logo.Count) { Write-ArtRow $Logo[$i] }
        else { Write-Host (' ' * 34) -NoNewline }
        if ($i -lt $info.Count) {
            if ($i -eq 0) { Write-Host $info[$i] -ForegroundColor White }
            elseif ($i -eq 1) { Write-Host $info[$i] -ForegroundColor DarkGray }
            else { Write-Host $info[$i] -ForegroundColor Gray }
        } else { Write-Host '' }
    }
    Write-Host ''
    Show-Palette
    Write-Host ''
    Write-Host '   ╔══════════════════════════════════════════════════════╗' -ForegroundColor DarkCyan
    Write-Host '   ║                    В Ы Б О Р                         ║' -ForegroundColor DarkCyan
    Write-Host '   ╚══════════════════════════════════════════════════════╝' -ForegroundColor DarkCyan
}

function Show-Menu {
    $items = @(
        @('1', 'Запустить сессию'),
        @('2', 'Запустить с настройками (сервер, -Fast и др.)'),
        @('3', 'Обновить подписку сейчас'),
        @('4', 'Подготовка дома (браузер и Xray)'),
        @('5', 'Собрать полную сборку в zip'),
        @('6', 'Почистить следы на этом ПК (-Deep, -Scrub)'),
        @('7', 'Проверка комплекта'),
        @('0', 'Выход')
    )
    foreach ($it in $items) {
        Write-Host '     ' -NoNewline
        Write-Host ('[' + $it[0] + ']') -ForegroundColor Yellow -NoNewline
        Write-Host ('  ' + $it[1])
    }
    Write-Host ''
}

function Run-PS([string]$Script, [string[]]$ScriptArgs = @()) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Script) + $ScriptArgs
    Write-Host ''
    & $psExe @a
    $code = $LASTEXITCODE
    Write-Host ''
    Write-Host ('   [код возврата: ' + $code + ']') -ForegroundColor DarkGray
    return $code
}

function Pause-Menu {
    Write-Host ''
    Write-Host '   Нажми Enter, чтобы вернуться в меню...' -ForegroundColor DarkGray -NoNewline
    $null = Read-Host
}

# ---------------------------------------------------------------- цикл
while ($true) {
    Show-Screen
    Show-Menu
    Write-Host '   Твой выбор: ' -ForegroundColor Green -NoNewline
    $choice = (Read-Host).Trim()

    switch ($choice) {
        '1' {
            [void](Run-PS (Join-Path $App 'start.ps1'))
            Pause-Menu
        }
        '2' {
            Write-Host ''
            Write-Host '   Номер сервера (Enter — без фиксации, пусть выбирает сам):' -ForegroundColor Gray
            Write-Host '   > ' -ForegroundColor Green -NoNewline
            $num = (Read-Host).Trim()
            Write-Host '   Дополнительные параметры: -Fast, -IgnorePolicies, -Debug (Enter — нет):' -ForegroundColor Gray
            Write-Host '   > ' -ForegroundColor Green -NoNewline
            $extra = (Read-Host).Trim()
            $extraArgs = @()
            if ($num -match '^\d+$' -and [int]$num -ge 1) { $extraArgs += @('-Server', $num) }
            elseif ($num -ne '') { Write-Host '   Номер не разобран — запускаю без -Server.' -ForegroundColor Yellow }
            if ($extra -ne '') { $extraArgs += ($extra -split '\s+') }
            [void](Run-PS (Join-Path $App 'start.ps1') $extraArgs)
            Pause-Menu
        }
        '3' {
            [void](Run-PS (Join-Path $App 'start.ps1') @('-ForceUpdate'))
            Pause-Menu
        }
        '4' {
            [void](Run-PS (Join-Path $App 'prepare-home.ps1'))
            Pause-Menu
        }
        '5' {
            [void](Run-PS (Join-Path $App 'make-bundle.ps1'))
            Pause-Menu
        }
        '6' {
            Write-Host ''
            Write-Host '   Параметры чистки: -Deep (Prefetch, нужен админ), -Scrub (стереть профиль).' -ForegroundColor Gray
            Write-Host '   > ' -ForegroundColor Green -NoNewline
            $extra = (Read-Host).Trim()
            $extraArgs = @()
            if ($extra -ne '') { $extraArgs += ($extra -split '\s+') }
            [void](Run-PS (Join-Path $App 'clean-traces.ps1') $extraArgs)
            Pause-Menu
        }
        '7' {
            [void](Run-PS (Join-Path $App 'self-check.ps1'))
            Pause-Menu
        }
        '0' { break }
        '' { }
        default {
            Write-Host '   Такого пункта нет.' -ForegroundColor Red
            Start-Sleep -Milliseconds 900
        }
    }
    if ($choice -eq '0') { break }
}

Clear-Host
Write-Host ''
Write-Host '   Сессия закрыта. Флешку можно вынимать.' -ForegroundColor Cyan
Write-Host ''
