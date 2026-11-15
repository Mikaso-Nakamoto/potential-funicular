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
$App  = $PSScriptRoot
$Root = Split-Path -Parent $App
$Vpn  = Join-Path $Root 'vpn'
$Dl   = Join-Path $Root '_download'

# системные бинарники — по полному пути: вызов по имени подменяется файлом из PATH
function Get-SystemExe([string]$Name) {
    if ($env:SystemRoot) {
        $p = Join-Path $env:SystemRoot ('System32\' + $Name)
        if (Test-Path $p) { return $p }
    }
    return $Name
}
$Curl = Get-SystemExe 'curl.exe'
$Tar  = Get-SystemExe 'tar.exe'

function Fail([string]$msg) {
    Write-Host ""
    Write-Host "[X] $msg" -ForegroundColor Red
    Write-Host "    Интернет должен быть обычным (домашним), без прокси-блокировок." -ForegroundColor DarkGray
    exit 1
}

function Download([string]$url, [string]$out) {
    Write-Host "     $url"
    & $Curl -L --fail --proto '=https' --tlsv1.2 --retry 3 --connect-timeout 20 --progress-bar -o "$out" "$url"
    if ($LASTEXITCODE -ne 0) { Fail "Не скачалось: $url" }
    if (-not (Test-Path $out) -or (Get-Item $out).Length -lt 100000) { Fail "Файл пустой/битый: $out" }
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
try {
    $rels = Invoke-RestMethod -Uri 'https://gitlab.com/api/v4/projects/librewolf-community%2Fbrowser%2Fbsys6/releases?per_page=5' -TimeoutSec 40
} catch { Fail "GitLab API недоступен: $($_.Exception.Message)" }
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
    & $Curl -L --fail --proto '=https' --tlsv1.2 --retry 2 --connect-timeout 20 --progress-bar -o "$zipPath" "$u"
    if ($LASTEXITCODE -eq 0 -and (Test-Path $zipPath) -and (Get-Item $zipPath).Length -gt 20000000) { $okDl = $true; $usedUrl = $u; break }
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
}
if (-not $okDl) {
    Fail ("Не удалось скачать LibreWolf. Открой в браузере страницу релизов, скачай вручную '{0}' и положи в папку _download\ на флешке, потом запусти подготовку снова: https://gitlab.com/librewolf-community/browser/bsys6/-/releases" -f $zipName)
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
                Fail "sha256 НЕ СОВПАЛ у LibreWolf: ожидался $($expected.ToLower()), получен $zipHash. Удали _download\ и повтори."
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
        Fail 'sha256 не подтверждён (либо не скачался файл суммы).'
    }
    Write-Host "         продолжаю по -AllowUnverified" -ForegroundColor Yellow
}

# распаковка -> app\LibreWolf
Write-Host "     распаковка..."
$stage = Join-Path $Dl 'stage'
New-Item -ItemType Directory -Force -Path $stage | Out-Null
& $Tar -xf "$zipPath" -C "$stage"
if ($LASTEXITCODE -ne 0) { Fail "tar не смог распаковать zip (нужна Windows 10 1803+)." }
$exe = Get-ChildItem $stage -Recurse -Filter 'LibreWolf.exe' | Select-Object -First 1
if (-not $exe) { Fail "В архиве не нашёлся LibreWolf.exe — распакуй вручную и положи папку браузера в app\LibreWolf\" }
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
try {
    $gh = Invoke-RestMethod -Uri $relUrl -TimeoutSec 40
} catch { Fail "GitHub API недоступен: $($_.Exception.Message)" }
$asset = @($gh.assets) | Where-Object { $_.name -eq 'Xray-windows-64.zip' } | Select-Object -First 1
if (-not $asset) { Fail "В последнем релизе Xray ($($gh.tag_name)) нет Xray-windows-64.zip. Возьми файл со старой страницы релизов." }
$xz = Join-Path $Dl 'Xray-windows-64.zip'
Download "$($asset.browser_download_url)" $xz

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
    if ($xzHash -ne $expect) { Fail "sha256 НЕ СОВПАЛ у Xray ($($gh.tag_name)): ожидался $expect, получен $xzHash. Удали _download\ и повтори." }
    Write-Host "     sha256 OK ($($gh.tag_name))" -ForegroundColor Green
} else {
    Write-Host "     [!] Хеш Xray не опубликован в API — целостность НЕ подтверждена." -ForegroundColor Red
    Write-Host "         sha256 файла: $xzHash — сверь на странице релиза $($gh.tag_name)" -ForegroundColor Yellow
    if (-not $AllowUnverified) {
        Write-Host ""
        Write-Host "     Остановился намеренно: распаковывать непроверенный xray.exe нельзя" -ForegroundColor Red
        Write-Host "     (этот файл и держит весь трафик). Сверь sha256 вручную, затем запусти с -AllowUnverified." -ForegroundColor Yellow
        Fail 'sha256 xray.exe не подтверждён.'
    }
    Write-Host "         продолжаю по -AllowUnverified" -ForegroundColor Yellow
}

Write-Host "     распаковка в vpn\..."
& $Tar -xf "$xz" -C "$Vpn"
if ($LASTEXITCODE -ne 0) { Fail "tar не смог распаковать Xray-windows-64.zip." }
$xrayExe = Join-Path $Vpn 'xray.exe'
if (-not (Test-Path $xrayExe)) { Fail "После распаковки нет vpn\xray.exe — распакуй архив вручную в папку vpn\" }
try { $ver = (& $xrayExe version | Select-Object -First 1) } catch { $ver = '(версию показать не удалось)' }
Remove-Item $xz -Force -ErrorAction SilentlyContinue
Write-Host "     Xray готов: $ver" -ForegroundColor Green

}

# ---------- 3. конфиг VPN ----------
Write-Host ""
Write-Host "[3/3] Конфиг VPN..." -ForegroundColor Cyan
$cfg = Join-Path $Vpn 'config.json'
if (Test-Path $cfg) {
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
        if (Test-Path $cfg) { Write-Host "     config.json создан" -ForegroundColor Green }
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
