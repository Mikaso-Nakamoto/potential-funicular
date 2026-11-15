# menu.ps1 — единое меню комплекта LibreWolf-USB.
# Один батник в корне запускает этот экран; всё остальное — отсюда.
# Вид: панели в рамках, пункты [N] с колонкой описаний, слева состояние комплекта,
# справа — анимированный пиксельный логотип (крест с плащаницей / весы с мечом).
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
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
$script:Build = 'F-52'

# геометрия сцены (1-based)
$script:MenuW   = 100   # ширина шапки
$script:LeftCol = 2
$script:LeftW   = 54
$script:ArtRow  = 5
$script:ArtCol  = 58

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
function Get-State {
    $s = New-Object System.Collections.Generic.List[object]
    $where = $Root
    try {
        $q = Split-Path -Qualifier $Root
        if ($q) { $where = $q + '\' }
        else { $where = '...' + (Split-Path -Leaf $Root) }
    } catch { }
    $s.Add(@('Флешка', $where, $true))
    $s.Add(@('Браузер', $(if (Test-Path (Join-Path $App 'LibreWolf\LibreWolf.exe')) { 'есть' } else { 'нет — пункт 4' }), (Test-Path (Join-Path $App 'LibreWolf\LibreWolf.exe'))))
    $s.Add(@('Xray', $(if (Test-Path (Join-Path $Vpn 'xray.exe')) { 'есть' } else { 'нет — пункт 4' }), (Test-Path (Join-Path $Vpn 'xray.exe'))))
    if (Test-Path $Cfg) {
        $n = 0
        try { $n = @((Get-Content $Cfg -Raw -Encoding UTF8 | ConvertFrom-Json).outbounds).Count } catch { }
        $age = [int]((Get-Date) - (Get-Item $Cfg).LastWriteTime).TotalDays
        $s.Add(@('Конфиг', "$n серв., $age дн.", $true))
    } else {
        $s.Add(@('Конфиг', 'нет — пункт 3/4', $false))
    }
    $hasSub = ((Test-Path $SubFile) -and ((Get-Content $SubFile -Raw -ErrorAction SilentlyContinue) -match 'url\s*=\s*\S+'))
    $s.Add(@('Подписка', $(if ($hasSub) { 'настроена' } else { 'нет' }), $hasSub))
    $s.Add(@('Профиль', $(if (Test-Path (Join-Path $Root 'profile')) { 'есть' } else { 'чистый' }), $true))
    try {
        $q = Split-Path -Qualifier $Root
        $d = Get-PSDrive -Name $q.TrimEnd(':') -ErrorAction Stop
        $s.Add(@('Свободно', ([string]([math]::Round($d.Free / 1GB, 1)) + ' ГБ'), ($d.Free -gt 1GB)))
    } catch { }
    return $s
}

# ---------------------------------------------------------------- отрисовка
function Write-ArtAnsi($grid) {
    $rows = ConvertTo-AnsiRows $grid
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $rows.Count; $i++) {
        [void]$sb.Append("$Esc[" + ($script:ArtRow + $i) + ';' + $script:ArtCol + 'H')
        [void]$sb.Append($rows[$i])
    }
    [void]$sb.Append("$Esc[0m")
    [Console]::Out.Write($sb.ToString())
}

function Write-ArtFallback($pix) {
    $rows = Get-ArtText $pix
    for ($i = 0; $i -lt $rows.Count; $i++) {
        try { [Console]::SetCursorPosition(($script:ArtCol - 1), ($script:ArtRow - 1 + $i)) } catch { }
        Write-Host $rows[$i] -ForegroundColor Cyan -NoNewline
    }
}

function Write-ArtFrame($grid) {
    if ($script:UseAnsi) { Write-ArtAnsi $grid } else { Write-ArtFallback $grid }
}

# ConsoleColor -> ANSI SGR: индексы не совпадают (1 = синий у консоли, но красный у ANSI)
function Get-SgrCode([int]$c) {
    $map = @(30, 34, 32, 36, 31, 35, 33, 37, 90, 94, 92, 96, 91, 95, 93, 97)
    return $map[$c]
}

# видимая длина строки с ANSI-последовательностями
function Get-VisLen([string]$s) {
    return ([regex]::Replace($s, "$([regex]::Escape($Esc))\[[0-9;]*m", '')).Length
}

function Pad-Ansi([string]$s, [int]$width) {
    $pad = $width - (Get-VisLen $s)
    if ($pad -lt 1) { $pad = 1 }
    return $s + (' ' * $pad)
}

function Get-Rule([string]$text, [int]$width) {
    $d = [string][char]0x2500
    $head = $d + $d + $d + ' ' + $text + ' '
    $n = $width - $head.Length
    if ($n -lt 2) { $n = 2 }
    return $head + ($d * $n)
}

# строки левой колонки: секции, пункты, панель состояния
function Get-LeftRows($state, [switch]$Short) {
    $rows = New-Object System.Collections.Generic.List[object]
    $rows.Add(@('sec', 'ЗАПУСК'))
    $rows.Add(@('item', '1', 'Обычный запуск', 'браузер через VPN'))
    $rows.Add(@('item', '2', 'С настройками', 'сервер, параметры'))
    $rows.Add(@('sec', 'ПОДПИСКА И ДОМ'))
    $rows.Add(@('item', '3', 'Обновить подписку', 'сейчас, без VPN'))
    $rows.Add(@('item', '4', 'Подготовка дома', 'браузер, Xray, ключ'))
    $rows.Add(@('item', '5', 'Собрать архив', 'полный zip'))
    $rows.Add(@('sec', 'СЛУЖЕБНОЕ'))
    $rows.Add(@('item', '6', 'Почистить следы', '-Deep, -Scrub'))
    $rows.Add(@('item', '7', 'Проверка комплекта', 'проверки без сети'))
    $rows.Add(@('sep'))
    $rows.Add(@('item', '0', 'Выход', 'закрыть меню'))
    $rows.Add(@('blank'))
    $rows.Add(@('box-top', 'СОСТОЯНИЕ'))
    $shown = $state
    if ($Short -and $state.Count -gt 4) { $shown = $state[0..3] }
    foreach ($s in $shown) { $rows.Add(@('box', $s[0], $s[1], $s[2])) }
    $rows.Add(@('box-bottom'))
    return $rows
}

function Build-Left($state, [switch]$Short) {
    $out = New-Object System.Collections.Generic.List[string]
    $d = [string][char]0x2500
    $v = [string][char]0x2502
    $innerW = $script:LeftW
    foreach ($r in (Get-LeftRows $state -Short:$Short)) {
        switch ($r[0]) {
            'sec'  { $out.Add("$Esc[36m" + (Get-Rule $r[1] $innerW) + "$Esc[0m") }
            'sep'  { $out.Add("$Esc[90m" + ($d * $innerW) + "$Esc[0m") }
            'blank'{ $out.Add('') }
            'item' {
                $num = $r[1]
                $numColor = if ($num -eq '0') { 91 } else { 93 }
                $name = [string]$r[2]
                $desc = [string]$r[3]
                $gap = 21 - $name.Length
                if ($gap -lt 2) { $gap = 2 }
                $line = ' ' + "$Esc[${numColor}m" + "[$num]" + "$Esc[0m" + '  ' +
                        "$Esc[97m" + $name + "$Esc[0m" + (' ' * $gap) +
                        "$Esc[90m" + $desc + "$Esc[0m"
                $out.Add($line)
            }
            'box-top' {
                $title = ' ' + $r[1] + ' '
                $n = $innerW - $title.Length - 2
                if ($n -lt 2) { $n = 2 }
                $out.Add("$Esc[36m" + [string][char]0x250C + $title + ($d * $n) + [string][char]0x2510 + "$Esc[0m")
            }
            'box' {
                $label = [string]$r[1]
                $value = [string]$r[2]
                $padL = 8 - $label.Length
                if ($padL -lt 1) { $padL = 1 }
                $maxValue = $innerW - 3 - (1 + $label.Length + $padL)
                if ($maxValue -lt 4) { $maxValue = 4 }
                if ($value.Length -gt $maxValue) { $value = $value.Substring(0, $maxValue - 3) + '...' }
                $text = ' ' + $label + (' ' * $padL) + $value
                $n = $innerW - (Get-VisLen $text) - 1
                if ($n -lt 0) { $n = 0 }
                $color = 90
                if ($r[3]) { $color = 97 } elseif ($r[1] -ne 'Свободно') { $color = 91 }
                $out.Add("$Esc[36m" + $v + "$Esc[0m" + $text + (' ' * $n) + "$Esc[36m" + $v + "$Esc[0m")
            }
            'box-bottom' {
                $out.Add("$Esc[36m" + [string][char]0x2514 + ($d * ($innerW - 1)) + [string][char]0x2518 + "$Esc[0m")
            }
        }
    }
    return $out
}

function Get-TermSize {
    $w = 100; $h = 40
    try {
        if ([Console]::WindowWidth -gt 0) { $w = [Console]::WindowWidth }
        if ([Console]::WindowHeight -gt 0) { $h = [Console]::WindowHeight }
    } catch { }
    return @($w, $h)
}

function Build-Scene($grid, $state) {
    $size = Get-TermSize
    $termW = [int]$size[0]
    $termH = [int]$size[1]

    $w = [Math]::Min($script:MenuW, ($termW - 2))
    if ($w -lt 56) { $w = 56 }

    # логотип показываем, только если окно достаточно широкое и высокое
    $script:ShowArt = ($termW -ge 98) -and ($termH -ge 33)
    $leftW = $script:LeftW
    if ($script:ShowArt) {
        $script:ArtRow = 5
        $script:ArtCol = $script:LeftCol + $leftW + 2
    }

    $d = [string][char]0x2500
    $v = [string][char]0x2502
    $c = [string][char]0x250C
    $c2 = [string][char]0x2510
    $c3 = [string][char]0x2514
    $c4 = [string][char]0x2518

    $lines = New-Object System.Collections.Generic.List[string]
    $inner = $w - 2

    # ---- шапка
    $title = ' LibreWolf-USB '
    $ver = ' ' + $script:Build + ' '
    $fill = $inner - $title.Length - $ver.Length
    if ($fill -lt 2) { $fill = 2 }
    $lines.Add("$Esc[36m" + $c + $title + ($d * $fill) + $ver + $c2 + "$Esc[0m")
    $sub = ' Портативный браузер с обходом блокировок'
    $lines.Add("$Esc[36m" + $v + "$Esc[0m" + "$Esc[37m" + $sub + "$Esc[0m" + (' ' * ([Math]::Max(0, $inner - $sub.Length))) + "$Esc[36m" + $v + "$Esc[0m")
    $sub2 = ' Только vless tls/reality · без установки · профиль на флешке'
    $lines.Add("$Esc[36m" + $v + "$Esc[0m" + "$Esc[90m" + $sub2 + "$Esc[0m" + (' ' * ([Math]::Max(0, $inner - $sub2.Length))) + "$Esc[36m" + $v + "$Esc[0m")
    $lines.Add("$Esc[36m" + $c3 + ($d * $inner) + $c4 + "$Esc[0m")

    # ---- тело
    $left = @(Build-Left $state -Short:(-not $script:ShowArt))
    $art = @()
    if ($script:ShowArt) { $art = @(ConvertTo-AnsiRows $grid) }
    $bodyH = [Math]::Max($left.Count, $art.Count)
    for ($i = 0; $i -lt $bodyH; $i++) {
        $l = ''
        if ($i -lt $left.Count) { $l = $left[$i] }
        $a = ''
        if ($i -lt $art.Count) { $a = $art[$i] }
        if ($a -ne '') {
            $lines.Add((Pad-Ansi $l $leftW) + '  ' + $a)
        } else {
            $lines.Add($l)
        }
    }

    # ---- низ
    $tip = ' Подсказка: цифра + Enter. Подготовка (4) — только дома; чистка (6) — после сессии.'
    if ($tip.Length -gt $w) { $tip = $tip.Substring(0, $w - 1) }
    $lines.Add("$Esc[90m" + $tip + "$Esc[0m")
    $lines.Add("$Esc[92m" + ' Выбор > ' + "$Esc[0m")

    $script:PromptRow = $lines.Count
    $script:PromptCol = 11

    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $lines.Count; $i++) {
        [void]$sb.Append("$Esc[" + ($i + 1) + ';' + $script:LeftCol + 'H')
        [void]$sb.Append($lines[$i])
    }
    [void]$sb.Append("$Esc[0m")
    return $sb.ToString()
}

function Draw-Scene($grid, $state) {
    if ($env:SystemRoot -or $env:TERM) { Clear-Host }
    if ($script:UseAnsi) {
        [Console]::Out.Write((Build-Scene $grid $state))
        try { [Console]::SetCursorPosition(($script:PromptCol - 1), ($script:PromptRow - 1)) } catch { }
    } else {
        $lines = Build-Left $state -Short:(-not $script:ShowArt)
        $rows = Get-ArtText $grid
        Write-Host ''
        foreach ($l in $lines) { Write-Host ('  ' + ([regex]::Replace($l, "$([regex]::Escape($Esc))\[[0-9;]*m", ''))) }
        if ($script:ShowArt) { Write-Host ''; foreach ($r in $rows) { Write-Host ('  ' + $r) -ForegroundColor Cyan } }
        Write-Host ''
        Write-Host '  Выбор > ' -ForegroundColor Green -NoNewline
    }
}

# ---------------------------------------------------------------- ввод
function Read-Choice($initialGrid, $state) {
    if ([Console]::IsInputRedirected) {
        return (Read-Host).Trim()
    }

    $buf = ''
    $phase = 0.0
    $mode = 'cross'
    $other = 'scales'
    $morphLeft = 0
    $morphTotal = 16
    $nextSwitch = [DateTime]::Now.AddSeconds(30)
    $lastDraw = [DateTime]::MinValue

    $promptX = $script:PromptCol - 1
    $promptY = $script:PromptRow - 1

    while ($true) {
        $now = [DateTime]::Now
        if ($script:ShowArt -and $script:UseAnsi -and (($now - $lastDraw).TotalMilliseconds -ge 75)) {
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
                try { [Console]::SetCursorPosition($promptX, $promptY) } catch { }
                return $buf
            } elseif ($k.Key -eq 'Backspace') {
                if ($buf.Length -gt 0) {
                    $buf = $buf.Substring(0, $buf.Length - 1)
                    try { [Console]::SetCursorPosition($promptX, $promptY) } catch { }
                    Write-Host ($buf + ' ') -NoNewline
                    try { [Console]::SetCursorPosition(($promptX + $buf.Length), $promptY) } catch { }
                }
            } elseif ($k.KeyChar -match '^[0-9]$') {
                $buf += $k.KeyChar
                try { [Console]::SetCursorPosition($promptX, $promptY) } catch { }
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
    # Out-Host: вывод идёт на экран, а функция возвращает только код
    & $psExe @a | Out-Host
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
$state = Get-State
$firstGrid = Get-Frame 'cross' 0.0

while ($true) {
    Draw-Scene $firstGrid $state
    $choice = Read-Choice $firstGrid $state

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
            Write-Host '   Доп. параметры: -IgnorePolicies, -Debug (Enter — нет):' -ForegroundColor Gray
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
    if ($choice -eq '0') { $state = Get-State }
    if ($choice -eq '0') { break }
}

Clear-Host
Write-Host ''
Write-Host '   Сессия закрыта. Флешку можно вынимать.' -ForegroundColor Cyan
Write-Host ''
