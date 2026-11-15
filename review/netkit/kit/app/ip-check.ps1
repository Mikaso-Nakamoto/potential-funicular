# ip-check.ps1 — что о нас знают сайты: IP, страна, город, провайдер.
# Поднимает Xray на отдельном порту (браузер не запускается), спрашивает три сервиса
# через SOCKS и печатает ответы. Нужен, когда «VPN включён, а Google показывает не ту страну».
$ErrorActionPreference = 'Stop'

$App  = $PSScriptRoot
$Root = Split-Path -Parent $App
$Vpn  = Join-Path $Root 'vpn'
$Cfg  = Join-Path $Vpn 'config.json'
$Xray = Join-Path $Vpn 'xray.exe'

function Say([string]$t, [string]$c = 'Gray') { Write-Host $t -ForegroundColor $c }
function Head([string]$t) { Write-Host ''; Say ('=== ' + $t + ' ===') 'Cyan' }

function Get-SystemExe([string]$Name) {
    if ($env:SystemRoot) {
        $p = Join-Path $env:SystemRoot ('System32\' + $Name)
        if (Test-Path $p) { return $p }
    }
    return $Name
}
$Curl = Get-SystemExe 'curl.exe'

function Get-FreePort {
    for ($i = 0; $i -lt 40; $i++) {
        $p = Get-Random -Minimum 20000 -Maximum 60000
        $l = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $p)
        try { $l.Start(); $l.Stop(); return $p } catch { try { $l.Stop() } catch { } }
    }
    return 0
}

Head 'Проверка IP и страны'

if (-not (Test-Path $Xray)) {
    Say '  Нет vpn\xray.exe — сначала пункт 4 (подготовка дома).' 'Red'
    exit 1
}
if (-not (Test-Path $Cfg)) {
    Say '  Нет vpn\config.json — сначала пункт 3 или 4.' 'Red'
    exit 1
}

$port = Get-FreePort
if ($port -le 0) { Say '  Не удалось выбрать свободный порт.' 'Red'; exit 1 }

# копия конфига со своим портом, во временной папке
$tmpCfg = Join-Path ([IO.Path]::GetTempPath()) ('lwusb-check-' + [guid]::NewGuid().ToString('N') + '.json')
$proc = $null
try {
    $obj = Get-Content $Cfg -Raw -Encoding UTF8 | ConvertFrom-Json
    $obj.inbounds[0].port = $port
    $json = $obj | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($tmpCfg, $json, (New-Object System.Text.UTF8Encoding $false))

    Say ('  Поднимаю туннель на порту ' + $port + '...') 'DarkGray'
    $proc = Start-Process -FilePath $Xray -ArgumentList @('-c', ('"' + $tmpCfg + '"')) `
            -WorkingDirectory $Vpn -WindowStyle Hidden -PassThru

    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        try {
            $c = New-Object Net.Sockets.TcpClient
            $t = $c.ConnectAsync('127.0.0.1', $port)
            if ($t.Wait(500) -and $c.Connected) { $ready = $true; $c.Dispose(); break }
            $c.Dispose()
        } catch { }
        if ($proc.HasExited) { break }
    }
    if (-not $ready) {
        Say '  Туннель не поднялся: сервера не отвечают или конфиг битый.' 'Red'
        exit 1
    }

    function Get-Json([string]$url) {
        $raw = & $Curl -s --max-time 15 --socks5-hostname ("127.0.0.1:" + $port) $url 2>$null
        if (-not $raw) { return $null }
        try { return (($raw -join '') | ConvertFrom-Json) } catch { return $null }
    }

    $a = Get-Json 'https://ipinfo.io/json'
    $b = Get-Json 'https://api.myip.com'
    $c2 = Get-Json 'https://ipapi.co/json/'

    $ip = ''
    if ($a) { $ip = "$($a.ip)" } elseif ($c2) { $ip = "$($c2.ip)" } elseif ($b) { $ip = "$($b.ip)" }

    if (-not $ip) {
        Say '  Ни один сервис не ответил через туннель.' 'Red'
        exit 1
    }

    Write-Host ''
    Write-Host ('  {0,-10} {1,-8} {2,-18} {3}' -f 'сервис', 'страна', 'город', 'провайдер') -ForegroundColor DarkGray
    $countries = @()
    if ($a) {
        $countries += "$($a.country)"
        Write-Host ('  {0,-10} {1,-8} {2,-18} {3}' -f 'ipinfo', "$($a.country)", "$($a.city)", "$($a.org)") -ForegroundColor White
    }
    if ($b) {
        $countries += "$($b.cc)"
        Write-Host ('  {0,-10} {1,-8} {2,-18} {3}' -f 'myip', "$($b.cc)", '', "$($b.country)") -ForegroundColor White
    }
    if ($c2) {
        $countries += "$($c2.country_code)"
        Write-Host ('  {0,-10} {1,-8} {2,-18} {3}' -f 'ipapi', "$($c2.country_code)", "$($c2.city)", "$($c2.org)") -ForegroundColor White
    }
    Write-Host ''
    Say ('  Ваш IP через VPN: ' + $ip) 'Green'

    $uniq = @($countries | Where-Object { $_ } | Select-Object -Unique)
    if ($uniq.Count -gt 1) {
        Say ('  Внимание: сервисы расходятся по стране (' + ($uniq -join ', ') + ').') 'Yellow'
        Say '  Значит IP-базы разные; Google пользуется своей и может показать третью страну.' 'Yellow'
    } elseif ($uniq.Count -eq 1) {
        Say ('  Все сервисы согласны: ' + $uniq[0]) 'Green'
    }
} finally {
    if ($proc -and -not $proc.HasExited) {
        try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch { }
    }
    Remove-Item $tmpCfg -Force -ErrorAction SilentlyContinue
}

Head 'Почему Google может показывать другую страну'
Say '  1. Cookie профиля. Google запоминает страну в cookie (NID/PREF) и не меняет её' 'Gray'
Say '     при смене IP. Проверка: Ctrl+Shift+P (приватное окно) → google.com → «где я».' 'Gray'
Say '     Если там Нидерланды/Швеция, а в обычном окне Россия — виноват профиль.' 'Gray'
Say '  2. DNS-подсказка. Firefox спрашивает домены через VPN-сервер, а тот может отдавать' 'Gray'
Say '     свою подсеть, по которой Google угадывает страну. Совпадает с пунктом 1 по эффекту.' 'Gray'
Say '  3. База Google. Для части «серых» IP Google считает страной место регистрации' 'Gray'
Say '     провайдера, даже если остальные сервисы показывают Амстердам.' 'Gray'
Write-Host ''
Say '  Что делать: приватное окно для проверки, другой сервер (пункт 2) или очистка' 'Yellow'
Say '  cookie Google. На работу туннеля это не влияет — меняется только гео-подсказка.' 'Yellow'
Write-Host ''
exit 0
