# logo.ps1 — пиксельные логотипы TempleOS для консоли (полублоки ▀).
# Каждый символ несёт два пикселя по вертикали, поэтому картинка 40x48
# выглядит гладко, а не «из букв».

$script:W = 40
$script:H = 48
$script:LogoW = 40
$script:LogoH = 24

$script:CH = @{
    BG = 3    # тёмно-бирюзовое поле
    FR = 1    # синяя рамка
    GD = 14   # золото (крест, шатёр, чаши)
    GK = 6    # тёмное золото (объём)
    SH = 15   # белая плащаница
    FL = 7    # серые складки, цепочки
    BL = 15   # клинок
    DK = 8    # тень
}

function New-Pix {
    $p = [int[]]::new($script:W * $script:H)
    for ($i = 0; $i -lt $p.Length; $i++) { $p[$i] = $script:CH.BG }
    return $p
}

function Set-Px($pix, [int]$x, [int]$y, [int]$color) {
    if ($x -lt 0 -or $y -lt 0 -or $x -ge $script:W -or $y -ge $script:H) { return }
    $pix[$y * $script:W + $x] = $color
}

function Get-Px($pix, [int]$x, [int]$y) {
    if ($x -lt 0 -or $y -lt 0 -or $x -ge $script:W -or $y -ge $script:H) { return $script:CH.BG }
    return $pix[$y * $script:W + $x]
}

function Fill-Rect($pix, [int]$x0, [int]$y0, [int]$x1, [int]$y1, [int]$color) {
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) { Set-Px $pix $x $y $color }
    }
}

function Fill-RoundRect($pix, [int]$x0, [int]$y0, [int]$x1, [int]$y1, [int]$r, [int]$color) {
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) {
            $dx = 0; $dy = 0
            if ($x -lt $x0 + $r) { $dx = $x0 + $r - $x } elseif ($x -gt $x1 - $r) { $dx = $x - ($x1 - $r) }
            if ($y -lt $y0 + $r) { $dy = $y0 + $r - $y } elseif ($y -gt $y1 - $r) { $dy = $y - ($y1 - $r) }
            if ($dx * $dx + $dy * $dy -le $r * $r) { Set-Px $pix $x $y $color }
        }
    }
}

function Fill-Tri($pix, [int]$x0, [int]$y0, [int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$color) {
    $minY = [math]::Min($y0, [math]::Min($y1, $y2))
    $maxY = [math]::Max($y0, [math]::Max($y1, $y2))
    for ($y = $minY; $y -le $maxY; $y++) {
        $xs = @()
        foreach ($e in @(@($x0, $y0, $x1, $y1), @($x1, $y1, $x2, $y2), @($x2, $y2, $x0, $y0))) {
            $ax = $e[0]; $ay = $e[1]; $bx = $e[2]; $by = $e[3]
            if (($ay -le $y -and $by -ge $y) -or ($by -le $y -and $ay -ge $y)) {
                if ($ay -eq $by) { $xs += $ax; $xs += $bx; continue }
                $t = ($y - $ay) / [double]($by - $ay)
                $xs += [int][math]::Round($ax + ($bx - $ax) * $t)
            }
        }
        if ($xs.Count -ge 2) {
            $lo = ($xs | Measure-Object -Minimum).Minimum
            $hi = ($xs | Measure-Object -Maximum).Maximum
            for ($x = $lo; $x -le $hi; $x++) { Set-Px $pix $x $y $color }
        }
    }
}

function Draw-Line($pix, [int]$x0, [int]$y0, [int]$x1, [int]$y1, [int]$thick, [int]$color) {
    $steps = [math]::Max([math]::Abs($x1 - $x0), [math]::Abs($y1 - $y0))
    if ($steps -eq 0) { $steps = 1 }
    for ($i = 0; $i -le $steps; $i++) {
        $t = $i / [double]$steps
        $x = [int][math]::Round($x0 + ($x1 - $x0) * $t)
        $y = [int][math]::Round($y0 + ($y1 - $y0) * $t)
        for ($dy = 0; $dy -lt $thick; $dy++) { Set-Px $pix ($x) ($y + $dy) $color }
    }
}

function Fill-Ellipse($pix, [int]$cx, [int]$cy, [int]$rx, [int]$ry, [int]$color) {
    for ($y = $cy - $ry; $y -le $cy + $ry; $y++) {
        for ($x = $cx - $rx; $x -le $cx + $rx; $x++) {
            $dx = ($x - $cx) / [double]$rx
            $dy = ($y - $cy) / [double]$ry
            if ($dx * $dx + $dy * $dy -le 1.0) { Set-Px $pix $x $y $color }
        }
    }
}

function Initialize-Field($pix) {
    Fill-Rect $pix 0 0 ($script:W - 1) ($script:H - 1) $script:CH.BG
    # рамка в один символ (2 пикселя)
    Fill-Rect $pix 0 0 ($script:W - 1) 1 $script:CH.FR
    Fill-Rect $pix 0 ($script:H - 2) ($script:W - 1) ($script:H - 1) $script:CH.FR
    Fill-Rect $pix 0 0 1 ($script:H - 1) $script:CH.FR
    Fill-Rect $pix ($script:W - 2) 0 ($script:W - 1) ($script:H - 1) $script:CH.FR
}

# ---------------------------------------------------------------- крест
function Get-CrossFrame([double]$phase) {
    $pix = New-Pix
    Initialize-Field $pix

    $bx0 = 15; $bx1 = 24      # балка
    $ry0 = 14; $ry1 = 23      # перекладина

    # балка и перекладина
    Fill-RoundRect $pix $bx0 4 $bx1 45 3 $script:CH.GD
    Fill-RoundRect $pix 3 $ry0 36 $ry1 3 $script:CH.GD

    # объём: правая грань балки и нижняя грань перекладины
    Fill-Rect $pix $bx1 6 $bx1 44 $script:CH.GK
    Fill-Rect $pix 4 $ry1 35 $ry1 $script:CH.GK
    # тонкая тень под крестом
    Fill-Rect $pix ($bx1 + 1) 8 ($bx1 + 1) 45 $script:CH.DK
    Fill-Rect $pix 4 ($ry1 + 1) 36 ($ry1 + 1) $script:CH.DK

    # накидка на перекладине (провисает)
    $lift = [int][math]::Round(1.5 * [math]::Sin($phase))
    Fill-RoundRect $pix 8 (10 + $lift) 31 (17 + $lift) 3 $script:CH.SH
    Fill-Rect $pix 8 (17 + $lift) 31 (18 + $lift) $script:CH.SH

    # свисающие концы: качаются вразнобой
    $dxL = [int][math]::Round(2.0 * [math]::Sin($phase))
    $dxR = [int][math]::Round(2.0 * [math]::Sin($phase + 1.3))
    $lenL = 34 + [int][math]::Round(2.0 * [math]::Sin($phase + 2.1))
    $lenR = 34 + [int][math]::Round(2.0 * [math]::Sin($phase + 3.0))

    for ($y = 18; $y -le $lenL; $y++) {
        $w = 5 - [int][math]::Floor(($y - 18) / 7)
        if ($w -lt 2) { $w = 2 }
        Fill-Rect $pix (6 + $dxL) $y (6 + $dxL + $w) $y $script:CH.SH
    }
    for ($y = 18; $y -le $lenR; $y++) {
        $w = 5 - [int][math]::Floor(($y - 18) / 7)
        if ($w -lt 2) { $w = 2 }
        Fill-Rect $pix (29 + $dxR) $y (29 + $dxR + $w) $y $script:CH.SH
    }
    # складки
    for ($y = 20; $y -le 32; $y += 4) {
        Set-Px $pix (7 + $dxL) $y $script:CH.FL
        Set-Px $pix (30 + $dxR) $y $script:CH.FL
    }
    return $pix
}

# ---------------------------------------------------------------- весы и меч
function Get-ScalesFrame([double]$phase) {
    $pix = New-Pix
    Initialize-Field $pix

    # меч наискось внизу: клинок и блик
    Draw-Line $pix 5 45 31 25 4 $script:CH.BL
    Draw-Line $pix 6 45 32 25 1 $script:CH.GK
    # гарда и рукоять
    Draw-Line $pix 2 43 9 40 2 $script:CH.GD
    Draw-Line $pix 3 45 7 48 2 $script:CH.GK

    # шатёр
    Fill-Tri $pix 20 6 5 16 35 16 $script:CH.GD
    Fill-Rect $pix 6 16 34 17 $script:CH.GK

    # чаши качаются в противофазе
    $yL = 30 + [int][math]::Round(3.0 * [math]::Sin($phase))
    $yR = 30 + [int][math]::Round(3.0 * [math]::Sin($phase + [math]::PI))

    foreach ($c in @(@(12, $yL), @(28, $yR))) {
        $cx = $c[0]; $cy = $c[1]
        Draw-Line $pix $cx 17 $cx ($cy - 5) 1 $script:CH.FL
        Fill-Ellipse $pix $cx $cy 6 3 $script:CH.GD
        Fill-Rect $pix ($cx - 6) ($cy - 3) ($cx + 6) ($cy - 3) $script:CH.GK
    }
    return $pix
}

# ---------------------------------------------------------------- морфинг
function Get-MorphFrame($a, $b, [double]$t) {
    $out = [int[]]::new($script:W * $script:H)
    for ($i = 0; $i -lt $out.Length; $i++) {
        $ca = $a[$i]; $cb = $b[$i]
        if ($ca -eq $cb) { $out[$i] = $ca; continue }
        if ($t -lt 0.5) {
            # старый растворяется в поле
            $k = 1 - $t * 2
            if ($k -lt 0.55) { $out[$i] = $script:CH.BG }
            elseif ($k -lt 0.8) { $out[$i] = $script:CH.DK }
            else { $out[$i] = $ca }
        } else {
            $k = ($t - 0.5) * 2
            if ($k -lt 0.25) { $out[$i] = $script:CH.BG }
            elseif ($k -lt 0.5) { $out[$i] = $script:CH.DK }
            else { $out[$i] = $cb }
        }
    }
    return $out
}

# ---------------------------------------------------------------- рендер
function Get-AnsiFg([int]$c) {
    $map = @(30, 34, 32, 36, 31, 35, 33, 37, 90, 94, 92, 96, 91, 95, 93, 97)
    return $map[$c]
}

function Get-AnsiBg([int]$c) {
    $map = @(40, 44, 42, 46, 41, 45, 43, 47, 100, 104, 102, 106, 101, 105, 103, 107)
    return $map[$c]
}

# превращает пиксельную сетку в строки ANSI: ▀ несёт два пикселя по вертикали
function ConvertTo-AnsiRows($pix) {
    $Esc = [char]27
    $rows = New-Object System.Collections.Generic.List[string]
    for ($y = 0; $y -lt $script:H; $y += 2) {
        $sb = New-Object System.Text.StringBuilder
        $x = 0
        while ($x -lt $script:W) {
            $i1 = $y * $script:W + $x
            $i2 = ($y + 1) * $script:W + $x
            $top = $pix[$i1]; $bot = $pix[$i2]
            $j = $x
            if ($top -eq $bot) {
                while ($j -lt $script:W -and $pix[$y * $script:W + $j] -eq $top -and $pix[($y + 1) * $script:W + $j] -eq $top) { $j++ }
                [void]$sb.Append("$Esc[" + (Get-AnsiFg $top) + 'm')
                for ($k = $x; $k -lt $j; $k++) { [void]$sb.Append([char]0x2588) }
            } else {
                while ($j -lt $script:W -and
                       (($pix[$y * $script:W + $j] -eq $top -and $pix[($y + 1) * $script:W + $j] -eq $bot) -or
                        ($pix[$y * $script:W + $j] -eq $bot -and $pix[($y + 1) * $script:W + $j] -eq $top))) { $j++ }
                [void]$sb.Append("$Esc[" + (Get-AnsiFg $top) + "m" + "$Esc[" + (Get-AnsiBg $bot) + 'm')
                for ($k = $x; $k -lt $j; $k++) {
                    $t2 = $pix[$y * $script:W + $k]
                    if ($t2 -eq $top) { [void]$sb.Append([char]0x2580) }
                    else { [void]$sb.Append([char]0x2584) }
                }
            }
            $x = $j
        }
        [void]$sb.Append("$Esc[0m")
        $rows.Add($sb.ToString())
    }
    return $rows
}

function Get-ArtText($pix) {
    # текстовый дамп для отладки: по символу на пару пикселей
    $chars = ' ', '.', ':', '+', '*', '#'
    $rows = @()
    for ($y = 0; $y -lt $script:H; $y += 2) {
        $line = ''
        for ($x = 0; $x -lt $script:W; $x++) {
            $c1 = $pix[$y * $script:W + $x]
            $c2 = $pix[($y + 1) * $script:W + $x]
            $bg = $script:CH.BG
            $v = 0
            if ($c1 -ne $bg) { $v++ }
            if ($c2 -ne $bg) { $v++ }
            $line += $chars[[math]::Min($v, 5)]
        }
        $rows += $line
    }
    return $rows
}


function Get-Frame([string]$kind, [double]$phase) {
    if ($kind -eq 'scales') { return Get-ScalesFrame $phase }
    return Get-CrossFrame $phase
}

function Get-MorphGrid($a, $b, [double]$t) {
    return Get-MorphFrame $a $b $t
}
