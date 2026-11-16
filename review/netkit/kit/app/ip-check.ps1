# ip-check.ps1 — что о нас знают сайты: IP, страна, город, провайдер.
# Поднимает Xray на отдельном порту (браузер не запускается), спрашивает три сервиса
# через SOCKS и печатает ответы. Нужен, когда «VPN включён, а Google показывает не ту страну».
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'vless-lib.ps1')
. (Join-Path $PSScriptRoot 'secret.ps1')

$App  = $PSScriptRoot
$Root = Split-Path -Parent $App
$Vpn  = Join-Path $Root 'vpn'
$Cfg  = Join-Path $Vpn 'config.json'
$CfgEnc = $Cfg + '.enc'
$Xray = Join-Path $Vpn 'xray.exe'
$CfgDec = ''   # расшифрованная копия, если ключи под паролем

$Curl = Get-SystemExe 'curl.exe'


Head 'Проверка IP и страны'

if (-not (Test-Path $Xray)) {
    Say '  Нет vpn\xray.exe — сначала пункт 4 (подготовка дома).' 'Red'
    exit 1
}
# ключи под паролем: без пароля конфиг не прочитать (раньше пункт 9 писал «нет config.json»)
$pw = ''
if (Test-KitSecret $Vpn) {
    Say '  Ключи на флешке зашифрованы — нужен пароль.' 'Cyan'
    $pw = Read-KitPassword $Vpn
    if (-not $pw) { Say '  Пароль не введён или неверный.' 'Red'; exit 1 }
    if (-not (Test-Path $Cfg) -and (Test-Path $CfgEnc)) {
        $CfgDec = Join-Path ([IO.Path]::GetTempPath()) ('lwusb-ip-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
        if (-not (Unprotect-KitFile $CfgEnc $CfgDec $pw)) {
            Say '  vpn\config.json.enc не расшифровался: файл повреждён или пароль от другой флешки.' 'Red'
            exit 1
        }
        $Cfg = $CfgDec
    }
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

    # --- сервисы: разные базы, чтобы видеть расхождения, а не одну точку зрения ---
    $services = @(
        @{ name = 'ipinfo';   url = 'https://ipinfo.io/json';        fmt = 'json' },
        @{ name = 'ipwho.is'; url = 'https://ipwho.is/';             fmt = 'json' },
        @{ name = 'ipapi';    url = 'https://ipapi.co/json/';        fmt = 'json' },
        @{ name = 'ifconfig'; url = 'https://ifconfig.co/json';      fmt = 'json' },
        @{ name = 'myip';     url = 'https://api.myip.com';          fmt = 'json' },
        @{ name = 'cf-trace'; url = 'https://1.1.1.1/cdn-cgi/trace'; fmt = 'trace' }
    )

    function Get-Raw([string]$url) {
        $raw = & $Curl -s --max-time 12 --socks5-hostname ("127.0.0.1:" + $port) $url 2>$null
        if (-not $raw) { return '' }
        return (($raw -join "`n").Trim())
    }

    function Read-Geo($svc) {
        # Возвращает @{ip;cc;country;city;org} или $null, если сервис не ответил.
        $raw = Get-Raw $svc.url
        if (-not $raw) { return $null }
        $o = $null
        if ($svc.fmt -eq 'trace') {
            $map = @{}
            foreach ($ln in ($raw -split "`n")) {
                if ($ln -match '^([a-z_]+)=(.*)$') { $map[$Matches[1]] = $Matches[2].Trim() }
            }
            if (-not $map['ip']) { return $null }
            return @{ ip = $map['ip']; cc = "$($map['loc'])".ToUpper(); country = "$($map['loc'])".ToUpper(); city = ''; org = $map['colo'] }
        }
        try { $o = $raw | ConvertFrom-Json } catch { return $null }
        if (-not $o) { return $null }
        $ip = "$($o.ip)"
        if (-not $ip) { return $null }

        $cc = ''
        foreach ($f in @('country_code', 'cc', 'country_iso', 'countryCode')) {
            $v = "$($o.$f)"
            if ($v -match '^[A-Za-z]{2}$') { $cc = $v.ToUpper(); break }
        }
        if (-not $cc -and "$($o.country)" -match '^[A-Za-z]{2}$') { $cc = "$($o.country)".ToUpper() }

        $cname = ''
        foreach ($f in @('country_name', 'country', 'name')) {
            $v = "$($o.$f)"
            if ($v -and $v -notmatch '^[A-Za-z]{2}$') { $cname = $v; break }
        }
        if (-not $cname) { $cname = $cc }

        $city = "$($o.city)"
        $org = ''
        foreach ($f in @('org', 'isp', 'asn_org', 'asn')) {
            $v = "$($o.$f)"
            if ($v) { $org = $v; break }
        }
        if (-not $org -and $o.connection) { $org = "$($o.connection.isp)"; if (-not $org) { $org = "$($o.connection.org)" } }
        return @{ ip = $ip; cc = $cc; country = $cname; city = $city; org = $org }
    }

    $rows = @()
    foreach ($svc in $services) {
        $g = Read-Geo $svc
        $rows += [pscustomobject]@{ Name = $svc.name; Geo = $g }
    }

    $ips = @($rows | Where-Object { $_.Geo } | ForEach-Object { $_.Geo.ip } | Where-Object { $_ } | Select-Object -Unique)
    if ($ips.Count -eq 0) {
        Say '  Ни один сервис не ответил через туннель.' 'Red'
        Say '  Значит туннель поднят, но наружу не выходит — проверь сервер (пункт 2).' 'DarkGray'
        exit 1
    }

    Write-Host ''
    Write-Host ('  {0,-10} {1,-7} {2,-16} {3}' -f 'сервис', 'страна', 'город', 'провайдер') -ForegroundColor DarkGray
    $countries = @()
    foreach ($r in $rows) {
        if (-not $r.Geo) {
            Write-Host ('  {0,-10} {1}' -f $r.Name, 'нет ответа') -ForegroundColor DarkGray
            continue
        }
        $g = $r.Geo
        if ($g.cc) { $countries += $g.cc }
        Write-Host ('  {0,-10} {1,-7} {2,-16} {3}' -f $r.Name, $g.cc, $g.city, $g.org) -ForegroundColor White
    }
    Write-Host ''
    Say ('  IP через VPN: ' + $ips[0]) 'Green'

    $answered = @($rows | Where-Object { $_.Geo }).Count
    $total = $rows.Count
    $uniq = @($countries | Where-Object { $_ } | Select-Object -Unique)
    Write-Host ''
    if ($uniq.Count -gt 1) {
        Say ('  Сервисы расходятся по стране (' + ($uniq -join ', ') + '); ответили ' + $answered + ' из ' + $total + '.') 'Yellow'
        Say '  Значит IP-базы разные; Google пользуется своей и может показать третью страну.' 'Yellow'
    } elseif ($uniq.Count -eq 1) {
        $agree = ('  Страна по всем ответившим: ' + $uniq[0] + ' — согласны ' + $answered + ' из ' + $total + ' сервисов.')
        if ($answered -lt $total) {
            Say $agree 'Green'
            Say ('  Не ответили: ' + (($rows | Where-Object { -not $_.Geo } | ForEach-Object { $_.Name }) -join ', ') + ' — это нормально, часть сервисов блокирует VPN-адреса.') 'DarkGray'
        } else {
            Say $agree 'Green'
        }
    } else {
        Say ('  Ответили ' + $answered + ' из ' + $total + ', но страну не сообщил никто.') 'Yellow'
    }
} finally {
    if ($proc -and -not $proc.HasExited) {
        try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch { }
    }
    Remove-Item $tmpCfg -Force -ErrorAction SilentlyContinue
    if ($CfgDec) { Remove-Item $CfgDec -Force -ErrorAction SilentlyContinue }
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
