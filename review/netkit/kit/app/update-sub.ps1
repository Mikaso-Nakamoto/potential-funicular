# update-sub.ps1 — обновление серверов VPN из подписки (api.giont.ru / Happ).
# ЗАПУСКАТЬ ТОЛЬКО ДОМА: запрос к API идёт напрямую (не через VPN).
# Данные подписки (url, hwid) хранятся в vpn\sub.txt на флешке — тоже секрет,
# на колледжном ПК не открывать.
# (В колледже обновление происходит само — START.bat подтягивает подписку
#  ЧЕРЕЗ туннель, если конфигу больше 3 дней.)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'vless-lib.ps1')

$Vpn    = Join-Path (Split-Path -Parent $PSScriptRoot) 'vpn'
$SubFile= Join-Path $Vpn 'sub.txt'
$OutFile= Join-Path $Vpn 'config.json'

function Fail([string]$m) { Write-Host "[X] $m" -ForegroundColor Red; exit 1 }

# --- параметры подписки (url / hwid / ua) ---
$p = Read-SubParams $SubFile
if (-not $p) {
    $url  = Read-Host 'URL подписки (https://api.../sub/...)'
    $hwid = Read-Host 'x-hwid (GUID клиента; Enter — не отправлять)'
    $ua   = 'INCY/3.0.28'
    $url  = "$url".Trim()
    $hwid = "$hwid".Trim()
    if ($url -notlike 'https://*') { Fail 'URL подписки должен начинаться с https://' }
    New-Item -ItemType Directory -Force -Path $Vpn | Out-Null
    [IO.File]::WriteAllText($SubFile, "url=$url`r`nhwid=$hwid`r`nua=$ua`r`n", (New-Object System.Text.UTF8Encoding $false))
    $p = @{ url = $url; hwid = $hwid; ua = $ua }
}

# --- скачиваем и разбираем ---
Write-Host "[..] Запрашиваю подписку..."
$text = Get-SubBody $p.url $p.hwid $p.ua 0
if (-not $text) {
    $why = "сеть/URL/заголовки"
    if ($script:LastSubError) { $why = $script:LastSubError + "; проверь URL и x-hwid" }
    Fail ("Не удалось получить подписку ($why). config.json НЕ тронут.")
}

$nodes = @(ConvertTo-Nodes $text)
if ($nodes.Count -eq 0) {
    Write-Host "[!] В подписке не нашлось узлов, которые можно положить в конфиг" -ForegroundColor Red
    Write-Host "    (без шифрования или с адресом-заглушкой 0.0.0.0)." -ForegroundColor Red
    Fail "config.json НЕ тронут. Проверь vpn\sub.txt: url должен быть вида https://.../sub/ТОКЕН, hwid — непустой. Токен мог отозваться — перевыпусти подписку в кабинете."
}

# --- пишем конфиг (с бэкапом) ---
$json = New-ConfigJson $nodes
if (Test-Path $OutFile) {
    Copy-Item $OutFile ($OutFile + '.bak.json') -Force
    Write-Host "[i] Старый конфиг — в config.bak.json" -ForegroundColor DarkGray
}
[System.IO.File]::WriteAllText($OutFile, $json, (New-Object System.Text.UTF8Encoding $false))

Write-Host ""
Write-Host "[+] Готово: $($nodes.Count) сервер(ов) записано в vpn\config.json" -ForegroundColor Green
$i = 0
foreach ($n in $nodes) {
    $i++
    Write-Host ("    proxy-{0}: {1}:{2}  sni={3}  [{4}/{5}]" -f $i, $n.address, $n.port, $n.sni, $n.net, $n.sec)
}
Write-Host "[i] Проверить связность можно дома: START.bat — он покажет внешний IP через VPN."
