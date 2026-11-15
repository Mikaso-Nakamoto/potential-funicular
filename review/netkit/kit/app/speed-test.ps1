# speed-test.ps1 — замер скорости КАЖДОГО сервера из vpn\config.json.
# Нужен, чтобы не перебирать вручную START.bat -Server 1..N, а увидеть цифры.
# Адреса серверов в вывод не попадают — только номера (инвариант: без адресов в логах).
param(
    [int]$Megabytes = 5,      # сколько скачать через каждый сервер
    [int]$TimeoutSec = 25
)

$ErrorActionPreference = 'Stop'
$App  = $PSScriptRoot
$Root = Split-Path -Parent $App
$Vpn  = Join-Path $Root 'vpn'
$Cfg  = Join-Path $Vpn 'config.json'
$Xray = Join-Path $Vpn 'xray.exe'

function Say([string]$text, [string]$color = 'Gray') { Write-Host $text -ForegroundColor $color }

function Get-SystemExe([string]$Name) {
    if ($env:SystemRoot) {
        $p = Join-Path $env:SystemRoot ('System32\' + $Name)
        if (Test-Path $p) { return $p }
    }
    return $Name
}
$Curl = Get-SystemExe 'curl.exe'

function Get-FreeTcpPort {
    for ($i = 0; $i -lt 40; $i++) {
        $p = Get-Random -Minimum 20000 -Maximum 60000
        try {
            $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $p)
            $l.Start(); $l.Stop()
            return $p
        } catch { }
    }
    return 0
}

function Wait-TcpPort([int]$P, [int]$Seconds = 20) {
    for ($i = 0; $i -lt ($Seconds * 4); $i++) {
        try {
            $c = New-Object System.Net.Sockets.TcpClient
            $c.Connect('127.0.0.1', $P)
            $c.Close()
            return $true
        } catch { Start-Sleep -Milliseconds 250 }
    }
    return $false
}

Say ''
Say '=== Скорость серверов ===' 'Cyan'
Say ''

if (-not (Test-Path $Cfg)) { Say '[X] Нет vpn\config.json — сначала сделай конфиг дома.' 'Red'; exit 1 }
if (-not (Test-Path $Xray)) { Say '[X] Нет vpn\xray.exe — сначала ПОДГОТОВКА-ДОМА.bat.' 'Red'; exit 1 }

$baseCfg = Get-Content $Cfg -Raw -Encoding UTF8 | ConvertFrom-Json
$all = @($baseCfg.outbounds)
$count = $all.Count
if ($count -lt 1) { Say '[X] В config.json нет серверов.' 'Red'; exit 1 }

Say ('серверов в конфиге: ' + $count + ', через каждый скачаю ' + $Megabytes + ' МБ') 'White'
Say ''

$bytes = $Megabytes * 1048576
$url = 'https://speed.cloudflare.com/__down?bytes=' + $bytes
$results = @()

for ($n = 1; $n -le $count; $n++) {
    $port = Get-FreeTcpPort
    if ($port -le 0) { Say '[X] Не нашёл свободный порт.' 'Red'; break }

    # сессионный конфиг: один узел, без балансировщика
    $one = Get-Content $Cfg -Raw -Encoding UTF8 | ConvertFrom-Json
    $pick = @($one.outbounds)[$n - 1]
    $tag = "$($pick.tag)"
    $one.outbounds = @($pick)
    $one.inbounds[0].port = $port
    $one.routing = [ordered]@{
        domainStrategy = 'AsIs'
        rules = @([ordered]@{ type = 'field'; network = 'tcp,udp'; outboundTag = $tag })
    }
    try { $one.PSObject.Properties.Remove('observatory') } catch {}

    $tmpCfg = Join-Path ([IO.Path]::GetTempPath()) ('lwusb-speed-' + $n + '-' + $port + '.json')
    $outLog = $tmpCfg + '.out.log'
    $errLog = $tmpCfg + '.err.log'
    [IO.File]::WriteAllText($tmpCfg, ($one | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding $false))

    Say ('[..] сервер ' + $n + ': поднимаю туннель...') 'DarkGray'
    $spArgs = @{
        FilePath = $Xray
        ArgumentList = @('-c', ('"' + $tmpCfg + '"'))
        WorkingDirectory = $Vpn
        PassThru = $true
        RedirectStandardOutput = $outLog
        RedirectStandardError = $errLog
    }
    if ($env:SystemRoot) { $spArgs['WindowStyle'] = 'Hidden' }
    $proc = Start-Process @spArgs
    try {
        if (-not (Wait-TcpPort $port 20)) {
            Say ('     сервер ' + $n + ': туннель не поднялся') 'Red'
            $results += [pscustomobject]@{ N = $n; MBps = 0; Sec = 0; Ok = $false }
            continue
        }

        # задержка: лёгкий запрос 204
        $lat = & $Curl -s --max-time $TimeoutSec --socks5-hostname ('127.0.0.1:' + $port) `
            -o NUL -w '%{time_total}' 'https://www.gstatic.com/generate_204' 2>$null
        $latMs = 0
        if ("$lat" -match '^[0-9.]+$') { $latMs = [int]([double]$lat * 1000) }

        $res = & $Curl -s --max-time $TimeoutSec --socks5-hostname ('127.0.0.1:' + $port) `
            -o NUL -w '%{size_download} %{time_total}' $url 2>$null
        $ok = $false; $mbps = 0; $sec = 0
        if ("$res" -match '^(\d+)\s+([0-9.]+)$') {
            $got = [int64]$Matches[1]
            $sec = [double]$Matches[2]
            if ($got -gt 0 -and $sec -gt 0) {
                $mbps = [Math]::Round(($got / 1MB) / $sec, 2)
                $ok = $true
            }
        }
        $results += [pscustomobject]@{ N = $n; MBps = $mbps; Sec = [Math]::Round($sec, 1); Ms = $latMs; Ok = $ok }
        if ($ok) { Say ('     сервер ' + $n + ': ' + $mbps + ' МБ/с, отклик ' + $latMs + ' мс') 'Green' }
        else { Say ('     сервер ' + $n + ': не отдал данные') 'Yellow' }
    }
    finally {
        try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
        Start-Sleep -Milliseconds 300
        foreach ($f in @($tmpCfg, $outLog, $errLog)) {
            Remove-Item $f -Force -ErrorAction SilentlyContinue
        }
    }
}

Say ''
if ($results.Count -eq 0) { Say 'Замеров нет.' 'Yellow'; exit 1 }

Say '--- итог ---' 'Cyan'
foreach ($r in $results) {
    if ($r.Ok) { Say ('  сервер ' + $r.N + ':  ' + $r.MBps + ' МБ/с   (' + $r.Sec + ' с на ' + $Megabytes + ' МБ)') }
    else { Say ('  сервер ' + $r.N + ':  не работает') 'Red' }
}

$best = @($results | Where-Object { $_.Ok } | Sort-Object -Property MBps -Descending) | Select-Object -First 1
Say ''
if ($best) {
    Say ('Лучший: сервер ' + $best.N + ' (' + $best.MBps + ' МБ/с).') 'Green'
    Say ("Запуск с ним:  START.bat -Server " + $best.N) 'Green'
    if ($best.MBps -lt 2) {
        Say 'Скорость низкая у всех: это ограничение серверов подписки, а не флешки или браузера.' 'Yellow'
    }
} else {
    Say 'Ни один сервер не отдал данные. Проверь подписку: ПРОВЕРКА-ПОДПИСКИ.bat' 'Red'
}
Say ''
