# ui-bar.ps1 — полоса загрузки в стиле TempleOS: зелёная заливка,
# над ней меняется иероглиф (анх, глаз Хора, весы, скарабей, перо, пирамида).

$script:BarGlyphs = @(
    @(' (o) ', '  |  ', ' -+- '),   # анх
    @(' ___ ', '(o o)', ' \_/ '),   # глаз Хора
    @(' \_/ ', '--+--', '  |  '),   # весы
    @(' .o. ', '(oOo)', " '-' "),   # скарабей
    @('  /\ ', '  || ', '  \/ '),   # перо Маат
    @('  /\ ', ' /  \', '/____\')    # пирамида
)

$script:BarWidth = 26
$script:BarFilled = [string][char]0x2588   # █
$script:BarEmpty  = [string][char]0x2591   # ░

function Format-Size([double]$bytes) {
    if ($bytes -ge 1GB) { return ([math]::Round($bytes / 1GB, 1)).ToString() + ' ГБ' }
    if ($bytes -ge 1MB) { return ([math]::Round($bytes / 1MB, 1)).ToString() + ' МБ' }
    if ($bytes -ge 1KB) { return ([math]::Round($bytes / 1KB, 0)).ToString() + ' КБ' }
    return ([int]$bytes).ToString() + ' Б'
}

function Put-Text([int]$x, [int]$y, [string]$text, [string]$color = 'Gray') {
    try {
        [Console]::SetCursorPosition($x, $y)
        Write-Host $text -ForegroundColor $color -NoNewline
    } catch {
        $script:NoPos = $true
        Write-Host $text -ForegroundColor $color -NoNewline
    }
}

function Show-BarFrame([int]$top, [int]$glyph, [string]$label, [double]$done, [double]$total, [double]$speed, [switch]$Counts) {
    $pct = 0
    if ($total -gt 0) { $pct = [int](100 * $done / $total); if ($pct -gt 100) { $pct = 100 } }
    $fill = [int]($script:BarWidth * $pct / 100)
    if ($fill -lt 0) { $fill = 0 }
    $empty = $script:BarWidth - $fill

    $g = $script:BarGlyphs[$glyph % $script:BarGlyphs.Count]

    Put-Text 2 $top $g[0] 'Cyan'
    $head = $label
    if ($Counts) {
        $head += '   ' + [int]$done + ' из ' + [int]$total
    } elseif ($total -gt 0) {
        $head += '   ' + (Format-Size $done) + ' из ' + (Format-Size $total)
    } else {
        $head += '   ' + (Format-Size $done)
    }
    Put-Text 9 $top $head 'Gray'

    Put-Text 2 ($top + 1) $g[1] 'Cyan'
    if ($fill -gt 0) { Put-Text 9 ($top + 1) ($script:BarFilled * $fill) 'Green' }
    if ($empty -gt 0) { Put-Text (9 + $fill) ($top + 1) ($script:BarEmpty * $empty) 'DarkGray' }
    Put-Text (9 + $script:BarWidth + 2) ($top + 1) ($pct.ToString() + '%') 'Yellow'
    if ($speed -gt 0 -and -not $Counts) { Put-Text (9 + $script:BarWidth + 7) ($top + 1) ((Format-Size $speed) + '/с') 'DarkGray' }

    Put-Text 2 ($top + 2) $g[2] 'Cyan'
    $tail = ''
    if ($total -gt 0 -and $speed -gt 1) {
        $left = ($total - $done) / $speed
        if ($left -lt 0) { $left = 0 }
        if ($left -ge 60) { $tail = 'осталось ~' + [math]::Round($left / 60, 0) + ' мин' }
        else { $tail = 'осталось ~' + [math]::Round($left, 0) + ' с' }
    }
    Put-Text 9 ($top + 2) $tail 'DarkGray'
}

function Clear-BarArea([int]$top, [int]$lines) {
    for ($i = 0; $i -lt $lines; $i++) {
        try {
            [Console]::SetCursorPosition(0, $top + $i)
            Write-Host (' ' * 76) -NoNewline
        } catch { }
    }
}

function Invoke-DownloadBar([string]$Curl, [string]$Url, [string]$Out, [string]$Label) {
    $total = 0
    # Content-Length: берём последний (после редиректов)
    try {
        $lines = & $Curl -sIL --max-time 20 $Url 2>$null
        $lenLine = @($lines | Where-Object { $_ -match '^\s*[Cc]ontent-[Ll]ength:\s*(\d+)' })
        if ($lenLine.Count -gt 0) {
            $m = [regex]::Match($lenLine[$lenLine.Count - 1], '(\d+)')
            if ($m.Success) { $total = [int64]$m.Groups[1].Value }
        }
    } catch { }

    $argList = @('-L', '--fail', '--proto', '=https', '--tlsv1.2', '--retry', '3',
                 '--connect-timeout', '20', '-s', '-o', ('"' + $Out + '"'), $Url)

    $canDraw = $true
    try { $null = [Console]::CursorTop } catch { $canDraw = $false }
    if ([Console]::IsOutputRedirected) { $canDraw = $false }

    $top = 0
    if ($canDraw) { $top = [Console]::CursorTop }

    $proc = Start-Process -FilePath $Curl -ArgumentList $argList -PassThru -NoNewWindow
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $lastSize = 0
    $lastTime = 0.0
    $speed = 0.0
    $glyph = 0
    $lastDraw = [DateTime]::MinValue

    while (-not $proc.HasExited) {
        Start-Sleep -Milliseconds 120
        $size = 0
        if (Test-Path $Out) {
            try { $size = (Get-Item $Out).Length } catch { }
        }
        $now = $sw.Elapsed.TotalSeconds
        if ($now - $lastTime -ge 0.5) {
            $speed = ($size - $lastSize) / ($now - $lastTime)
            $lastSize = $size
            $lastTime = $now
        }
        if ($canDraw -and ((Get-Date) - $lastDraw).TotalMilliseconds -ge 110) {
            Show-BarFrame $top $glyph $Label $size $total $speed
            $glyph++
            $lastDraw = Get-Date
            if ($script:NoPos) { $canDraw = $false; Write-Host '' }
        } elseif (-not $canDraw -and ((Get-Date) - $lastDraw).TotalMilliseconds -ge 700) {
            # без позиционирования — простая строка раз в 0,7 с
            $pct2 = 0
            if ($total -gt 0) { $pct2 = [int](100 * $size / $total) }
            $line = '   ' + $Label + '  ' + $pct2 + '%  ' + (Format-Size $size)
            if ($total -gt 0) { $line += ' из ' + (Format-Size $total) }
            Write-Host $line
            $lastDraw = Get-Date
        }
    }

    $final = 0
    if (Test-Path $Out) { try { $final = (Get-Item $Out).Length } catch { } }
    if ($canDraw -and -not $script:NoPos) {
        Show-BarFrame $top $glyph $Label $final $total 0
        Start-Sleep -Milliseconds 120
        Clear-BarArea $top 3
        try { [Console]::SetCursorPosition(2, $top) } catch { }
        Write-Host ('   [ok] ' + $Label + '  ' + (Format-Size $final)) -ForegroundColor Green
    } else {
        Write-Host ('   [ok] ' + $Label + '  ' + (Format-Size $final)) -ForegroundColor Green
    }
    return $proc.ExitCode
}
