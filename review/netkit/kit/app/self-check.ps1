# self-check.ps1 — офлайн-проверка логики комплекта.
# Ничего не скачивает, не запускает Xray, не трогает реестр и брандмауэр.
# Проверяет только конвертер VLESS-ссылок и сборку JSON — то, что чаще всего ломается.
#
# Запуск:  powershell -ExecutionPolicy Bypass -File app\self-check.ps1
# Код возврата 0 — всё в порядке, 1 — есть провалы.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'vless-lib.ps1')

$script:fail = 0
$script:pass = 0

function Check([string]$Name, $Cond, [string]$Detail = '') {
    if ($Cond) {
        Write-Host ('  [OK]   ' + $Name) -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host ('  [FAIL] ' + $Name + ' ' + $Detail) -ForegroundColor Red
        $script:fail++
    }
}

Write-Host ''
Write-Host '=== self-check: конвертер и JSON (без сети) ===' -ForegroundColor Cyan

# ---------------------------------------------------------------- ссылки
$uuid = '11111111-1111-1111-1111-111111111111'
$links = @(
    ('vless://' + $uuid + '@r.example.com:443?type=tcp&security=reality&pbk=PUBKEY123&fp=chrome&sni=r.example.com&sid=ab12&spx=%2Fprobe&flow=xtls-rprx-vision#reality-tcp'),
    ('vless://' + $uuid + '@ws.example.com:443?type=ws&security=tls&path=%2Fwspath&host=cdn.example.com&sni=ws.example.com&fp=firefox&alpn=h2%2Chttp%2F1.1#ws-tls'),
    ('vless://' + $uuid + '@hu.example.com:443?type=httpupgrade&security=reality&path=%2Fhu&host=hu.example.com&pbk=PUBKEY456&sni=hu.example.com&sid=cd34#httpupgrade'),
    ('vless://' + $uuid + '@tcp.example.com:8080?type=tcp&security=tls&sni=tcp.example.com&headerType=http&path=%2Ftp&host=tcp.example.com#tcp-http'),
    ('vless://' + $uuid + '@grpc.example.com:443?type=grpc&security=tls&serviceName=gsvc&sni=grpc.example.com#grpc'),
    ('vless://' + $uuid + '@[2001:db8::1]:8443?type=ws&security=tls&path=%2Fv6&sni=v6.example.com#ipv6')
)

$nodes = @()
foreach ($l in $links) {
    $n = ConvertFrom-VlessLink $l
    if ($n) { $nodes += $n }
}
Check ("разобрано ссылок: $($nodes.Count) из $($links.Count)") ($nodes.Count -eq $links.Count)

# security=none (VLESS без TLS) — провайдер видит содержимое; такой узел нельзя брать
$noneNode = ConvertFrom-VlessLink ('vless://' + $uuid + '@plain.example.com:8080?type=tcp&security=none#plain') 3>$null
Check 'узел без шифрования (security=none) отброшен' ($null -eq $noneNode)

# заглушка от панели: адрес 0.0.0.0 — с ним xray не подключится ни при каком TLS
$stubNode = ConvertFrom-VlessLink ('vless://' + $uuid + '@0.0.0.0:443?type=tcp&security=tls&sni=x.example.com#stub') 3>$null
Check 'узел-заглушка (адрес 0.0.0.0) отброшен' ($null -eq $stubNode)

# регистр полей в ссылке бывает любой: TLS/WS не должны отбрасываться
$up = ConvertFrom-VlessLink ('vless://' + $uuid + '@up.example.com:443?type=WS&security=TLS&sni=up.example.com#up')
Check 'парсер: type=WS и security=TLS приводятся к нижнему регистру' ($up -and $up.net -eq 'ws' -and $up.sec -eq 'tls')

$kcp = ConvertFrom-VlessLink ('vless://' + $uuid + '@kcp.example.com:443?type=kcp&security=tls&sni=k.example.com#k') 3>$null
Check 'парсер: неподдерживаемый транспорт (kcp) отброшен' ($null -eq $kcp)

$r = @($nodes | Where-Object { $_.address -eq 'r.example.com' })[0]
Check 'reality: pbk сохранён' ($r.pbk -eq 'PUBKEY123')
Check 'reality: shortId сохранён' ($r.sid -eq 'ab12')
Check 'reality: spiderX раскодирован' ($r.spx -eq '/probe')
Check 'flow сохранён' ($r.flow -eq 'xtls-rprx-vision')

$w = @($nodes | Where-Object { $_.address -eq 'ws.example.com' })[0]
Check 'ws: путь из %2F-кодировки' ($w.path -eq '/wspath')
Check 'ws: Host-заголовок' ($w.host -eq 'cdn.example.com')
Check 'ws: alpn через запятую' ($w.alpn -eq 'h2,http/1.1')

$h = @($nodes | Where-Object { $_.address -eq 'hu.example.com' })[0]
Check 'httpupgrade распознан' ($h.net -eq 'httpupgrade')

$t = @($nodes | Where-Object { $_.address -eq 'tcp.example.com' })[0]
Check 'tcp+http: headerType' ($t.headerType -eq 'http')

$g = @($nodes | Where-Object { $_.address -eq 'grpc.example.com' })[0]
Check 'grpc: serviceName' ($g.serviceName -eq 'gsvc')

$v6 = @($nodes | Where-Object { $_.address -eq '2001:db8::1' })[0]
Check 'IPv6-адрес разобран' ($null -ne $v6)

# ------------------------------------------------------------ сборка JSON
$json = New-ConfigJson $nodes
$obj = $null
try { $obj = $json | ConvertFrom-Json } catch { }
Check 'конфиг — валидный JSON' ($null -ne $obj) ('длина: ' + $json.Length)
Check 'размер конфига разумный (>1 КБ)' ($json.Length -gt 1024)

# ------------------------------------------------------------ режим одного сервера
$oneObj = (New-ConfigJson -Nodes $nodes -Only 2) | ConvertFrom-Json
Check 'режим -Only: остался один outbound' (@($oneObj.outbounds).Count -eq 1) ('их: ' + @($oneObj.outbounds).Count)
Check 'режим -Only: балансировщика нет' ($null -eq $oneObj.routing.balancers)
Check 'режим -Only: трафик идёт прямо в proxy-1' ("$($oneObj.routing.rules[0].outboundTag)" -eq 'proxy-1')

$tags = @($obj.outbounds | ForEach-Object { $_.tag })
Check ('теги outbound: ' + ($tags -join ',')) ($tags -contains 'proxy-1')
Check 'нет outbound freedom/blackhole (прямого выхода наружу нет)' ((@($tags) -contains 'direct') -eq $false -and (@($tags) -contains 'block') -eq $false)

$first = $obj.outbounds[0]
Check 'первый outbound — vless' ($first.protocol -eq 'vless')
Check 'адрес сервера на месте' ($first.settings.vnext[0].address -eq 'r.example.com')
Check 'port — число' ($first.settings.vnext[0].port -eq 443)
Check 'uuid на месте' ($first.settings.vnext[0].users[0].id -eq $uuid)
Check 'realitySettings.publicKey' ($first.streamSettings.realitySettings.publicKey -eq 'PUBKEY123')
Check 'realitySettings.spiderX' ($first.streamSettings.realitySettings.spiderX -eq '/probe')

$wsOut = @($obj.outbounds | Where-Object { $_.settings -and $_.settings.vnext -and $_.settings.vnext[0].address -eq 'ws.example.com' })[0]
Check 'wsSettings.path' ($wsOut.streamSettings.wsSettings.path -eq '/wspath')
Check 'wsHeaders.Host — массив' (@($wsOut.streamSettings.wsSettings.headers.Host)[0] -eq 'cdn.example.com')
Check 'tlsSettings.alpn — массив из двух' (@($wsOut.streamSettings.tlsSettings.alpn).Count -eq 2)

$tcpOut = @($obj.outbounds | Where-Object { $_.settings -and $_.settings.vnext -and $_.settings.vnext[0].address -eq 'tcp.example.com' })[0]
Check 'tcpSettings.header.request.path[]' (@($tcpOut.streamSettings.tcpSettings.header.request.path)[0] -eq '/tp')

$rules = @($obj.routing.rules)
Check 'routing: два правила (видео + остальное)' ($rules.Count -eq 2)
Check 'routing: видео YouTube идёт через proxy-1' ($rules[0].outboundTag -eq 'proxy-1' -and @($rules[0].domain) -contains 'domain:googlevideo.com')
Check 'routing: остальное — через balancer' ($rules[1].balancerTag -eq 'all-proxies')
# прямой путь наружу — это direct/freedom; направление на свой proxy-* — не путь наружу
Check 'routing: прямого пути наружу нет' (@($rules | Where-Object { "$($_.outboundTag)" -match '^(direct|freedom|block|blackhole)$' }).Count -eq 0)
$bal = @($obj.routing.balancers)[0]
Check 'balancer: selector по префиксу proxy-' (@($bal.selector) -contains 'proxy-')
Check 'balancer: стратегия leastPing' (($bal.strategy).type -eq 'leastPing')
Check 'observatory: следит за proxy-*' (@($obj.observatory.subjectSelector) -contains 'proxy-')
Check 'в конфиге остались только vless-outbound' (@($obj.outbounds | Where-Object { $_.protocol -ne 'vless' }).Count -eq 0)

# ------------------------------------------------------------ inbound и логи
$inb = @($obj.inbounds)
Check 'inbound ровно один' ($inb.Count -eq 1) ('их: ' + $inb.Count)
Check 'inbound — socks' ($inb[0].protocol -eq 'socks')
Check 'inbound слушает только loopback' ($inb[0].listen -eq '127.0.0.1')
Check 'udp у inbound выключен' ($inb[0].settings.udp -eq $false)
Check 'нет HTTP-inbound (10809)' (@($inb | Where-Object { $_.protocol -eq 'http' -or $_.port -eq 10809 }).Count -eq 0)
Check 'loglevel=none (адреса назначения не пишутся)' ("$($obj.log.loglevel)" -eq 'none')

# --------------------------------------------------------------- линтер
$badSelf = @(Test-ConfigSafe $obj)
Check 'линтер конфига: замечаний нет' ($badSelf.Count -eq 0) (($badSelf) -join '; ')
$evilCfg = $obj | ConvertTo-Json -Depth 12 | ConvertFrom-Json
$evilCfg.inbounds[0].listen = '0.0.0.0'
$evilCfg.outbounds[0].streamSettings.security = 'none'
$badEvil = @(Test-ConfigSafe $evilCfg)
Check ('линтер ловит плохой конфиг (замечаний: ' + $badEvil.Count + ')') ($badEvil.Count -ge 2)

# Правило может ссылаться на реальный vless-outbound, но не на выдуманный тег
$t1 = $obj | ConvertTo-Json -Depth 12 | ConvertFrom-Json
$t1.routing.rules[0].outboundTag = 'proxy-99'
Check 'линтер ловит неизвестный outboundTag' ((@(Test-ConfigSafe $t1) -join ' ') -match 'неизвестный outbound')

$t2 = $obj | ConvertTo-Json -Depth 12 | ConvertFrom-Json
$t2.routing.rules[1].balancerTag = 'ghost'
Check 'линтер ловит неизвестный balancerTag' ((@(Test-ConfigSafe $t2) -join ' ') -match 'неизвестный balancer')

$t3 = $obj | ConvertTo-Json -Depth 12 | ConvertFrom-Json
$t3.outbounds[0].settings.vnext[0].address = '0.0.0.0'
Check 'линтер ловит адрес-заглушку 0.0.0.0' ((@(Test-ConfigSafe $t3) -join ' ') -match 'заглушка')

$t4 = $obj | ConvertTo-Json -Depth 12 | ConvertFrom-Json
$t4.routing.rules[0].outboundTag = 'freedom'
Check 'линтер ловит прямой выход (freedom)' ((@(Test-ConfigSafe $t4) -join ' ') -match 'прямой выход')

# ------------------------------------------------ кавычки в значениях (F-08)
$evil = 'vless://' + $uuid + '@evil.example.com:443?type=ws&security=tls&path=%2Fa%22b%5Cc&sni=evil.example.com#evil'
$en = ConvertFrom-VlessLink $evil
$ejson = New-ConfigJson @($en)
$eobj = $null
try { $eobj = $ejson | ConvertFrom-Json } catch { }
Check 'кавычка и слэш в path не ломают JSON' ($null -ne $eobj)
if ($eobj) {
    Check 'значение path сохранено как есть' ($eobj.outbounds[0].streamSettings.wsSettings.path -eq '/a"b\c')
}

# ------------------------------------------------------------- подписка
$body = ($links -join "`n")
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($body))
$fromB64 = @(ConvertTo-Nodes $b64)
Check ('подписка base64: узлов ' + $fromB64.Count) ($fromB64.Count -eq $links.Count)
$fromTxt = @(ConvertTo-Nodes $body)
Check ('подписка текстом: узлов ' + $fromTxt.Count) ($fromTxt.Count -eq $links.Count)

# ------------------------------------------------------------- пинг серверов
$pingRes = @(Measure-ServerPing -Targets @('127.0.0.1:1') -TimeoutMs 400)
Check ('пинг закрытого порта: запись одна (' + $pingRes.Count + ')') ($pingRes.Count -eq 1)
$pingMsOk = $false
if ($pingRes.Count -ge 1) {
    # Ms должен быть числом, а не массивом: из-за вложенного массива сессия
    # падала с «Cannot convert System.Object[] to System.Int32» (F-65)
    $pingMsOk = ($pingRes[0].Ms -is [int]) -or ($pingRes[0].Ms -is [long])
}
Check 'пинг: Ms — число, а не массив' $pingMsOk
$pingFail = $false
if ($pingRes.Count -ge 1) { $pingFail = ([int]$pingRes[0].Ms -eq -1) }
Check 'пинг: закрытый порт помечен -1' $pingFail

# ------------------------------------------------------------- секреты в логах
$VpnDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'vpn'
$logDir = Join-Path $VpnDir 'logs'
$logFiles = @()
if (Test-Path $logDir) { $logFiles = @(Get-ChildItem $logDir -Filter '*.log' -File -ErrorAction SilentlyContinue) }
$logText = ''
foreach ($lf in $logFiles) {
    try { $logText += (Get-Content $lf.FullName -Raw -ErrorAction SilentlyContinue) } catch { }
}
$secretHits = @()
if ($logText -match 'vless://') { $secretHits += 'vless-ссылка' }
if ($logText -match '/sub/[A-Za-z0-9]{8,}') { $secretHits += 'URL подписки' }
Check ('в логах нет ключей и ссылки подписки (файлов: ' + $logFiles.Count + ')') ($secretHits.Count -eq 0) ($secretHits -join ', ')

# внешние адреса: IP через VPN пишется намеренно (диагностика), а ПРЯМОЙ IP — нет.
# Поэтому ругаемся только на внешний адрес в строке без пометки про VPN.
$seen = @()
$suspect = @()
foreach ($line in ($logText -split "`n")) {
    foreach ($m in [regex]::Matches($line, '\b((?:\d{1,3}\.){3}\d{1,3})\b')) {
        $ip = $m.Groups[1].Value
        if ($ip -match '^(127\.|0\.|10\.|192\.168\.|169\.254\.|255\.)') { continue }
        if ($ip -match '^172\.(1[6-9]|2[0-9]|3[01])\.') { continue }
        $seen += $ip
        $isVpnIp = ($line -match 'VPN|сменился|обновление успешно|откат успешен')
        if (-not $isVpnIp) { $suspect += ($ip + ' в строке: ' + $line.Trim()) }
    }
}
$seenCount = @($seen | Select-Object -Unique).Count
Check ('в логах нет прямого IP (адреса через VPN не в счёт; внешних найдено: ' + $seenCount + ')') ($suspect.Count -eq 0) (($suspect | Select-Object -First 2) -join '; ')

# ----------------------------------------------------------------- пароль на ключи
. (Join-Path $PSScriptRoot 'secret.ps1')
$scDir = New-KitTempDir 'lwusb-scheck'
try {
    Set-KitPasswordValue $scDir 'проверка-кдф-2026'
    $scMeta = Read-KitHeaders (Get-KitSecretFile $scDir)
    Check ('KDF: в secret.dat записан prf=' + "$($scMeta['prf'])") ("$($scMeta['prf'])" -eq (Get-KitPrfTag))
    Check 'KDF: верный пароль проходит, неверный — нет' ((Test-KitPassword $scDir 'проверка-кдф-2026') -and (-not (Test-KitPassword $scDir 'другой-пароль-1')))
} finally {
    Remove-KitTempDir $scDir | Out-Null
}

# ----------------------------------------------------------------- итог
Write-Host ''
if ($script:fail -eq 0) {
    Write-Host ("ВСЁ ХОРОШО: $($script:pass) проверок пройдено.") -ForegroundColor Green
    exit 0
} else {
    Write-Host ("ПРОВАЛОВ: $($script:fail) из $($script:pass + $script:fail). Пришли этот вывод — поправлю.") -ForegroundColor Red
    exit 1
}
