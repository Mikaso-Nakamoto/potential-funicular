# ping-servers.ps1 — задержка до серверов из vpn\config.json.
# Замер — TCP-подключение к address:port (не ICMP): работает без прав администратора,
# не зависит от блокировки ICMP в сети колледжа и не требует поднятого туннеля.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'vless-lib.ps1')
. (Join-Path $PSScriptRoot 'secret.ps1')

$Root   = Split-Path -Parent $PSScriptRoot
$Vpn    = Join-Path $Root 'vpn'
$Cfg    = Join-Path $Vpn 'config.json'
$CfgEnc = $Cfg + '.enc'
$TmpCfg = ''

Write-Host ''
Write-Host '=== Задержка до серверов (TCP, без браузера) ===' -ForegroundColor Cyan

if (Test-KitSecret $Vpn) {
    Write-Host '[i] Ключи на флешке зашифрованы — нужен пароль.' -ForegroundColor DarkGray
    $pw = Read-KitPassword $Vpn
    if (-not $pw) { Write-Host '[X] Пароль не введён или неверный.' -ForegroundColor Red; exit 1 }
    if (Test-Path $CfgEnc) {
        $TmpCfg = Join-Path ([IO.Path]::GetTempPath()) ('lwusb-ping-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
        if (-not (Unprotect-KitFile $CfgEnc $TmpCfg $pw)) {
            Write-Host '[X] vpn\config.json.enc не расшифровался: файл повреждён или пароль от другой флешки.' -ForegroundColor Red
            exit 1
        }
        $Cfg = $TmpCfg
    }
}

if (-not (Test-Path $Cfg)) {
    Write-Host '[X] Нет vpn\config.json. Дома запусти ПОДГОТОВКА-ДОМА.bat и пункт 4.' -ForegroundColor Red
    exit 1
}

$obj = $null
try { $obj = Get-Content $Cfg -Raw -Encoding UTF8 | ConvertFrom-Json }
catch {
    if ($TmpCfg) { Remove-Item $TmpCfg -Force -ErrorAction SilentlyContinue }
    Write-Host '[X] vpn\config.json повреждён — дома пересобери его (пункт 3 или 4).' -ForegroundColor Red
    exit 1
}

$targets = @()
$labels  = @()
foreach ($o in @($obj.outbounds)) {
    if ("$($o.tag)" -notlike 'proxy-*') { continue }
    $v = $null
    if ($o.settings -and $o.settings.vnext) { $v = @($o.settings.vnext)[0] }
    if (-not $v) { continue }
    $targets += ("$($v.address):$($v.port)")
    $labels  += ("$($o.tag)  $($v.address):$($v.port)")
}
if ($TmpCfg) { Remove-Item $TmpCfg -Force -ErrorAction SilentlyContinue }

if ($targets.Count -eq 0) {
    Write-Host '[X] В конфиге нет серверов вида proxy-N.' -ForegroundColor Red
    exit 1
}

Write-Host "[..] Проверяю $($targets.Count) сервер(ов)..." -ForegroundColor DarkGray
$res = @(Measure-ServerPing -Targets $targets -TimeoutMs 3000)
# на всякий случай разворачиваем вложенные массивы: индексы должны совпадать с $labels
$flat = @()
foreach ($x in $res) {
    if ($x -is [array]) { foreach ($y in $x) { $flat += $y } } else { $flat += $x }
}

$rows = @()
for ($i = 0; $i -lt $flat.Count; $i++) {
    $ms = -1
    try { if ($null -ne $flat[$i].Ms) { $ms = [int]$flat[$i].Ms } } catch { $ms = -1 }
    $lbl = ''
    if ($i -lt $labels.Count) { $lbl = $labels[$i] }
    $rows += [pscustomobject]@{ N = ($i + 1); Label = $lbl; Ms = $ms }
}
$rows = @($rows | Sort-Object @{ Expression = { if ($_.Ms -lt 0) { 999999 } else { $_.Ms } } })

Write-Host ''
foreach ($r in $rows) {
    if ($r.Ms -ge 0) {
        $color = 'Green'
        if ($r.Ms -ge 300) { $color = 'Yellow' }
        if ($r.Ms -ge 800) { $color = 'Red' }
        Write-Host ("  [{0}] {1}  —  {2} мс" -f $r.N, $r.Label, $r.Ms) -ForegroundColor $color
    } else {
        Write-Host ("  [{0}] {1}  —  нет ответа (порт закрыт/сервер не отвечает)" -f $r.N, $r.Label) -ForegroundColor DarkGray
    }
}

$alive = @($rows | Where-Object { $_.Ms -ge 0 })
Write-Host ''
if ($alive.Count -eq 0) {
    Write-Host '[!] Ни один сервер не ответил. Проверь интернет; возможно, узлы заменены — дома обнови подписку (пункт 3).' -ForegroundColor Red
} else {
    $best = $alive[0]
    Write-Host ("[i] Быстрее всех: [{0}] {1} — {2} мс. В режиме с выбором сервера это номер {0}." -f $best.N, $best.Label, $best.Ms) -ForegroundColor Green
}
Write-Host '[i] Замер идёт напрямую, без туннеля: показывает задержку до сервера, а не скорость через него.' -ForegroundColor DarkGray
Write-Host ''
