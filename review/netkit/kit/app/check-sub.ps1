# check-sub.ps1 — ДИАГНОСТИКА подписки: показывает, что РЕАЛЬНО приходит от панели.
#
# Зачем: если панель отдаёт заглушки (адрес 0.0.0.0) или узлы без шифрования,
# конвертер отбрасывает их, и человек видит только «нет валидных узлов».
# Этот скрипт печатает разбор всех строк подписки: адрес, порт, транспорт,
# security, sni, есть ли pbk — и говорит, что из этого годится.
#
# ЗАПУСКАТЬ ДОМА: запрос идёт напрямую, без туннеля.
# Ничего не меняет: vpn\config.json не трогает.
# Токен подписки и UUID узлов в вывод и в отчёт НЕ попадают (маскируются).
#
# Запуск:  ПРОВЕРКА-ПОДПИСКИ.bat   или   powershell -ExecutionPolicy Bypass -File app\check-sub.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'vless-lib.ps1')

$Root    = Split-Path -Parent $PSScriptRoot
$Vpn     = Join-Path $Root 'vpn'
$SubFile = Join-Path $Vpn 'sub.txt'
$Report  = Join-Path $Vpn 'sub-report.txt'
$script:lines = @()

function Add-Line([string]$m) {
    Write-Host $m
    $script:lines += $m
}

function Mask-Url([string]$u) {
    try {
        $i = $u.LastIndexOf('/')
        if ($i -lt 0) { return '(скрыт)' }
        $tail = $u.Substring($i + 1)
        if ($tail.Length -gt 4) { $tail = '***' + $tail.Substring($tail.Length - 4) }
        return $u.Substring(0, $i) + '/' + $tail
    } catch { return '(скрыт)' }
}

# разбор ссылки «как есть» — без фильтров, чтобы было видно и плохое
function Get-RawNode([string]$line) {
    $body = $line.Substring(8)
    $name = ''
    $h = $body.IndexOf('#')
    if ($h -ge 0) { $name = [Uri]::UnescapeDataString($body.Substring($h + 1)); $body = $body.Substring(0, $h) }
    $uri = $null
    try { $uri = [Uri]('vless://' + $body) } catch { return $null }
    if (-not $uri.Host) { return $null }
    $q = @{}
    $qs = "$($uri.Query)".TrimStart('?')
    foreach ($pair in ($qs -split '&')) {
        if (-not $pair) { continue }
        $k = $pair; $v = ''
        $eq = $pair.IndexOf('=')
        if ($eq -ge 0) { $k = $pair.Substring(0, $eq); $v = $pair.Substring($eq + 1) }
        $q[$k.ToLower()] = [Uri]::UnescapeDataString($v)
    }
    $sec = "$($q['security'])"; if (-not $sec) { $sec = 'none' }
    $net = "$($q['type'])";     if (-not $net) { $net = 'tcp' }
    $pbk = "$($q['pbk'])"; $sni = "$($q['sni'])"

    $verdict = 'годен'
    if ($uri.Host -eq '0.0.0.0' -or $uri.Host -eq '::' -or $uri.Host -eq '127.0.0.1') {
        $verdict = 'заглушка: адреса сервера нет'
    } elseif ($sec -ne 'tls' -and $sec -ne 'reality') {
        $verdict = 'без шифрования (' + $sec + ')'
    } elseif ($sec -eq 'reality' -and (-not $pbk -or -not $sni)) {
        $verdict = 'REALITY без pbk/sni'
    }

    return [pscustomobject]@{
        name = $name; address = $uri.Host; port = $uri.Port
        net = $net; sec = $sec; sni = $sni; pbk = $pbk; verdict = $verdict
    }
}

function Get-NodesFrom([string]$text) {
    $raw = @($text -split "`n" | Where-Object { "$_".Trim() -like 'vless://*' })
    $nodes = @()
    foreach ($l in $raw) { $n = Get-RawNode $l.Trim(); if ($n) { $nodes += $n } }
    return ,@($nodes)
}

function Show-Table($nodes) {
    Add-Line '  №   адрес:порт                     тип        security  sni                 вердикт'
    Add-Line '  --- ------------------------------ ---------- --------- ------------------- ------------------------------'
    $i = 0
    foreach ($n in $nodes) {
        $i++
        if ($i -gt 40) { break }
        $ap = "$($n.address):$($n.port)".PadRight(30)
        $net = "$($n.net)".PadRight(10)
        $sec = "$($n.sec)".PadRight(9)
        $sni = "$($n.sni)"; if (-not $sni) { $sni = '-' }
        $sni = $sni.PadRight(19)
        Add-Line ("  {0,3} {1} {2} {3} {4} {5}" -f $i, $ap, $net, $sec, $sni, $n.verdict)
    }
    if ($nodes.Count -gt 40) { Add-Line ("  ... ещё {0} строк" -f ($nodes.Count - 40)) }
}

Write-Host ''
Write-Host '=== Диагностика подписки (ничего не меняет) ===' -ForegroundColor Cyan
Write-Host ''

$p = Read-SubParams $SubFile
if (-not $p) {
    Write-Host 'Нет vpn\sub.txt — введи URL подписки (он не сохранится, это разовая проверка).' -ForegroundColor Yellow
    $url = "$(Read-Host 'URL подписки (https://...)')".Trim()
    if ($url -notlike 'https://*') { Write-Host '[X] URL должен начинаться с https://' -ForegroundColor Red; exit 1 }
    $p = @{ url = $url; hwid = ''; ua = 'INCY/3.0.28' }
}

Add-Line ('URL:        ' + (Mask-Url $p.url))
if ($p.hwid) { Add-Line 'x-hwid:     отправляется (задан)' } else { Add-Line 'x-hwid:     НЕ отправляется (пусто)' }
Add-Line ('User-Agent: ' + $p.ua)
Add-Line ''

Write-Host '[..] Запрашиваю подписку...' -ForegroundColor DarkGray
$text = Get-SubBody $p.url $p.hwid $p.ua 0
if (-not $text) {
    Add-Line ('[X] Подписку получить не удалось: ' + $script:LastSubError)
    Add-Line '    Проверь: интернет, правильность URL, не истёк ли токен.'
    $script:lines | Set-Content -Path $Report -Encoding UTF8
    exit 1
}

$rawCount = @($text -split "`n" | Where-Object { "$_".Trim() -like 'vless://*' }).Count
Add-Line ("тело ответа: {0} символов, строк vless://: {1}" -f $text.Length, $rawCount)
Add-Line ''

if ($rawCount -eq 0) {
    Add-Line '[!] В ответе нет ни одной строки vless:// — панель вернула не список серверов.'
    Add-Line '    Обычно это значит: истёк токен, подписка заблокирована или URL не тот.'
    $script:lines | Set-Content -Path $Report -Encoding UTF8
    exit 1
}

$nodes = Get-NodesFrom $text
Show-Table $nodes
Add-Line ''

$good  = @($nodes | Where-Object { $_.verdict -eq 'годен' })
$stub  = @($nodes | Where-Object { $_.verdict -like 'заглушка*' })
$plain = @($nodes | Where-Object { $_.verdict -like 'без шифрования*' })

Add-Line ("Годных узлов для комплекта: {0} из {1}" -f $good.Count, $nodes.Count)

# --- проверка с x-hwid, если он не задан: часто именно он «раскрывает» заглушки
if ($good.Count -eq 0 -and -not $p.hwid -and -not [Console]::IsInputRedirected) {
    Add-Line ''
    Write-Host 'Если в кабинете провайдера видно «5 из 5» (или другой лимит устройств), панель' -ForegroundColor Yellow
    Write-Host 'именно поэтому и отдаёт нули. HWID уже подключённого устройства решает это без' -ForegroundColor Yellow
    Write-Host 'нового слота — введи его ниже (в Happ: настройки / «о приложении»).' -ForegroundColor Yellow
    $h = "$(Read-Host 'введи его, чтобы проверить подписку с ним (Enter — пропустить)')".Trim()
    if ($h) {
        Write-Host '[..] Повторяю запрос с x-hwid...' -ForegroundColor DarkGray
        $text2 = Get-SubBody $p.url $h $p.ua 0
        if (-not $text2) {
            Add-Line ('[!] С x-hwid запрос не удался: ' + $script:LastSubError)
        } else {
            $nodes2 = Get-NodesFrom $text2
            $good2 = @($nodes2 | Where-Object { $_.verdict -eq 'годен' })
            Add-Line ''
            Add-Line ("С x-hwid: строк vless:// {0}, годных {1} (было {2} из {3})" -f $nodes2.Count, $good2.Count, $good.Count, $nodes.Count)
            Show-Table $nodes2
            if ($good2.Count -gt 0) {
                Add-Line ''
                Add-Line '[+] С x-hwid панель отдала рабочие узлы — этот HWID нужно записать в vpn\sub.txt.'
                $save = "$(Read-Host 'Записать этот x-hwid в vpn\sub.txt? (y/n)')".Trim()
                if ($save -eq 'y' -or $save -eq 'Y' -or $save -eq 'да') {
                    $ua = $p.ua
                    [IO.File]::WriteAllText($SubFile, ("url={0}`r`nhwid={1}`r`nua={2}`r`n" -f $p.url, $h, $ua), (New-Object System.Text.UTF8Encoding $false))
                    Add-Line 'Записано в vpn\sub.txt — теперь запускай ПОДГОТОВКА-ДОМА.bat.'
                }
            } else {
                Add-Line ''
                Add-Line '[!] С x-hwid тоже нет годных узлов — дело не в HWID.'
            }
        }
    }
}

if ($good.Count -eq 0) {
    Add-Line ''
    if ($stub.Count -gt 0) {
        Add-Line '[!] Панель отдала ЗАГЛУШКИ: адрес сервера 0.0.0.0 вместо настоящего.'
        Add-Line '    Так бывает в двух случаях:'
        Add-Line '      1) подписка привязана к устройству — нужен x-hwid;'
        Add-Line '      2) адрес сервера подставляет сам клиент Happ при подключении — тогда'
        Add-Line '         нужна прямая ссылка vless:// с адресом от провайдера.'
    }
    if ($plain.Count -gt 0) {
        Add-Line ('[!] Узлы без шифрования (security=none): {0} шт. Комплект их не берёт —' -f $plain.Count)
        Add-Line '    в чужой сети содержимое такого туннеля видно провайдеру.'
    }
    Add-Line ''
    Add-Line 'Почему так: панели считают не адреса, а УСТРОЙСТВА (по x-hwid). Лимит вида'
    Add-Line '«5 из 5» означает, что все слоты заняты телефонами/ПК, и на незнакомое'
    Add-Line 'устройство панель отдаёт заглушку 0.0.0.0. Совпадение IP здесь не помогает:'
    Add-Line 'с того же адреса, но без «своего» HWID — это всё равно новое устройство.'
    Add-Line ''
    Add-Line 'Что делать по порядку:'
    Add-Line '  1. открой кабинет/бот провайдера и посмотри список устройств (там же лимит).'
    Add-Line '     Удали те, которыми не пользуешься, — освободи слот;'
    Add-Line '  2. возьми HWID одного из ОСТАВШИХСЯ устройств (в Happ он показан в настройках/'
    Add-Line '     «о приложении», у провайдера — в списке устройств) и введи его в этом'
    Add-Line '     скрипте при повторном запуске: если адреса появятся — запиши HWID в sub.txt;'
    Add-Line '  3. если слотов нет и освобождать нечего — попроси у провайдера ещё одно'
    Add-Line '     устройство или прямую ссылку vless:// с адресом и портом;'
    Add-Line '  4. прямую ссылку можно вставить в app\vless-to-config.ps1 (по одной, Enter,'
    Add-Line '     потом пустая строка) — конфиг соберётся без подписки.'
    Add-Line ''
    Add-Line 'Важно: HWID нужен ОДИН и постоянный. Если каждый раз подставлять новый,'
    Add-Line 'каждое обновление подписки будет занимать новый слот — и лимит кончится снова.'
} else {
    Add-Line ''
    Add-Line 'Всё в порядке: запускай ПОДГОТОВКА-ДОМА.bat (или app\update-sub.ps1) — комплект соберёт конфиг.'
}

Add-Line ''
Add-Line ('Отчёт сохранён: ' + $Report)
$script:lines | Set-Content -Path $Report -Encoding UTF8
Write-Host ''
Write-Host 'Готово.' -ForegroundColor Green
