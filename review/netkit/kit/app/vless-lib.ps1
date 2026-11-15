# vless-lib.ps1 — общая библиотека: разбор vless:// ссылок и сборка конфига Xray
# (мульти-серверного: балансировщик leastPing + observatory).
# Подключается точкой (dot-source) из vless-to-config.ps1, update-sub.ps1 и start.ps1.
#
# Конфиг собирается объектами и ConvertTo-Json, без ручной склейки строк:
# любое значение из ссылки/подписки экранируется сериализатором, а не JsonEsc.

$script:LogLevel = 'none'   # xray: none | warning | info (start.ps1 -Debug поднимает до warning)

# полный путь к системному exe: вызовы по имени подменяются файлом из PATH/PowerShell-профиля
function Get-SystemExe([string]$Name) {
    if ($env:SystemRoot) {
        $p = Join-Path $env:SystemRoot ('System32\' + $Name)
        if (Test-Path $p) { return $p }
    }
    return $Name
}

function ConvertFrom-VlessLink([string]$Link) {
    # Возвращает [pscustomobject] с полями узла или $null (с предупреждением).
    $link = "$Link".Trim()
    if ($link -notlike 'vless://*') { Write-Warning "не vless:// ссылка — пропускаю"; return $null }
    $link = $link.Substring(8)

    $name = ''
    $pos = $link.IndexOf('#')
    if ($pos -ge 0) {
        $name = [Uri]::UnescapeDataString($link.Substring($pos + 1))
        $link = $link.Substring(0, $pos)
    }
    $query = @{}
    $pos = $link.IndexOf('?')
    if ($pos -ge 0) {
        $qs = $link.Substring($pos + 1)
        $link = $link.Substring(0, $pos)
        foreach ($pair in ($qs -split '&')) {
            if ([string]::IsNullOrEmpty($pair)) { continue }
            $k = $pair; $v = ''
            $eq = $pair.IndexOf('=')
            if ($eq -ge 0) { $k = $pair.Substring(0, $eq); $v = $pair.Substring($eq + 1) }
            $query[$k.ToLower()] = [Uri]::UnescapeDataString($v)
        }
    }
    $link = $link.Trim('/')
    if ($link -notmatch '^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})@(\[[^\]]+\]|[^:@/]+):(\d+)$') {
        Write-Warning "не удалось разобрать uuid@адрес:порт — пропускаю"
        return $null
    }
    $uuid = $Matches[1]
    $addr = $Matches[2]
    if ($addr.StartsWith('[')) { $addr = $addr.Substring(1, $addr.Length - 2) }
    $port = [int]$Matches[3]
    if ($port -lt 1 -or $port -gt 65535) { Write-Warning "порт вне диапазона — пропускаю: $addr"; return $null }

    function Q([string]$k) {
        $k = $k.ToLower()
        if ($query.ContainsKey($k)) { return "$($query[$k])" }
        return ''
    }
    $net = Q 'type';       if (-not $net) { $net = 'tcp' }
    $sec = Q 'security';   if (-not $sec) { $sec = 'none' }

    $node = [pscustomobject]@{
        uuid = $uuid; address = $addr; port = $port; name = $name
        net = $net; sec = $sec
        flow = (Q 'flow');   sni = (Q 'sni');        fp = (Q 'fp')
        host = (Q 'host');   path = (Q 'path');      serviceName = (Q 'servicename')
        alpn = (Q 'alpn');   pbk = (Q 'pbk');        sid = (Q 'sid')
        spx = (Q 'spx');     headerType = (Q 'headertype')
    }
    # Адрес 0.0.0.0 / 127.0.0.1 / :: в подписке — это заглушка: панель не выдала
    # настоящий адрес сервера (обычно потому, что не прислали x-hwid, либо адрес
    # подставляет сам клиент Happ). С таким адресом xray не подключится ни при
    # каком TLS, поэтому отбрасываем раньше проверки security — иначе в консоли
    # будет видно «security=none», хотя настоящая причина в другом.
    if ($addr -eq '0.0.0.0' -or $addr -eq '::' -or $addr -eq '127.0.0.1' -or $addr -eq 'localhost') {
        Write-Warning ("панель вернула заглушку: адрес сервера '{0}' вместо настоящего — пропускаю. Причина обычно в x-hwid (идентификатор устройства) или в том, что адрес подставляет клиент Happ." -f $addr)
        return $null
    }
    # валидация: только шифрованный транспорт.
    # security=none — это VLESS без TLS: в чужой сети содержимое видно провайдеру.
    if ($sec -ne 'tls' -and $sec -ne 'reality') {
        Write-Warning "незашифрованный узел (security=$sec) — пропускаю: $addr. Разрешены только tls и reality."
        return $null
    }
    if ($sec -eq 'reality') {
        if (-not $node.pbk) { Write-Warning "REALITY без publicKey (pbk) — пропускаю: $addr"; return $null }
        if (-not $node.sni) { Write-Warning "REALITY без serverName (sni) — пропускаю: $addr"; return $null }
    }
    return $node
}

function New-StreamSettings($Node) {
    # streamSettings как объект: значения экранирует ConvertTo-Json, а не ручной JsonEsc.
    $ss = [ordered]@{ network = "$($Node.net)"; security = "$($Node.sec)" }

    switch ("$($Node.net)") {
        'ws' {
            $p = $Node.path; if (-not $p) { $p = '/' }
            $ws = [ordered]@{ path = "$p" }
            if ($Node.host) { $ws['headers'] = [ordered]@{ Host = "$($Node.host)" } }
            $ss['wsSettings'] = $ws
        }
        'grpc' {
            $ss['grpcSettings'] = [ordered]@{ serviceName = "$($Node.serviceName)" }
        }
        'httpupgrade' {
            $p = $Node.path; if (-not $p) { $p = '/' }
            $hu = [ordered]@{ path = "$p" }
            if ($Node.host) { $hu['host'] = "$($Node.host)" }
            $ss['httpupgradeSettings'] = $hu
        }
        'tcp' {
            if ($Node.headerType -eq 'http') {
                $p = $Node.path; if (-not $p) { $p = '/' }
                $ss['tcpSettings'] = [ordered]@{
                    header = [ordered]@{
                        type = 'http'
                        request = [ordered]@{
                            path = @("$p")
                            headers = [ordered]@{ Host = @("$($Node.host)") }
                        }
                    }
                }
            }
        }
    }

    if ("$($Node.sec)" -eq 'tls') {
        $sn = $Node.sni; if (-not $sn) { $sn = $Node.host }; if (-not $sn) { $sn = $Node.address }
        $fp = $Node.fp; if (-not $fp) { $fp = 'chrome' }
        $tls = [ordered]@{ serverName = "$sn"; fingerprint = "$fp" }
        if ($Node.alpn) {
            $alpn = @("$($Node.alpn)" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            if ($alpn.Count -gt 0) { $tls['alpn'] = $alpn }
        }
        $ss['tlsSettings'] = $tls
    }
    elseif ("$($Node.sec)" -eq 'reality') {
        $fp = $Node.fp; if (-not $fp) { $fp = 'firefox' }
        $rl = [ordered]@{
            show = $false
            fingerprint = "$fp"
            serverName = "$($Node.sni)"
            publicKey = "$($Node.pbk)"
        }
        if ($Node.sid) { $rl['shortId'] = "$($Node.sid)" }
        if ($Node.spx) { $rl['spiderX'] = "$($Node.spx)" }
        $ss['realitySettings'] = $rl
    }
    return $ss
}

function New-Outbound($Node, [int]$Index) {
    # Один outbound как объект (tag proxy-N, protocol vless, vnext, streamSettings).
    $user = [ordered]@{ id = "$($Node.uuid)"; encryption = 'none' }
    if ($Node.flow -and (("$($Node.sec)" -eq 'reality') -or ("$($Node.sec)" -eq 'tls'))) {
        $user['flow'] = "$($Node.flow)"
    }
    return [ordered]@{
        tag = "proxy-$Index"
        protocol = 'vless'
        settings = [ordered]@{
            vnext = @(
                [ordered]@{
                    address = "$($Node.address)"
                    port = [int]$Node.port
                    users = @($user)
                }
            )
        }
        streamSettings = (New-StreamSettings $Node)
    }
}

function New-ConfigJson($Nodes, [int]$Only = 0) {
    # Полный конфиг: один SOCKS-inbound на loopback, N прокси, observatory
    # и routing c балансировщиком leastPing. Правило одно: весь tcp+udp -> balancer.
    #
    # -Only N: оставить ТОЛЬКО N-й сервер и убрать балансировщик. Нужно, когда сайт
    # не переносит смену выходного IP на каждом соединении (YouTube, Google):
    # leastPing выбирает узел заново для каждого нового соединения, и одна
    # страница грузится через разные адреса — сервис это рвёт.
    #
    # Намеренно нет: HTTP-inbound (лишняя дверь), udp:true (лишний UDP-ASSOCIATE),
    # outbound freedom/blackhole (прямого пути наружу быть не должно вообще).
    # loglevel=none: Xray на warning пишет адреса назначения в лог на флешке.
    $useNodes = @($Nodes)
    $oneMode = ($Only -gt 0)
    if ($oneMode) {
        if ($Only -gt $useNodes.Count) {
            throw ('Запрошен сервер ' + $Only + ', а в конфиге их ' + $useNodes.Count)
        }
        $useNodes = @($useNodes[$Only - 1])
    }
    # обычный массив, а не Generic.List: List в разных сборках PowerShell ведёт себя
    # по-разному (в PS 7.7 @() вокруг него падал с 'Argument types do not match')
    $outbounds = @()
    $i = 0
    foreach ($n in $useNodes) {
        $i++
        $outbounds += (New-Outbound $n $i)
    }
    $inbound = [ordered]@{
        tag = 'socks-in'
        listen = '127.0.0.1'
        port = 10808
        protocol = 'socks'
        settings = [ordered]@{ auth = 'noauth'; udp = $false }
        sniffing = [ordered]@{ enabled = $true; destOverride = @('http', 'tls') }
    }
    if ($oneMode) {
        $cfg = [ordered]@{
            log = [ordered]@{ loglevel = "$(if ($script:LogLevel) { $script:LogLevel } else { 'none' })" }
            inbounds = @($inbound)
            outbounds = $outbounds
            routing = [ordered]@{
                domainStrategy = 'AsIs'
                rules = @(
                    [ordered]@{ type = 'field'; network = 'tcp,udp'; outboundTag = 'proxy-1' }
                )
            }
        }
    } else {
        $cfg = [ordered]@{
            log = [ordered]@{ loglevel = "$(if ($script:LogLevel) { $script:LogLevel } else { 'none' })" }
            inbounds = @($inbound)
            outbounds = $outbounds
            observatory = [ordered]@{
                subjectSelector = @('proxy-')
                probeURL = 'https://www.gstatic.com/generate_204'
                probeInterval = '3m'
                enableConcurrency = $true
            }
            routing = [ordered]@{
                domainStrategy = 'AsIs'
                balancers = @(
                    [ordered]@{
                        tag = 'all-proxies'
                        selector = @('proxy-')
                        strategy = [ordered]@{ type = 'leastPing' }
                    }
                )
                rules = @(
                    [ordered]@{ type = 'field'; network = 'tcp,udp'; balancerTag = 'all-proxies' }
                )
            }
        }
    }

    $json = $cfg | ConvertTo-Json -Depth 12
    # Самопроверка: невалидный JSON падает здесь, а не в xray.exe на чужом ПК.
    $null = $json | ConvertFrom-Json
    return $json
}

# ---------- работа с подпиской (общее для update-sub.ps1 и start.ps1) ----------

function Read-SubParams([string]$SubFile) {
    # читает vpn\sub.txt -> @{url;hwid;ua}; $null, если файла нет или url пуст
    if (-not (Test-Path $SubFile)) { return $null }
    $p = @{ url = ''; hwid = ''; ua = 'INCY/3.0.28' }
    foreach ($ln in [IO.File]::ReadAllLines($SubFile)) {
        if ($ln -match '^\s*(\w+)\s*=\s*(.*)$') {
            switch ($Matches[1].ToLower()) {
                'url'  { $p.url  = $Matches[2].Trim() }
                'hwid' { $p.hwid = $Matches[2].Trim() }
                'ua'   { $p.ua   = $Matches[2].Trim() }
            }
        }
    }
    if (-not $p.url) { return $null }
    return $p
}

function Get-SubBody([string]$Url, [string]$Hwid, [string]$Ua, [int]$ProxyPort = 0) {
    # скачивает тело подписки (через локальный SOCKS, если ProxyPort > 0),
    # распаковывает base64 (в т.ч. без паддинга и url-safe). '' = не получилось.
    #
    # URL подписки (bearer-токен) и x-hwid НЕ идут аргументами командной строки:
    # их видно в журнале 4688, в EDR и любому процессу того же пользователя.
    # Поэтому параметры запроса уходят curl'у файлом: в командной строке виден
    # только путь. Файл лежит в %TEMP%, живёт миллисекунды и удаляется сразу
    # (в finally, даже если запрос упал).
    #
    # Почему не `curl -K -` через stdin: на Windows PowerShell 5.1 конфиг из
    # stdin приходит искажённым (curl 8.x отвечает «config file option ... is unknown»
    # и «option -K: found an unknown config option»). Проверено на живой машине.
    $script:LastSubError = ''
    if ($Url -notlike 'https://*') { Write-Warning 'URL подписки не https — отказываюсь'; return '' }
    $cfg = @(
        ('url = "{0}"' -f $Url.Replace('"', '%22')),
        'silent',
        'fail',
        'location',
        'proto = "=https"',
        'max-time = 20',
        ('header = "User-Agent: {0}"' -f $Ua)
    )
    if ($Hwid) { $cfg += ('header = "x-hwid: {0}"' -f $Hwid) }
    if ($ProxyPort -gt 0) { $cfg += ('socks5-hostname = "127.0.0.1:{0}"' -f $ProxyPort) }

    $curl = Get-SystemExe 'curl.exe'
    $cfgPath = Join-Path ([IO.Path]::GetTempPath()) ('lwusb-' + [guid]::NewGuid().ToString('N') + '.curl')
    $body = ''
    $rc = -1
    try {
        [IO.File]::WriteAllText($cfgPath, (($cfg -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding $false))
        $body = (& $curl -K $cfgPath 2>$null) -join "`n"
        $rc = $LASTEXITCODE
    } catch {
        $script:LastSubError = $_.Exception.Message
        $rc = -1
    } finally {
        Remove-Item $cfgPath -Force -ErrorAction SilentlyContinue
    }
    if ($rc -ne 0 -or [string]::IsNullOrWhiteSpace($body)) {
        if (-not $script:LastSubError) {
            $why = "curl код $rc"
            switch ($rc) {
                6  { $why = 'нет DNS: имя сервера подписки не разрешается' }
                7  { $why = 'нет соединения с сервером подписки' }
                22 { $why = 'сервер подписки ответил ошибкой (403/404/5xx) — проверь токен и x-hwid' }
                28 { $why = 'таймаут: сервер подписки не отвечает' }
                35 { $why = 'ошибка TLS (антивирус/прокси/часы Windows)' }
                56 { $why = 'соединение сброшено (прокси/антивирус)' }
            }
            $script:LastSubError = $why
        }
        return ''
    }

    $text = $body.Trim()
    if ($text -notlike '*vless://*') {
        $b = ($text -replace '\s', '').Replace('-', '+').Replace('_', '/')
        $b += '=' * ((4 - ($b.Length % 4)) % 4)
        try { $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)) }
        catch { return '' }
    }
    return $text
}

function Test-ConfigSafe($Cfg) {
    # Линтер собранного конфига: возвращает список проблем (пусто = всё в порядке).
    # Смысл: даже если конвертер или подписка принесли что-то странное, xray не
    # запустится с конфигом, в котором есть прямой выход наружу или слабый транспорт.
    $bad = @()
    foreach ($in in @($Cfg.inbounds)) {
        $listen = "$($in.listen)"
        if ($listen -ne '127.0.0.1' -and $listen -ne '::1') {
            $bad += "inbound '$($in.tag)' слушает '$listen' вместо loopback"
        }
        if ("$($in.protocol)" -ne 'socks') {
            $bad += "inbound '$($in.tag)' протокол '$($in.protocol)' (ожидается socks)"
        }
        if ($in.settings -and $in.settings.udp -eq $true) {
            $bad += "inbound '$($in.tag)': udp=true (лишний UDP-ASSOCIATE)"
        }
    }
    foreach ($ob in @($Cfg.outbounds)) {
        if ("$($ob.protocol)" -ne 'vless') {
            $bad += "outbound '$($ob.tag)': протокол '$($ob.protocol)' (разрешён только vless)"
        }
        $sec = "$($ob.streamSettings.security)"
        if ($sec -ne 'tls' -and $sec -ne 'reality') {
            $bad += "outbound '$($ob.tag)': security='$sec' (разрешены tls и reality)"
        }
    }
    foreach ($r in @($Cfg.routing.rules)) {
        if ($r.outboundTag) {
            $bad += "routing: правило с outboundTag='$($r.outboundTag)' — трафик может уйти мимо балансировщика"
        }
    }
    if (@($Cfg.routing.rules).Count -eq 0) { $bad += 'routing: нет ни одного правила (весь трафик уйдёт в первый outbound)' }
    return $bad
}

function ConvertTo-Nodes([string]$Text) {
    # текст подписки -> узлы (валидные vless://, без дублей).
    # Вызывать так: $nodes = @(ConvertTo-Nodes $text) — иначе один сервер
    # вернётся как словарь, и .Count покажет число полей, а не серверов.
    $nodes = @()
    $seen = @{}
    $body = "$Text"
    if ($body -notlike '*vless://*') {
        # тело подписки может прийти в base64 (в т.ч. url-safe и без паддинга) —
        # так отдают многие панели; Get-SubBody это уже делает, но пусть работает и тут
        $b = ($body -replace '\s', '').Replace('-', '+').Replace('_', '/')
        $b += '=' * ((4 - ($b.Length % 4)) % 4)
        try { $body = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)) } catch { $body = "$Text" }
    }
    foreach ($ln in ($body -split "`n")) {
        $ln = "$ln".Trim()
        if (-not $ln -or $ln -notlike 'vless://*') { continue }
        $n = ConvertFrom-VlessLink $ln
        if (-not $n) { continue }
        $key = "$($n.uuid)|$($n.address)|$($n.port)"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $nodes += $n
    }
    return $nodes
}
