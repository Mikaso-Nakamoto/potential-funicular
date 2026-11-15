# menu.ps1 — единое меню комплекта LibreWolf-USB в стиле TempleOS.
# Один батник в корне запускает этот экран; всё остальное — отсюда.
# Логотип анимирован: крест с качающейся тканью и весы с качающимися чашами
# сменяют друг друга раз в 30 секунд плавным перетеканием символов.
$ErrorActionPreference = 'Stop'

$App     = $PSScriptRoot
$Root    = Split-Path -Parent $App
$Vpn     = Join-Path $Root 'vpn'
$Cfg     = Join-Path $Vpn 'config.json'
$SubFile = Join-Path $Vpn 'sub.txt'

. (Join-Path $App 'logo.ps1')

$psExe = 'powershell.exe'
if (-not $env:SystemRoot) {
    $p = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($p) { $psExe = $p.Source }
}

$Esc = [char]27

$ArtCol   = 4     # колонка логотипа (1-based)
$ArtRow   = 2     # строка логотипа
$RightCol = 39    # колонка правой панели

# ---------------------------------------------------------------- VT
$script:UseAnsi = $true
function Enable-VT {
    if (-not $env:SystemRoot) { return $true }
    try {
        if ([Console]::IsOutputRedirected) { return $false }
        Add-Type -Namespace LwUsb -Name Vt -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetConsoleMode(IntPtr h, out uint mode);
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetConsoleMode(IntPtr h, uint mode);
'@ -ErrorAction Stop
        $h = [LwUsb.Vt]::GetStdHandle(-11)
        $m = [uint32]0
        if (-not [LwUsb.Vt]::GetConsoleMode($h, [ref]$m)) { return $false }
        [void][LwUsb.Vt]::SetConsoleMode($h, ($m -bor 0x0004))
        # проверяем, что режим действительно включился
        $m2 = [uint32]0
        if (-not [LwUsb.Vt]::GetConsoleMode($h, [ref]$m2)) { return $false }
        return (($m2 -band 0x0004) -eq 0x0004)
    } catch { return $false }
}
$script:UseAnsi = Enable-VT

# ---------------------------------------------------------------- состояние
function Get-Info {
    $lines = @()
    $lines += 'TempleOS 5.03  ·  LibreWolf-USB'
    $lines += [string]([char]0x2500) * 34
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
        $lines += ('Свободно : ' + [math]::Round($d.Free / 1GB, 1) + ' ГБ')
    } catch { }
    $lines += 'Сборка   : F-45'
    return $lines
}

# ---------------------------------------------------------------- отрисовка
function Write-ArtAnsi($grid) {
    $rows = ConvertTo-AnsiRows $grid
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $rows.Count; $i++) {
        [void]$sb.Append("$Esc[" + ($ArtRow + $i) + ';' + $ArtCol + 'H')
        [void]$sb.Append($rows[$i])
    }
    [void]$sb.Append("$Esc[0m")
    [Console]::Out.Write($sb.ToString())
}

function Write-ArtFallback($grid) {
    for ($y = 0; $y -lt $ArtH; $y++) {
        [Console]::SetCursorPosition(($ArtCol - 1), ($ArtRow - 1 + $y))
        $cur = -1
        for ($x = 0; $x -lt $ArtW; $x++) {
            $i = $y * $ArtW + $x
            $ci = $grid.Co[$i]
            if ($ci -ne $cur) {
                $map = @('Black','DarkBlue','DarkGreen','DarkCyan','DarkRed','DarkMagenta','DarkYellow','Gray',
                         'DarkGray','Blue','Green','Cyan','Red','Magenta','Yellow','White')
                [Console]::ForegroundColor = [ConsoleColor]$map[$ci]
                $cur = $ci
            }
            [Console]::Out.Write($grid.Ch[$i])
        }
        [Console]::ResetColor()
    }
}

function Write-ArtFrame($grid) {
    if ($script:UseAnsi) { Write-ArtAnsi $grid } else { Write-ArtFallback $grid }
}

function Get-SgrCode([int]$c) {
    if ($c -lt 8) { return (30 + $c) }
    return (90 + $c - 8)
}

function Get-RightRows($info) {
    $items = @(
        @('1', 'Запустить сессию'),
        @('2', 'Запустить с настройками (сервер, -Fast)'),
        @('3', 'Обновить подписку сейчас'),
        @('4', 'Подготовка дома (браузер и Xray)'),
        @('5', 'Собрать полную сборку в zip'),
        @('6', 'Почистить следы (-Deep, -Scrub)'),
        @('7', 'Проверка комплекта'),
        @('0', 'Выход')
    )
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($l in $info) { $rows.Add(@('info', $l)) }
    $rows.Add(@('blank', ''))
    $rows.Add(@('frame', '╔══════════════════════════════════════════╗'))
    $rows.Add(@('frame', '║              В Ы Б О Р                   ║'))
    $rows.Add(@('frame', '╚══════════════════════════════════════════╝'))
    foreach ($it in $items) { $rows.Add(@('item', $it)) }
    $rows.Add(@('blank', ''))
    $rows.Add(@('prompt', 'Твой выбор: '))
    return $rows
}

function Build-Scene($grid, $info) {
    $sb = New-Object System.Text.StringBuilder
    $rows = ConvertTo-AnsiRows $grid
    for ($i = 0; $i -lt $rows.Count; $i++) {
        [void]$sb.Append("$Esc[" + ($ArtRow + $i) + ';' + $ArtCol + 'H')
        [void]$sb.Append($rows[$i])
    }

    # палитра под логотипом
    $palRow = $ArtRow + $ArtH + 1
    [void]$sb.Append("$Esc[" + $palRow + ';' + $ArtCol + 'H')
    for ($c = 0; $c -lt 16; $c++) {
        [void]$sb.Append("$Esc[" + (Get-SgrCode $c) + 'm' + [char]0x2588 + [char]0x2588)
    }
    [void]$sb.Append("$Esc[0m")

    # правая панель
    $right = Get-RightRows $info
    $script:PromptRow = 0
    $script:PromptCol = 0
    for ($i = 0; $i -lt $right.Count; $i++) {
        $row = $ArtRow + $i
        $kind = $right[$i][0]
        $text = $right[$i][1]
        [void]$sb.Append("$Esc[" + $row + ';' + $RightCol + 'H')
        switch ($kind) {
            'info' {
                if ($i -eq 0) { [void]$sb.Append("$Esc[97m") }
                elseif ($i -eq 1) { [void]$sb.Append("$Esc[90m") }
                else { [void]$sb.Append("$Esc[37m") }
                [void]$sb.Append($text + "$Esc[0m")
            }
            'frame' { [void]$sb.Append("$Esc[36m" + $text + "$Esc[0m") }
            'item' {
                [void]$sb.Append("$Esc[93m  [" + $text[0] + ']' + "$Esc[0m" + '  ' + $text[1])
            }
            'prompt' {
                [void]$sb.Append("$Esc[92m" + $text + "$Esc[0m")
                $script:PromptRow = $row
                $script:PromptCol = $RightCol + $text.Length
            }
            default { }
        }
    }
    # предупреждение, если окно слишком узкое
    try {
        if ([Console]::WindowWidth -gt 0 -and [Console]::WindowWidth -lt 84) {
            [void]$sb.Append("$Esc[1;1H`e[91m Окно мало: разверни консоль на весь экран (Alt+Enter)`e[0m")
        }
    } catch { }
    return $sb.ToString()
}

function Draw-Scene($grid, $info) {
    if ($env:SystemRoot -or $env:TERM) { Clear-Host }
    if ($script:UseAnsi) {
        [Console]::Out.Write((Build-Scene $grid $info))
        [Console]::SetCursorPosition(($script:PromptCol - 1), ($script:PromptRow - 1))
    } else {
        $rows = Get-ArtText $grid
        Write-Host ''
        for ($i = 0; $i -lt $rows.Count; $i++) { Write-Host ('   ' + $rows[$i]) }
        Write-Host ''
        $colors = @('Black','DarkBlue','DarkGreen','DarkCyan','DarkRed','DarkMagenta','DarkYellow','Gray',
                    'DarkGray','Blue','Green','Cyan','Red','Magenta','Yellow','White')
        Write-Host '   ' -NoNewline
        foreach ($c in $colors) { Write-Host ([string][char]0x2588 + [char]0x2588) -ForegroundColor $c -NoNewline }
        Write-Host ''
        Write-Host ''
        foreach ($row in (Get-RightRows $info)) {
            if ($row[0] -eq 'item') { Write-Host ('  [' + $row[1][0] + ']  ' + $row[1][1]) }
            elseif ($row[0] -eq 'frame') { Write-Host $row[1] -ForegroundColor DarkCyan }
            elseif ($row[0] -eq 'prompt') { Write-Host $row[1] -ForegroundColor Green -NoNewline }
            else { Write-Host $row[1] }
        }
    }
}

# ---------------------------------------------------------------- ввод
function Read-Choice($initialGrid, $info) {
    if ([Console]::IsInputRedirected) {
        return (Read-Host).Trim()
    }

    $buf = ''
    $phase = 0.0
    $mode = 'cross'
    $other = 'scales'
    $frame = 0
    $morphLeft = 0
    $morphTotal = 16
    $nextSwitch = [DateTime]::Now.AddSeconds(30)
    $lastDraw = [DateTime]::MinValue

    $promptX = $script:PromptCol - 1
    $promptY = $script:PromptRow - 1

    while ($true) {
        $now = [DateTime]::Now
        if (($now - $lastDraw).TotalMilliseconds -ge 75) {
            $phase += 0.16
            $g = $null
            if ($morphLeft -gt 0) {
                $t = 1.0 - ($morphLeft / [double]$morphTotal)
                $g = Get-MorphGrid (Get-Frame $mode $phase) (Get-Frame $other $phase) $t
                $morphLeft--
                if ($morphLeft -eq 0) {
                    $tmp = $mode; $mode = $other; $other = $tmp
                    $nextSwitch = [DateTime]::Now.AddSeconds(30)
                }
            } else {
                $g = Get-Frame $mode $phase
                if ($now -ge $nextSwitch) { $morphLeft = $morphTotal }
            }
            Write-ArtFrame $g
            $lastDraw = $now
        }

        if ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq 'Enter') {
                [Console]::SetCursorPosition($promptX, $promptY)
                return $buf
            } elseif ($k.Key -eq 'Backspace') {
                if ($buf.Length -gt 0) {
                    $buf = $buf.Substring(0, $buf.Length - 1)
                    [Console]::SetCursorPosition($promptX, $promptY)
                    Write-Host ($buf + ' ') -NoNewline
                    [Console]::SetCursorPosition(($promptX + $buf.Length), $promptY)
                }
            } elseif ($k.KeyChar -match '^[0-9]$') {
                $buf += $k.KeyChar
                [Console]::SetCursorPosition($promptX, $promptY)
                Write-Host $buf -NoNewline
            }
        } else {
            Start-Sleep -Milliseconds 15
        }
    }
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
$info = Get-Info
$firstGrid = Get-Frame 'cross' 0.0

while ($true) {
    Draw-Scene $firstGrid $info
    $choice = Read-Choice $firstGrid $info

    switch ($choice) {
        '1' {
            [void](Run-PS (Join-Path $App 'start.ps1'))
            Pause-Menu
        }
        '2' {
            Write-Host ''
            Write-Host '   Номер сервера (Enter — без фиксации):' -ForegroundColor Gray
            Write-Host '   > ' -ForegroundColor Green -NoNewline
            $num = (Read-Host).Trim()
            Write-Host '   Доп. параметры: -Fast, -IgnorePolicies, -Debug (Enter — нет):' -ForegroundColor Gray
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
            Write-Host '   Параметры: -Deep (Prefetch, нужен админ), -Scrub (стереть профиль).' -ForegroundColor Gray
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
    if ($choice -eq '0') {
        $info = Get-Info
    }
    if ($choice -eq '0') { break }
}

Clear-Host
Write-Host ''
Write-Host '   Сессия закрыта. Флешку можно вынимать.' -ForegroundColor Cyan
Write-Host ''
