# update-sub.ps1 — обновление серверов VPN из подписки (api.giont.ru / Happ).
# ЗАПУСКАТЬ ТОЛЬКО ДОМА: запрос к API идёт напрямую (не через VPN).
# Данные подписки (url, hwid) хранятся в vpn\sub.txt на флешке — тоже секрет,
# на колледжном ПК не открывать.
# (В колледже обновление происходит само — START.bat подтягивает подписку
#  ЧЕРЕЗ туннель, если конфигу больше 3 дней.)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'vless-lib.ps1')
. (Join-Path $PSScriptRoot 'secret.ps1')

$Vpn    = Join-Path (Split-Path -Parent $PSScriptRoot) 'vpn'
$SubFile= Join-Path $Vpn 'sub.txt'
$OutFile= Join-Path $Vpn 'config.json'
$SubEnc = $SubFile + '.enc'
$CfgEnc = $OutFile + '.enc'


# --- пароль флешки (если задан): без него не читаем sub.txt и не пишем config.json ---
$KitLock = Enter-KitLock 0
if (-not $KitLock) {
    Write-Host '[X] Комплект уже работает в другом окне. Обновление подписки не запускаю.' -ForegroundColor Red
    exit 1
}

$pw = ''
if (Test-KitSecret $Vpn) {
    Write-Host '[i] Ключи на флешке зашифрованы — нужен пароль.' -ForegroundColor Cyan
    $pw = Read-KitPassword $Vpn
    if (-not $pw) { Fail 'Пароль не введён или неверный. Ничего не изменено.' }
}

# --- параметры подписки (url / hwid / ua): из sub.txt или из его .enc ---
$SubRead = $SubFile
$SubTmp = ''
$SubDir = ''
if ($pw -and (Test-Path $SubEnc)) {
    $SubDir = New-KitTempDir 'lwusb-sub'
    $SubTmp = Join-Path $SubDir 'sub.txt'
    if (-not (Unprotect-KitFile $SubEnc $SubTmp $pw)) { Fail 'vpn\sub.txt.enc не расшифровался: файл повреждён или пароль от другой флешки.' }
    $SubRead = $SubTmp
}
$p = Read-SubParams $SubRead
if ($SubDir) { Remove-KitTempDir $SubDir | Out-Null }
if (-not $p) {
    $url  = Read-Host 'URL подписки (https://api.../sub/...)'
    $hwid = Read-Host 'x-hwid (GUID клиента; Enter — не отправлять)'
    $ua   = 'INCY/3.0.28'
    $url  = "$url".Trim()
    $hwid = "$hwid".Trim()
    if ($url -notlike 'https://*') { Fail 'URL подписки должен начинаться с https://' }
    New-Item -ItemType Directory -Force -Path $Vpn | Out-Null
    [IO.File]::WriteAllText($SubFile, "url=$url`r`nhwid=$hwid`r`nua=$ua`r`n", (New-Object System.Text.UTF8Encoding $false))
    # ссылку вставляли из буфера (Ctrl+V) — там осталась копия с токеном, и она же
    # попадает в историю буфера Windows (Win+V). Стираем.
    try { Set-Clipboard -Value ' ' -ErrorAction SilentlyContinue } catch { }
    Write-Host '[i] Буфер обмена очищен: вставленная ссылка с токеном там больше не лежит.' -ForegroundColor DarkGray
    if ($pw) { Protect-KitFile $SubFile $pw $SubEnc | Out-Null; Write-Host '[i] sub.txt зашифрован (sub.txt.enc), открытый удалён.' -ForegroundColor DarkGray }
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
# под паролем открытого config.json нет — старый бэкап делаем из зашифрованного,
# иначе «сохранён предыдущий конфиг» остаётся пустым обещанием
if ($pw -and -not (Test-Path $OutFile) -and (Test-Path $CfgEnc) -and -not (Test-Path ($OutFile + '.bak.json'))) {
    if (Unprotect-KitFile $CfgEnc ($OutFile + '.bak.json') $pw) {
        Write-Host "[i] Старый конфиг — в config.json.bak.json" -ForegroundColor DarkGray
    }
}
if (Test-Path $OutFile) {
    Copy-Item $OutFile ($OutFile + '.bak.json') -Force
    Write-Host "[i] Старый конфиг — в config.bak.json" -ForegroundColor DarkGray
}
[System.IO.File]::WriteAllText($OutFile, $json, (New-Object System.Text.UTF8Encoding $false))

if ($pw) {
    Protect-KitFile $OutFile $pw $CfgEnc | Out-Null
    if (Test-Path ($OutFile + '.bak.json')) {
        Protect-KitFile ($OutFile + '.bak.json') $pw ($Vpn + '\config.json.bak.json.enc') | Out-Null
    }
    Write-Host '[i] Конфиг зашифрован: vpn\config.json.enc (открытый удалён).' -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "[+] Готово: $($nodes.Count) сервер(ов) записано в vpn\$(if ($pw) { 'config.json.enc' } else { 'config.json' })" -ForegroundColor Green
$i = 0
foreach ($n in $nodes) {
    $i++
    Write-Host ("    proxy-{0}: {1}:{2}  sni={3}  [{4}/{5}]" -f $i, $n.address, $n.port, $n.sni, $n.net, $n.sec)
}
Write-Host "[i] Проверить связность можно дома: START.bat — он покажет внешний IP через VPN."
