# logo.ps1 — символьные логотипы TempleOS с анимацией для menu.ps1.
# Два вида: крест с плащаницей (ткань качается) и весы с мечом (чаши качаются).
# Морфинг между ними — плавная интерполяция "плотности" символов.

$Esc = [char]27

$ArtW = 32
$ArtH = 24

# индекс цвета 0..15 (как в ANSI/консоли)
$ColDefault = 8
$ColOf = @{
    '#' = 1   # тёмно-синий
    ':' = 3   # тёмно-бирюзовый
    '%' = 14  # жёлтый
    '&' = 6   # тёмно-жёлтый
    'o' = 15  # белый
    '~' = 7   # серый
    '|' = 7   # цепочка
    '_' = 14  # борт чаши
    '/' = 6
    '\' = 6
    '.' = 3
}
# плотность символа (для морфинга)
$Dens = @{
    ' ' = 0.0; '.' = 0.12; ':' = 0.25; '|' = 0.35; '-' = 0.35; '~' = 0.5; 'o' = 0.62;
    '_' = 0.7; '/' = 0.72; '\' = 0.72; '%' = 0.85; '&' = 0.92; '#' = 1.0
}
$DensChars = @(
    @(0.06,' '), @(0.18,'.'), @(0.30,':'), @(0.40,'|'), @(0.55,'~'),
    @(0.68,'o'), @(0.78,'%'), @(0.90,'&'), @(1.01,'#')
)

function New-Grid {
    $g = [char[]]::new($ArtW * $ArtH)
    $c = [int[]]::new($ArtW * $ArtH)
    for ($i = 0; $i -lt $g.Length; $i++) { $g[$i] = ' '; $c[$i] = $ColDefault }
    return @{ Ch = $g; Co = $c }
}

function Set-Px($grid, [int]$x, [int]$y, [char]$ch) {
    if ($x -lt 0 -or $y -lt 0 -or $x -ge $ArtW -or $y -ge $ArtH) { return }
    $i = $y * $ArtW + $x
    $grid.Ch[$i] = $ch
    $col = 8
    if ($ColOf.ContainsKey([string]$ch)) { $col = $ColOf[[string]$ch] }
    $grid.Co[$i] = $col
}

function Fill-Rect($grid, [int]$x0, [int]$y0, [int]$x1, [int]$y1, [char]$ch) {
    for ($y = $y0; $y -le $y1; $y++) {
        for ($x = $x0; $x -le $x1; $x++) { Set-Px $grid $x $y $ch }
    }
}

function Initialize-Background($grid) {
    Fill-Rect $grid 0 0 ($ArtW-1) ($ArtH-1) ':'
    for ($x = 0; $x -lt $ArtW; $x++) {
        Set-Px $grid $x 0 '#'
        Set-Px $grid $x ($ArtH-1) '#'
    }
    for ($y = 0; $y -lt $ArtH; $y++) {
        Set-Px $grid 0 $y '#'
        Set-Px $grid ($ArtW-1) $y '#'
    }
}

# ---------------------------------------------------------------- крест
function Get-CrossGrid([double]$phase) {
    $g = New-Grid
    Initialize-Background $g

    # перекладина и балка
    Fill-Rect $g 2 8 29 10 '%'
    Fill-Rect $g 14 2 18 21 '%'
    # объём
    for ($y = 2; $y -le 21; $y++) { Set-Px $g 18 $y '&' }
    for ($x = 2; $x -le 29; $x++) { Set-Px $g $x 10 '&' }

    # накидка: качается верхним краем
    $lift = [int][math]::Round(0.6 * [math]::Sin($phase))
    Fill-Rect $g 12 (6 + $lift) 20 (6 + $lift) 'o'
    Fill-Rect $g 10 (7 + $lift) 22 (7 + $lift) 'o'
    foreach ($x in @(12, 16, 20)) { Set-Px $g $x (7 + $lift) '~' }

    # свисающие концы ткани: качаются от ветра
    $dxL = [int][math]::Round(1.4 * [math]::Sin($phase))
    $dxR = [int][math]::Round(1.4 * [math]::Sin($phase + 1.2))
    $lenL = 17 + [int][math]::Round(1.2 * [math]::Sin($phase + 2.0))
    $lenR = 17 + [int][math]::Round(1.2 * [math]::Sin($phase + 2.9))

    for ($y = 11; $y -le $lenL; $y++) {
        $w = 2 - [int][math]::Floor(($y - 11) / 6)
        for ($k = 0; $k -le [math]::Max(0, $w); $k++) {
            Set-Px $g (10 + $dxL + $k) $y 'o'
        }
    }
    for ($y = 11; $y -le $lenR; $y++) {
        $w = 2 - [int][math]::Floor(($y - 11) / 6)
        for ($k = 0; $k -le [math]::Max(0, $w); $k++) {
            Set-Px $g (20 + $dxR + $k) $y 'o'
        }
    }
    # складки
    for ($y = 12; $y -le 16; $y += 2) {
        Set-Px $g (11 + $dxL) $y '~'
        Set-Px $g (21 + $dxR) $y '~'
    }
    return $g
}

# ---------------------------------------------------------------- весы и меч
function Get-ScalesGrid([double]$phase) {
    $g = New-Grid
    Initialize-Background $g

    # меч наискось в нижней трети, под чашами (толщина 2)
    for ($y = 13; $y -le 22; $y++) {
        $x = [int][math]::Round(5 + (22 - $y) * (21.0 / 9.0))
        Set-Px $g $x $y 'o'
        Set-Px $g ($x + 1) $y 'o'
        Set-Px $g ($x + 2) $y '~'
    }
    # гарда, рукоять, навершие
    Fill-Rect $g 3 21 9 21 '&'
    Fill-Rect $g 5 22 7 22 '&'
    Set-Px $g 4 20 '&'; Set-Px $g 8 20 '&'

    # навес-шатёр
    Fill-Rect $g 14 2 17 2 '%'
    Fill-Rect $g 12 3 19 3 '%'
    Fill-Rect $g 10 4 21 4 '%'
    Fill-Rect $g 8 5 23 5 '%'
    Fill-Rect $g 6 6 25 6 '%'
    for ($x = 7; $x -le 24; $x += 3) { Set-Px $g $x 7 '&' }

    # чаши качаются вверх-вниз в противофазе
    $yL = 12 + [int][math]::Round(1.4 * [math]::Sin($phase))
    $yR = 12 + [int][math]::Round(1.4 * [math]::Sin($phase + [math]::PI))

    foreach ($p in @(@(10, $yL), @(22, $yR))) {
        $cx = $p[0]; $cy = $p[1]
        for ($y = 7; $y -lt $cy - 1; $y++) { Set-Px $g $cx $y '|' }
        Set-Px $g ($cx - 3) ($cy - 1) '/'
        Set-Px $g ($cx + 3) ($cy - 1) '\'
        Fill-Rect $g ($cx - 2) ($cy - 1) ($cx + 2) ($cy - 1) '%'
        Fill-Rect $g ($cx - 3) $cy ($cx + 3) $cy '_'
    }
    return $g
}

# ---------------------------------------------------------------- морфинг
function Get-Frame([string]$kind, [double]$phase) {
    if ($kind -eq 'scales') { return Get-ScalesGrid $phase }
    return Get-CrossGrid $phase
}

function Get-DensityChar([double]$v) {
    foreach ($pair in $DensChars) {
        if ($v -lt $pair[0]) { return [char]$pair[1] }
    }
    return [char]'#'
}

function Get-MorphGrid($a, $b, [double]$t) {
    $out = New-Grid
    for ($y = 0; $y -lt $ArtH; $y++) {
        # волна: нижние строки переходят позже верхних
        $w = $t * 1.6 - ($y / $ArtH) * 0.6
        if ($w -lt 0) { $w = 0 } elseif ($w -gt 1) { $w = 1 }
        for ($x = 0; $x -lt $ArtW; $x++) {
            $i = $y * $ArtW + $x
            # общий фон и рамка не растворяются
            if ($a.Ch[$i] -eq $b.Ch[$i]) {
                $out.Ch[$i] = $a.Ch[$i]
                $out.Co[$i] = $a.Co[$i]
                continue
            }
            $base = 0.26   # плотность фона: фигуры растворяются в поле, а не в чёрное
            if ($w -lt 0.5) {
                # старый логотип растворяется
                $da = $base
                if ($Dens.ContainsKey([string]$a.Ch[$i])) { $da = [math]::Max($base, $Dens[[string]$a.Ch[$i]]) }
                $v = $base + ($da - $base) * (1 - $w * 2)
                $out.Ch[$i] = Get-DensityChar $v
                $out.Co[$i] = $a.Co[$i]
            } else {
                # новый собирается
                $db = $base
                if ($Dens.ContainsKey([string]$b.Ch[$i])) { $db = [math]::Max($base, $Dens[[string]$b.Ch[$i]]) }
                $v = $base + ($db - $base) * (($w - 0.5) * 2)
                $out.Ch[$i] = Get-DensityChar $v
                $out.Co[$i] = $b.Co[$i]
            }
        }
    }
    return $out
}

# ---------------------------------------------------------------- вывод
function Get-Sgr([int]$c) {
    if ($c -lt 8) { return (30 + $c) }
    return (90 + $c - 8)
}

function ConvertTo-AnsiRows($grid) {
    $rows = New-Object System.Collections.Generic.List[string]
    for ($y = 0; $y -lt $ArtH; $y++) {
        $sb = New-Object System.Text.StringBuilder
        $cur = -1
        for ($x = 0; $x -lt $ArtW; $x++) {
            $i = $y * $ArtW + $x
            $col = $grid.Co[$i]
            if ($col -ne $cur) {
                [void]$sb.Append("$Esc[" + (Get-Sgr $col) + 'm')
                $cur = $col
            }
            [void]$sb.Append($grid.Ch[$i])
        }
        [void]$sb.Append("$Esc[0m")
        $rows.Add($sb.ToString())
    }
    return $rows
}

function Get-ArtText($grid) {
    $rows = @()
    for ($y = 0; $y -lt $ArtH; $y++) {
        $rows += (-join $grid.Ch[($y * $ArtW)..(($y + 1) * $ArtW - 1)])
    }
    return $rows
}
