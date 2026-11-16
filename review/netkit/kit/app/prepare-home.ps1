# prepare-home.ps1 — ДОМАШНЯЯ подготовка флешки LibreWolf-USB.
# Скачивает LibreWolf (portable) с GitLab и Xray-core с GitHub, проверяет sha256,
# раскладывает по папкам и (если нужно) конвертирует VLESS-ссылку в vpn\config.json.
# В колледже этот скрипт НЕ запускать (ссылка вставляется только дома).
param(
    [string]$XrayVersion = '',   # '' = последний релиз; для воспроизводимости можно прибить, напр. 'v25.10.1'
    # Запускать без сверенной контрольной суммы (см. пояснение в конце проверки sha256)
    [switch]$AllowUnverified,
    [switch]$Force              # переустановить даже то, что уже лежит (браузер, xray)
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'vless-lib.ps1')
$App  = $PSScriptRoot
$Root = Split-Path -Parent $App
$Vpn  = Join-Path $Root 'vpn'
$Dl   = Join-Path $Root '_download'

$Curl = Get-SystemExe 'curl.exe'
$Tar  = Get-SystemExe 'tar.exe'
. (Join-Path $PSScriptRoot 'ui-bar.ps1')

# PowerShell 5.1 по умолчанию может согласовывать TLS 1.0/1.1 — GitLab и GitHub такой handshake отвергают,
# а пользователь видит "SSL connection could not be established" при полностью рабочем интернете.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

function Get-Api([string]$url, [string]$who) {
    try {
        return Invoke-RestMethod -Uri $url -TimeoutSec 40 -Headers @{ 'User-Agent' = 'LibreWolf-USB' }
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match 'rate limit|403|Forbidden') { Fail-Fetch "${who}: превышен лимит запросов (403). Подожди час и повтори, либо скачай файл вручную." }
        if ($msg -match 'SSL|TLS|certificate|Сертификат') { Fail-Fetch "${who}: ошибка TLS ($msg). Проверь прокси/антивирус с перехватом HTTPS и часы Windows." }
        if ($msg -match 'resolve|connect|timed out|unreachable|Имя') { Fail-Fetch "${who} недоступен: нет связи с интернетом ($msg)." }
        Fail-Fetch "${who} недоступен: $msg"
    }
}

function Expand-Zip([string]$zip, [string]$dst) {
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    if ($Tar) {
        try {
            & $Tar -xf "$zip" -C "$dst"
            if ($LASTEXITCODE -eq 0) { return $true }
        } catch { }
    }
    # tar.exe есть не на каждой Windows (нужна 10 1803+) — Expand-Archive из PS 5.1 работает везде
    try { Expand-Archive -LiteralPath $zip -DestinationPath $dst -Force -ErrorAction Stop; return $true } catch { return $false }
}

function Fail-Fetch([string]$msg) {
    Write-Host ""
    Write-Host "[X] $msg" -ForegroundColor Red
    Write-Host "    Интернет должен быть обычным (домашним), без прокси-блокировок." -ForegroundColor DarkGray
    exit 1
}

function Test-ZipMagic([string]$path) {
    # настоящий zip начинается с "PK"; HTML-заглушка с кодом 200 — нет
    try {
        $fs = [IO.File]::OpenRead($path)
        try {
            $b = New-Object byte[] 2
            $n = $fs.Read($b, 0, 2)
            if ($n -lt 2) { return $false }
            return ($b[0] -eq 0x50 -and $b[1] -eq 0x4B)
        } finally { $fs.Dispose() }
    } catch { return $false }
}

function Download([string]$url, [string]$out, [string]$label = 'Загрузка', [switch]$Zip) {
    Write-Host "     $url"
    $r = Invoke-DownloadBar $Curl $url $out $label
    if (-not $r.Ok -and (Test-Path $out) -and (Get-Item $out).Length -gt 0) {
        Write-Host "     [..] обрыв — пробую докачать остаток" -ForegroundColor Yellow
        $r = Invoke-DownloadBar $Curl $url $out $label -Resume
    }
    if (-not $r.Ok) { Remove-Item $out -Force -ErrorAction SilentlyContinue; Fail-Fetch "Не скачалось: $url (код curl $($r.Code), $($r.Size) б из $($r.Total))" }
    if (-not (Test-Path $out) -or (Get-Item $out).Length -lt 100000) { Remove-Item $out -Force -ErrorAction SilentlyContinue; Fail-Fetch "Файл пустой/битый: $out" }
    if ($Zip -and -not (Test-ZipMagic $out)) {
        Remove-Item $out -Force -ErrorAction SilentlyContinue
        Fail-Fetch "Скачался не архив (первые байты не PK): $url — вероятно, вместо файла отдана страница-заглушка или требуется вход. Удали _download\ и повтори."
    }
}

Write-Host ""
Write-Host "=== LibreWolf-USB: подготовка ДОМА ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $Dl, $Vpn | Out-Null

# ---------- 1. LibreWolf ----------
Write-Host ""
$haveBrowser = ((-not $Force) -and (Test-Path (Join-Path $App 'LibreWolf\LibreWolf.exe')))
if ($haveBrowser) {
    Write-Host "[1/3] LibreWolf уже установлен — скачивание пропущено (переустановка: -Force)" -ForegroundColor Green
} else {
Write-Host "[1/3] LibreWolf (portable) — узнаю последнюю версию с GitLab..." -ForegroundColor Cyan
$rels = Get-Api 'https://gitlab.com/api/v4/projects/librewolf-community%2Fbrowser%2Fbsys6/releases?per_page=5' 'GitLab API'
$rel = @($rels)[0]
$tag = $rel.tag_name
Write-Host "     последняя версия: $tag"

$zipName = "librewolf-$tag-windows-x86_64-portable.zip"
$candidates = @("https://gitlab.com/librewolf-community/browser/bsys6/-/releases/$tag/downloads/$zipName")
foreach ($l in @($rel.assets.links)) {
    if ("$($l.name)" -like '*windows*x86_64*portable*' -and "$($l.url)" -like '*.zip') { $candidates += "$($l.url)" }
}
$zipPath = Join-Path $Dl $zipName
$okDl = $false
$usedUrl = ''
$manual  = $false
# если файл уже лежит в _download\ (скачан вручную) — используем его
if ((Test-Path $zipPath) -and ((Get-Item $zipPath).Length -gt 20000000)) {
    $okDl = $true
    $manual = $true
    Write-Host "     найден уже скачанный $zipName — использую его"
}
foreach ($u in $candidates) {
    if ($okDl) { break }
    Write-Host "     пробую скачать..."
    $r = Invoke-DownloadBar $Curl $u $zipPath 'LibreWolf'
    if (-not $r.Ok -and (Test-Path $zipPath) -and (Get-Item $zipPath).Length -gt 1000) {
        Write-Host "     [..] обрыв на $([math]::Round((Get-Item $zipPath).Length/1MB,1)) МБ — пробую докачать остаток" -ForegroundColor Yellow
        $r = Invoke-DownloadBar $Curl $u $zipPath 'LibreWolf' -Resume
    }
    $gotSize = 0
    if (Test-Path $zipPath) { $gotSize = (Get-Item $zipPath).Length }
    if ($r.Ok -and $gotSize -gt 20000000 -and (Test-ZipMagic $zipPath)) { $okDl = $true; $usedUrl = $u; break }
    if ($gotSize -gt 20000000) {
        Write-Host "     [!] размер похож на архив, но это не zip (нет PK) — отбрасываю" -ForegroundColor Red
    }
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
}
if (-not $okDl) {
    Fail-Fetch ("Не удалось скачать LibreWolf. Открой в браузере страницу релизов, скачай вручную '{0}' и положи в папку _download\ на флешке, потом запусти подготовку снова: https://gitlab.com/librewolf-community/browser/bsys6/-/releases" -f $zipName)
}
Write-Host "     скачано: $([math]::Round((Get-Item $zipPath).Length/1MB,1)) МБ"

# sha256: сверяем с суммой, опубликованной рядом с ФАКТИЧЕСКИ скачанным файлом
$zipHash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLower()
Write-Host "     sha256 файла: $zipHash"
$shaOk = $false
$shaTried = @()
if ($usedUrl) { $shaTried += ($usedUrl + '.sha256sum') }
$shaTried += ($candidates[0] + '.sha256sum')
$shaPath = $zipPath + '.sha256sum'
foreach ($su in ($shaTried | Select-Object -Unique)) {
    & $Curl -L --fail --proto '=https' --tlsv1.2 --retry 1 --connect-timeout 15 -s -o "$shaPath" "$su"
    if ($LASTEXITCODE -eq 0 -and (Test-Path $shaPath)) {
        $expected = (("$(Get-Content $shaPath -Raw)").Trim() -split '\s+') | Select-Object -First 1
        Remove-Item $shaPath -Force -ErrorAction SilentlyContinue
        if ($expected -match '^[0-9a-fA-F]{64}$') {
            if ($zipHash -ne $expected.ToLower()) {
                Fail-Fetch "sha256 НЕ СОВПАЛ у LibreWolf: ожидался $($expected.ToLower()), получен $zipHash. Удали _download\ и повтори."
            }
            Write-Host "     sha256 OK (сверено с $su)" -ForegroundColor Green
            $shaOk = $true
            break
        }
    }
}
if (-not $shaOk) {
    # Раньше здесь была только жёлтая строчка и распаковка продолжалась. Это означало:
    # любой подменённый архив (или MITM на домашнем Wi-Fi) попадает в комплект молча.
    Write-Host "     [!] Контрольную сумму скачать не удалось — целостность НЕ подтверждена." -ForegroundColor Red
    Write-Host "         sha256 скачанного файла: $zipHash" -ForegroundColor Yellow
    Write-Host "         Сверь его вручную на странице релиза LibreWolf (GitLab)." -ForegroundColor Yellow
    if ($manual) { Write-Host "         (архив лежит в _download\ — скачан вручную)" -ForegroundColor DarkGray }
    if (-not $AllowUnverified) {
        Write-Host ""
        Write-Host "     Остановился намеренно: распаковывать непроверенный архив нельзя." -ForegroundColor Red
        Write-Host "     1) сверь sha256 вручную на странице релиза;" -ForegroundColor Yellow
        Write-Host "     2) если совпало — запусти подготовку снова с -AllowUnverified:" -ForegroundColor Yellow
        Write-Host "        powershell -ExecutionPolicy Bypass -File app\prepare-home.ps1 -AllowUnverified" -ForegroundColor DarkGray
        Fail-Fetch 'sha256 не подтверждён (либо не скачался файл суммы).'
    }
    Write-Host "         продолжаю по -AllowUnverified" -ForegroundColor Yellow
}

# распаковка -> app\LibreWolf
Write-Host "     распаковка..."
$stage = Join-Path $Dl 'stage'
New-Item -ItemType Directory -Force -Path $stage | Out-Null
if (-not (Expand-Zip $zipPath $stage)) { Fail-Fetch "Не удалось распаковать архив LibreWolf (tar и Expand-Archive не сработали)." }
$exe = Get-ChildItem $stage -Recurse -Filter 'LibreWolf.exe' | Select-Object -First 1
if (-not $exe) { Fail-Fetch "В архиве не нашёлся LibreWolf.exe — распакуй вручную и положи папку браузера в app\LibreWolf\" }
$src = Split-Path $exe.FullName
$dst = Join-Path $App 'LibreWolf'
if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
Move-Item $src $dst
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
Remove-Item $shaPath -Force -ErrorAction SilentlyContinue
Write-Host "     LibreWolf установлен в app\LibreWolf\" -ForegroundColor Green

}

# ---------- 2. Xray-core ----------
Write-Host ""
$haveXray = ((-not $Force) -and (Test-Path (Join-Path $Vpn 'xray.exe')))
if ($haveXray) {
    Write-Host "[2/3] Xray уже на месте — скачивание пропущено (переустановка: -Force)" -ForegroundColor Green
} else {
Write-Host "[2/3] Xray-core — узнаю последнюю версию с GitHub..." -ForegroundColor Cyan
$relUrl = 'https://api.github.com/repos/XTLS/Xray-core/releases/latest'
if ($XrayVersion) { $relUrl = "https://api.github.com/repos/XTLS/Xray-core/releases/tags/$XrayVersion" }
$gh = Get-Api $relUrl 'GitHub API'
$asset = @($gh.assets) | Where-Object { $_.name -eq 'Xray-windows-64.zip' } | Select-Object -First 1
if (-not $asset) { Fail-Fetch "В последнем релизе Xray ($($gh.tag_name)) нет Xray-windows-64.zip. Возьми файл со старой страницы релизов." }
$xz = Join-Path $Dl 'Xray-windows-64.zip'
Download "$($asset.browser_download_url)" $xz 'Xray' -Zip

# целостность: digest из GitHub API, иначе .sha256 рядом с ассетом, иначе громкое предупреждение
$xzHash = (Get-FileHash $xz -Algorithm SHA256).Hash.ToLower()
$expect = ''
if ("$($asset.digest)" -match '^sha256:([0-9a-fA-F]{64})$') { $expect = $Matches[1].ToLower() }
if (-not $expect) {
    $shaTmp = $xz + '.sha256'
    & $Curl -L --fail --proto '=https' --tlsv1.2 -s -o "$shaTmp" "$($asset.browser_download_url).sha256"
    if ($LASTEXITCODE -eq 0 -and (Test-Path $shaTmp)) {
        $v = (("$(Get-Content $shaTmp -Raw)").Trim() -split '\s+') | Select-Object -First 1
        if ("$v" -match '^[0-9a-fA-F]{64}$') { $expect = "$v".ToLower() }
    }
    Remove-Item $shaTmp -Force -ErrorAction SilentlyContinue
}
if ($expect) {
    if ($xzHash -ne $expect) { Fail-Fetch "sha256 НЕ СОВПАЛ у Xray ($($gh.tag_name)): ожидался $expect, получен $xzHash. Удали _download\ и повтори." }
    Write-Host "     sha256 OK ($($gh.tag_name))" -ForegroundColor Green
} else {
    Write-Host "     [!] Хеш Xray не опубликован в API — целостность НЕ подтверждена." -ForegroundColor Red
    Write-Host "         sha256 файла: $xzHash — сверь на странице релиза $($gh.tag_name)" -ForegroundColor Yellow
    if (-not $AllowUnverified) {
        Write-Host ""
        Write-Host "     Остановился намеренно: распаковывать непроверенный xray.exe нельзя" -ForegroundColor Red
        Write-Host "     (этот файл и держит весь трафик). Сверь sha256 вручную, затем запусти с -AllowUnverified." -ForegroundColor Yellow
        Fail-Fetch 'sha256 xray.exe не подтверждён.'
    }
    Write-Host "         продолжаю по -AllowUnverified" -ForegroundColor Yellow
}

Write-Host "     распаковка в vpn\..."
if (-not (Expand-Zip $xz $Vpn)) { Fail-Fetch "Не удалось распаковать Xray-windows-64.zip." }
$xrayExe = Join-Path $Vpn 'xray.exe'
if (-not (Test-Path $xrayExe)) { Fail-Fetch "После распаковки нет vpn\xray.exe — распакуй архив вручную в папку vpn\" }
try { $ver = (& $xrayExe version | Select-Object -First 1) } catch { $ver = '(версию показать не удалось)' }
Remove-Item $xz -Force -ErrorAction SilentlyContinue
Write-Host "     Xray готов: $ver" -ForegroundColor Green

}

# ---------- 3. конфиг VPN ----------
Write-Host ""
Write-Host "[3/3] Конфиг VPN..." -ForegroundColor Cyan
$cfg = Join-Path $Vpn 'config.json'
$cfgEnc = $cfg + '.enc'
if ((-not (Test-Path $cfg)) -and (Test-Path $cfgEnc)) {
    # ключи уже на месте и зашифрованы: пересобирать их в открытый config.json нельзя
    Write-Host "     vpn\config.json.enc уже есть (ключи под паролем) — пропускаю." -ForegroundColor Green
    Write-Host "     Обновить сервера из подписки: ПОДГОТОВКА-ДОМА.bat → пункт 3 в меню." -ForegroundColor DarkGray
} elseif (Test-Path $cfg) {
    Write-Host "     vpn\config.json уже есть — пропускаю." -ForegroundColor Green
    Write-Host "     Обновить сервера из подписки: powershell -ExecutionPolicy Bypass -File app\update-sub.ps1" -ForegroundColor DarkGray
} else {
    Write-Host "     Откуда взять сервера?" -ForegroundColor Yellow
    Write-Host "       [1] ОДИН КЛЮЧ: вставить vless://... ссылку (можно несколько)"
    Write-Host "           сервера потом обновляются вручную, сами не обновляются"
    Write-Host "       [2] ПОДПИСКА: вставить https://.../sub/ТОКЕН"
    Write-Host "           список серверов приходит с сервера провайдера и обновляется"
    Write-Host "           сам при запуске START.bat (если конфигу больше 3 дней)"
    Write-Host "       [3] пропустить (потом запусти подготовку снова)"
    $mode = Read-Host "     Выбор (1/2/3)"
    $conv = $null
    if ("$mode".Trim() -eq '1') { $conv = Join-Path $App 'vless-to-config.ps1' }
    elseif ("$mode".Trim() -eq '2') {
        $conv = Join-Path $App 'update-sub.ps1'
        Write-Host "     Нужен URL ПОДПИСКИ (https://.../sub/ТОКЕН), не vless:// ссылка." -ForegroundColor DarkGray
    }
    if ($conv) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$conv"
        if ((Test-Path $cfg) -or (Test-Path $cfgEnc)) { Write-Host "     config.json создан" -ForegroundColor Green }
        else { Write-Host "     [!] Конфиг не создан — см. сообщения выше" -ForegroundColor Red }
    } else {
        Write-Host "     Пропущено. Потом дома (в консоли из папки комплекта):" -ForegroundColor Yellow
        Write-Host "       powershell -ExecutionPolicy Bypass -File app\vless-to-config.ps1   (ссылки вручную)" -ForegroundColor Yellow
        Write-Host "       powershell -ExecutionPolicy Bypass -File app\update-sub.ps1       (из подписки)" -ForegroundColor Yellow
    }
}

Remove-Item $Dl -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "=== ГОТОВО ===" -ForegroundColor Green
Write-Host "Флешку можно брать в колледж: там запускай START.bat, в конце — ЧИСТКА.bat."
Write-Host "Подробности: README-RU.md на флешке."
Write-Host ""
exit 0
