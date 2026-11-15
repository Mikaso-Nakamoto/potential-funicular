# start.ps1 — LibreWolf-USB: запуск браузера ТОЛЬКО через Xray (VLESS)
# с kill-switch и авто-обновлением подписки ЧЕРЕЗ туннель (если конфиг устарел).
#
# -ForceUpdate     — обновить подписку через туннель, не дожидаясь 3 дней
# -IgnorePolicies  — не отказывать, если в реестре есть политики Mozilla
# -Debug           — поднять уровень логов xray (по умолчанию none)
param(
    [switch]$ForceUpdate,
    [switch]$IgnorePolicies,
    [switch]$Debug,
    [switch]$Fast,
    [int]$Server = 0          # >0: только этот сервер, без балансировки (для YouTube и подобных)
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'vless-lib.ps1')
. (Join-Path $PSScriptRoot 'secret.ps1')

# --- пути и настройки ---
$App     = $PSScriptRoot
$Root    = Split-Path -Parent $App
$Vpn     = Join-Path $Root 'vpn'
$Logs    = Join-Path $Vpn 'logs'
$Profile = Join-Path $Root 'profile'
$ProfileTemp = $false
if ($Fast) {
    # -Fast: профиль на локальном диске. Флешка не тормозит на мелких файлах,
    # но папка профиля появляется в %TEMP% на время сессии и удаляется в конце.
    $tmpRoot = $env:TEMP
    if (-not $tmpRoot) { $tmpRoot = [IO.Path]::GetTempPath() }
    $Profile = Join-Path $tmpRoot ('lwusb-profile-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
    $ProfileTemp = $true
}
$Cfg     = Join-Path $Vpn 'config.json'
$SubFile = Join-Path $Vpn 'sub.txt'
$CfgEnc  = $Cfg + '.enc'          # vpn\config.json.enc (если задан пароль)
$SubEnc  = $SubFile + '.enc'      # vpn\sub.txt.enc
$script:KitPassword = $null       # пароль флешки на эту сессию (в файл не пишется)
$Xray    = Join-Path $Vpn 'xray.exe'
$Ts      = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $Logs ('session-' + $Ts + '.log')
$SubMaxAgeDays = 3   # старше — пробуем обновить подписку через туннель
$script:XraySeq = 0
$script:OnlyServer = $Server
$script:FailCode = 0   # 0 = штатно; Fail() и перехват ошибок выставляют код
$script:XrayProc = $null
$script:SessionCfg = ''

# временный каталог сессии: сюда идут только сырые логи xray и сессионный конфиг
$TmpRoot = $env:TEMP
if (-not $TmpRoot) { $TmpRoot = [IO.Path]::GetTempPath() }
$SessionDir = Join-Path $TmpRoot ('lwusb-' + $Ts)
$script:SessionDir = $SessionDir

$Curl     = Get-SystemExe 'curl.exe'
$Taskkill = Get-SystemExe 'taskkill.exe'
$Netstat  = Get-SystemExe 'netstat.exe'

if ($Debug) { $script:LogLevel = 'warning' }

function Log([string]$msg) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $msg
    Write-Host $line
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch {}
}

# Fail больше не вызывает exit напрямую: иначе не сработает finally и xray останется
# висеть (это и был баг из отчёта — «осиротевший xray»).
function Fail([string]$msg, [int]$code = 1) {
    Write-Host ''
    Write-Host "[X] $msg" -ForegroundColor Red
    try { Add-Content -Path $LogFile -Value "[XX] $msg" -Encoding UTF8 } catch {}
    $script:FailCode = $code
    throw '__LWUSB_STOP__'
}

# --- санитайзер окружения: чужой ПК мог оставить переменные, читающие трафик ---
$script:DroppedEnv = @()
foreach ($n in @(
        'MOZ_LOG', 'MOZ_LOG_FILE', 'MOZ_LOG_MODULES',
        'SSLKEYLOGFILE',
        'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY',
        'http_proxy', 'https_proxy', 'all_proxy', 'no_proxy',
        'JAVA_TOOL_OPTIONS', '_JAVA_OPTIONS',
        'DOTNET_STARTUP_HOOKS', 'DOTNET_PROFILER',
        'COR_ENABLE_PROFILING', 'COR_PROFILER', 'COR_PROFILER_PATH',
        'CORECLR_ENABLE_PROFILING', 'CORECLR_PROFILER', 'CORECLR_PROFILER_PATH',
        'NODE_OPTIONS')) {
    if (Test-Path ("env:" + $n)) {
        try { Remove-Item ("env:" + $n) -Force -ErrorAction SilentlyContinue } catch {}
        $script:DroppedEnv += $n
    }
}
# пользовательские пути модулей идут первыми → подложенный модуль подменит
# Get-NetTCPConnection и прочие командлеты проверок
if ($PSHOME) { $env:PSModulePath = (Join-Path $PSHOME 'Modules') } else { $env:PSModulePath = '' }

# --- внешний IP (через прокси, если указан; иначе прямой) ---
function Get-ExtIP([int]$ProxyPort = 0) {
    foreach ($u in @('https://api.ipify.org', 'https://ifconfig.me/ip')) {
        try {
            $curlArgs = @('-s', '--max-time', '12')
            if ($ProxyPort -gt 0) { $curlArgs += @('--socks5-hostname', "127.0.0.1:$ProxyPort") }
            $r = & $Curl @curlArgs $u 2>$null
            $r = "$r".Trim()
            if ($r -match '^[0-9a-fA-F.:\[\]]+$' -and $r.Length -le 45) { return $r }
        } catch {}
    }
    return ''
}

function Test-Socks([int]$P) {
    $c = New-Object Net.Sockets.TcpClient
    try {
        $t = $c.ConnectAsync('127.0.0.1', $P)
        if ($t.Wait(1500) -and $c.Connected) { return $true }
    } catch {}
    finally { $c.Dispose() }
    return $false
}

function Get-ListenerPid([int]$P) {
    # кто слушает порт: PID или 0, если определить не удалось.
    # Основной путь — Get-NetTCPConnection, запасной — netstat (если CIM/WMI зарезаны политикой).
    try {
        $c = Get-NetTCPConnection -LocalPort $P -State Listen -ErrorAction Stop | Select-Object -First 1
        if ($c) { return [int]$c.OwningProcess }
    } catch {}
    try {
        $lines = & $Netstat -ano 2>$null
        foreach ($l in @($lines)) {
            $t = ("$l".Trim()) -split '\s+'
            if ($t.Count -lt 4 -or ("$l" -notmatch 'LISTENING')) { continue }
            if ("$l" -notmatch (":" + $P + '\s')) { continue }
            if ("$($t[-1])" -match '^\d+$' -and [int]$t[-1] -gt 0) { return [int]$t[-1] }
        }
    } catch {}
    return 0
}

function Ask-Cleanup {
    # После закрытия браузера спрашивает, чистить ли следы этой сессии.
    # Enter/Y — чистить, N/Esc — нет, 30 секунд без ответа — пропустить.
    # При перенаправленном вводе (запуск из скрипта) не спрашивает вовсе.
    try {
        if ([Console]::IsInputRedirected) { return $false }
    } catch { return $false }

    Write-Host ''
    Write-Host '[?] Почистить следы этой сессии на этом ПК?' -ForegroundColor Cyan
    Write-Host '    История PowerShell, временные файлы, кэш миниатюр, недавние документы, DNS-кэш.' -ForegroundColor DarkGray
    Write-Host '    Enter или Y — чистить,   N — оставить,   30 секунд — пропустить.' -ForegroundColor DarkGray
    Write-Host '    > ' -ForegroundColor Green -NoNewline

    $buf = ''
    $answered = $false
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        try {
            if ([Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true)
                if ($k.Key -eq 'Enter') { $answered = $true; break }
                if ($k.Key -eq 'Escape') { Write-Host ''; return $false }
                if ("$($k.KeyChar)" -match '^[A-Za-zА-Яа-я]$') {
                    $buf += $k.KeyChar
                    Write-Host $k.KeyChar -NoNewline
                }
            }
        } catch { return $false }
        Start-Sleep -Milliseconds 100
    }
    Write-Host ''
    if (-not $answered) { return $false }
    if ($buf -eq '') { return $true }
    return ($buf -match '^(y|Y|д|Д)')
}

function Save-KitCopies {
    # после пересборки конфига: обновить зашифрованные копии на флешке (.enc)
    if (-not $script:KitPassword) { return }
    try {
        if (Test-Path $Cfg) { Protect-KitFile $Cfg $script:KitPassword $CfgEnc -KeepSource | Out-Null }
        $bak = $Cfg + '.bak.json'
        if (Test-Path $bak) {
            Protect-KitFile $bak $script:KitPassword (Join-Path $Vpn 'config.json.bak.json.enc') -KeepSource | Out-Null
        }
    } catch { Log ('не удалось обновить .enc: ' + $_.Exception.Message) }
}

function Enable-KitPassword {
    # предлагает поставить пароль и сразу шифрует ключи; $true, если пароль задан
    $lines = @(
        '    Тогда config.json и sub.txt будут лежать на флешке зашифрованными,',
        '    а пароль придётся вводить при каждом подключении (пункты 1 и 2).',
        '    Пароль нигде не хранится: забыли — ключи собирать заново.'
    )
    if (-not (Read-KitYesNo '[?] Поставить пароль на ключи этой флешки?' $lines 30)) { return $false }
    $pw = ''
    try { $pw = Set-KitPassword $Vpn } catch { Log ('пароль не задан: ' + $_.Exception.Message); return $false }
    if (-not $pw) { return $false }
    try {
        $plain = Join-Path $SessionDir 'config.json'
        if (Test-Path $Cfg) {
            New-Item -ItemType Directory -Force -Path $SessionDir | Out-Null
            Copy-Item $Cfg $plain -Force
        }
        if (Test-Path $Cfg) { Protect-KitFile $Cfg $pw $CfgEnc | Out-Null }
        $bak = $Cfg + '.bak.json'
        if (Test-Path $bak) { Protect-KitFile $bak $pw (Join-Path $Vpn 'config.json.bak.json.enc') | Out-Null }
        if (Test-Path $SubFile) { Protect-KitFile $SubFile $pw $SubEnc | Out-Null }
        Log 'пароль задан, ключи зашифрованы (.enc)'
        Write-Host '[+] Пароль задан, открытые копии с флешки удалены.' -ForegroundColor Green
        if (Test-Path $plain) { $script:Cfg = $plain }
        $script:KitPassword = $pw
        return $true
    } catch {
        Log ('ошибка шифрования: ' + $_.Exception.Message)
        Write-Host '[!] Не удалось зашифровать — файлы остались как были.' -ForegroundColor Red
        return $false
    }
}

function Get-FreePort {
    for ($i = 0; $i -lt 40; $i++) {
        $p = Get-Random -Minimum 20000 -Maximum 60000
        if ((Get-ListenerPid $p) -eq 0) { return $p }
    }
    return 0
}

function New-SessionConfig([int]$P) {
    # копия config.json с портом сессии в %TEMP%: на флешку ничего не пишем,
    # а конфиг с чужим портом снаружи бесполезен
    $obj = Get-Content $Cfg -Raw -Encoding UTF8 | ConvertFrom-Json
    if (@($obj.inbounds).Count -lt 1) { Fail 'config.json без inbound — пересоздай конфиг дома.' }
    $obj.inbounds[0].port = $P
    if ($script:OnlyServer -gt 0) {
        # фиксируем один сервер: балансировщик выбирает узел на КАЖДОЕ соединение,
        # поэтому одна страница уходит через разные IP, и сервисы это рвут
        $all = @($obj.outbounds)
        if ($script:OnlyServer -gt $all.Count) {
            Fail ('В config.json серверов: ' + $all.Count + ', а ты просишь -Server ' + $script:OnlyServer + '. Укажи число от 1 до ' + $all.Count + '.')
        }
        $pick = $all[$script:OnlyServer - 1]
        $tag = "$($pick.tag)"
        $obj.outbounds = @($pick)
        $obj.routing = [ordered]@{
            domainStrategy = 'AsIs'
            rules = @(
                [ordered]@{ type = 'field'; network = 'tcp,udp'; outboundTag = $tag }
            )
        }
        try { $obj.PSObject.Properties.Remove('observatory') } catch {}
    }
    $json = $obj | ConvertTo-Json -Depth 12
    $null = $json | ConvertFrom-Json   # самопроверка перед записью
    $path = Join-Path $SessionDir 'config.session.json'
    [IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding $false))
    return $path
}

function Start-XrayProc {
    # запуск xray с СЕССИОННЫМ конфигом (порт меняется на каждый запуск)
    $script:XraySeq++
    $OutLog = Join-Path $SessionDir ('xray-out-' + $script:XraySeq + '.log')
    $ErrLog = Join-Path $SessionDir ('xray-err-' + $script:XraySeq + '.log')
    Log "запуск xray (попытка $($script:XraySeq))"
    return (Start-Process -FilePath $Xray -ArgumentList @('-c', ('"' + $script:SessionCfg + '"')) `
        -WorkingDirectory $Vpn -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog)
}

function Get-KitBrowserPids([string]$Dir) {
    # librewolf.exe в корне папки — лончер: он запускает настоящий процесс и завершается.
    # Поэтому ищем любой процесс, чей файл лежит внутри папки браузера.
    $pids = @()
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
        $path = ''
        try { $path = $p.Path } catch {}
        if ($path -and $path.StartsWith($Dir, [StringComparison]::OrdinalIgnoreCase)) { $pids += [int]$p.Id }
    }
    return $pids
}

function Wait-SocksReady($Proc) {
    # 'ok' | 'exited' | 'timeout' | 'foreign:<pid>' | 'unknown-pid'
    for ($i = 0; $i -lt 30; $i++) {
        if ($Proc.HasExited) { return 'exited' }
        if (Test-Socks $Port) {
            $owner = Get-ListenerPid $Port
            # fail-closed: не знаем, кто слушает порт → не пускаем браузер
            if ($owner -le 0) { return 'unknown-pid' }
            if ($owner -eq $Proc.Id) { return 'ok' }
            return ('foreign:' + $owner)
        }
        Start-Sleep -Milliseconds 1000
    }
    return 'timeout'
}

function Assert-SocksOk($status, [string]$context) {
    switch -Regex ("$status") {
        '^ok$' { return }
        '^foreign:(.+)$' { Fail ($context + " Порт $Port занят чужим процессом (PID " + $Matches[1] + ') — трафик пошёл бы через него. Закрой его и запусти снова.') }
        '^unknown-pid$' { Fail ($context + " Не удалось определить владельца порта $Port (CIM и netstat недоступны) — отказываюсь запускать браузер, чтобы не отдать трафик чужому процессу.") }
        '^exited$' { Fail ($context + ' Xray завершился, не подняв SOCKS.') }
        default { Fail ($context + " Xray не поднял SOCKS на 127.0.0.1:$Port за 30 с.") }
    }
}

function Stop-OurXray {
    if ($script:XrayProc -and -not $script:XrayProc.HasExited) {
        Stop-Process -Id $script:XrayProc.Id -Force -ErrorAction SilentlyContinue
    }
    foreach ($p in @(Get-Process -Name 'xray' -ErrorAction SilentlyContinue)) {
        $path = ''
        try { $path = $p.Path } catch {}
        if ($path -and ($path -ieq $Xray)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    }
}

# --- баннер ---
Write-Host ''
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host '  LibreWolf-USB  |  браузер только через VPN'      -ForegroundColor Cyan
Write-Host '  трафик БРАУЗЕРА -> Xray (VLESS) -> SOCKS 127.0.0.1' -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $Logs | Out-Null
New-Item -ItemType Directory -Force -Path $SessionDir | Out-Null
Log "=== старт сессии $Ts ==="
if ($script:DroppedEnv.Count -gt 0) {
    Log ("сняты переменные окружения: " + ($script:DroppedEnv -join ', '))
}

$script:BrowserPid = $null
$script:Breach = ''

try {
    # --- preflight: окружение, в котором скрипт заведомо не сработает ---
    try {
        $lm = "$($ExecutionContext.SessionState.LanguageMode)"
        if ($lm -ne 'FullLanguage') {
            Fail ("PowerShell в режиме " + $lm + " (запрет политикой ПК). В таком режиме kill-switch и проверки порта не работают — запускать нельзя.")
        }
    } catch {}
    try {
        $blocked = @()
        foreach ($scope in @('MachinePolicy', 'UserPolicy')) {
            $pol = $null
            try { $pol = Get-ExecutionPolicy -Scope $scope -ErrorAction Stop } catch {}
            if ($pol -and ("$pol" -eq 'Restricted' -or "$pol" -eq 'AllSigned')) {
                $blocked += ($scope + '=' + $pol)
            }
        }
        if ($blocked.Count -gt 0) {
            Fail ("Политика ПК запрещает запуск скриптов (" + ($blocked -join ', ') + '). -ExecutionPolicy Bypass такую политику не обходит.')
        }
    } catch {}

    # --- политики Mozilla в реестре: могут подсунуть прокси или расширение ---
    if (-not $IgnorePolicies) {
        $policyKeys = @()
        foreach ($k in @('HKCU:\Software\Policies\Mozilla\Firefox', 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox')) {
            try { if (Test-Path $k) { $policyKeys += $k } } catch {}
        }
        if ($policyKeys.Count -gt 0) {
            Fail ("В реестре есть политики Mozilla (" + ($policyKeys -join ', ') + '): они могут задавать прокси или ставить расширения помимо user.js. Если это твой ПК — запусти с -IgnorePolicies.')
        }
    }

    # --- снимаем правила kill-switch от прошлых сессий: иначе они блокируют браузер навсегда ---
    try {
        $stale = @(Get-NetFirewallRule -DisplayName 'LibreWolf-USB-KILLSWITCH*' -ErrorAction SilentlyContinue)
        if ($stale.Count -gt 0) {
            $stale | Remove-NetFirewallRule -ErrorAction SilentlyContinue
            Log ("сняты правила брандмауэра от прошлых сессий: " + $stale.Count)
        }
    } catch {}

    # --- пароль на ключи (если задан на флешке) ---
    if (Test-KitSecret $Vpn) {
        Write-Host ''
        Write-Host '[i] Ключи на флешке зашифрованы — нужен пароль.' -ForegroundColor Cyan
        $script:KitPassword = Read-KitPassword $Vpn
        if (-not $script:KitPassword) {
            Fail 'Пароль не введён или неверный — соединение не поднимаю, браузер не запущен.'
        }
        if (Test-Path $CfgEnc) {
            $plain = Join-Path $SessionDir 'config.json'
            if (-not (Unprotect-KitFile $CfgEnc $plain $script:KitPassword)) {
                Fail 'vpn\config.json.enc не расшифровался: файл повреждён или пароль от другой флешки.'
            }
            try { (Get-Item $plain).LastWriteTime = (Get-Item $CfgEnc).LastWriteTime } catch { }
            $script:Cfg = $plain
            Log 'config.json расшифрован во временный каталог сессии'
        } elseif (Test-Path $Cfg) {
            New-Item -ItemType Directory -Force -Path $SessionDir | Out-Null
            $plain = Join-Path $SessionDir 'config.json'
            Copy-Item $Cfg $plain -Force
            try { Protect-KitFile $Cfg $script:KitPassword $CfgEnc | Out-Null; Log 'config.json зашифрован (.enc)' } catch { }
            $script:Cfg = $plain
        }
        if (Test-Path $SubEnc) {
            $psub = Join-Path $SessionDir 'sub.txt'
            if (Unprotect-KitFile $SubEnc $psub $script:KitPassword) { $script:SubFile = $psub }
        } elseif (Test-Path $SubFile) {
            try { Protect-KitFile $SubFile $script:KitPassword $SubEnc | Out-Null; Log 'sub.txt зашифрован (.enc)' } catch { }
        }
        $n = Remove-KitPlain $Vpn
        if ($n -gt 0) { Log ('.enc на месте, открытых копий удалено: ' + $n) }
    } elseif ((Test-Path $Cfg) -or (Test-Path $CfgEnc)) {
        Enable-KitPassword | Out-Null
    }

    # --- проверки ---
    if (-not (Test-Path $Cfg)) {
        Fail 'Нет vpn\config.json. Дома запусти ПОДГОТОВКА-ДОМА.bat и конвертер VLESS-ссылок (см. README).'
    }
    if (-not (Test-Path $Xray)) {
        Fail 'Нет vpn\xray.exe. Дома запусти ПОДГОТОВКА-ДОМА.bat (скачает Xray и LibreWolf).'
    }
    $UserJs = Join-Path $App 'user.js'
    if (-not (Test-Path $UserJs)) {
        Fail 'Нет app\user.js — без него браузер пойдёт мимо прокси. Перекачай комплект (файл мог удалить антивирус).'
    }

    $CfgObj = $null
    try { $CfgObj = (Get-Content $Cfg -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { Fail 'vpn\config.json повреждён. Дома пересоздай его конвертером (ПОДГОТОВКА-ДОМА.bat).' }
    $problems = @(Test-ConfigSafe $CfgObj)
    if ($problems.Count -gt 0) {
        Fail ("Конфиг не прошёл проверку безопасности:`n      - " + ($problems -join "`n      - ") + "`n      Дома пересоздай конфиг: app\update-sub.ps1 или app\vless-to-config.ps1.")
    }

    $srvCount = @($CfgObj.outbounds).Count
    if ($script:OnlyServer -gt 0) {
        Log ('режим: только сервер ' + $script:OnlyServer + ' из ' + $srvCount + ' (без балансировки)')
        Write-Host ('[i] Режим: только сервер ' + $script:OnlyServer + ' из ' + $srvCount +
                    ' — балансировщик выключен, выходной IP должен оставаться одним.') -ForegroundColor Green
    } else {
        Log ('серверов в config.json: ' + $srvCount + ', балансировщик leastPing')
        if ($srvCount -gt 1) {
            Write-Host ('[i] Режим: балансировщик leastPing, серверов ' + $srvCount +
                        ' — выходной IP будет МЕНЯТЬСЯ (в логе видно «IP через VPN сменился»).') -ForegroundColor Yellow
            Write-Host '    YouTube и Google такое не любят (страница грузится пустой). Лечится так:' -ForegroundColor DarkGray
            Write-Host ('    START.bat -Server 1   (номер от 1 до ' + $srvCount + ', можно перебрать)') -ForegroundColor DarkGray
        } else {
            Write-Host '[i] Режим: балансировщик leastPing, сервер в конфиге один — IP зависит только от него.' -ForegroundColor Green
        }
    }

    $cfgAge = ((Get-Date) - (Get-Item $Cfg).LastWriteTime).TotalDays

    $Exe = $null
    foreach ($dir in @((Join-Path $App 'LibreWolf'), $App, $Root)) {
        if (Test-Path $dir) {
            $Exe = Get-ChildItem -Path $dir -Recurse -Filter 'LibreWolf.exe' -ErrorAction SilentlyContinue |
                   Select-Object -First 1 -ExpandProperty FullName
            if (-not $Exe) {
                $Exe = Get-ChildItem -Path $dir -Recurse -Filter 'LibreWolf-Portable.exe' -ErrorAction SilentlyContinue |
                       Select-Object -First 1 -ExpandProperty FullName
            }
            if ($Exe) { break }
        }
    }
    if (-not $Exe) { Fail 'LibreWolf.exe не найден. Дома запусти ПОДГОТОВКА-ДОМА.bat (скачает браузер).' }
    $BrowserDir = Split-Path $Exe -Parent
    Log "браузер: $Exe"

    # --- остатки прошлой сессии: свой xray гасим, чужой процесс на порту — повод отказа ---
    $orphans = 0
    foreach ($p in @(Get-Process -Name 'xray' -ErrorAction SilentlyContinue)) {
        $path = ''
        try { $path = $p.Path } catch {}
        if ($path -and ($path -ieq $Xray)) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            $orphans++
        }
    }
    if ($orphans -gt 0) { Log ("погашен xray.exe от прошлой сессии: " + $orphans) }

    # --- порт на сессию: случайный, чтобы чужая «заготовка» на 10808 не получала трафик ---
    $Port = Get-FreePort
    if ($Port -le 0) { Fail 'Не удалось выбрать свободный порт для SOCKS — закрой лишние программы и повтори.' }
    Log "SOCKS-порт сессии: $Port"

    # --- профиль + жёсткая привязка к прокси ---
    New-Item -ItemType Directory -Force -Path $Profile | Out-Null
    Copy-Item $UserJs (Join-Path $Profile 'user.js') -Force
    $profUserJs = Join-Path $Profile 'user.js'
    $override = "user_pref(`"network.proxy.type`", 1);`r`n" +
                "user_pref(`"network.proxy.socks`", `"127.0.0.1`");`r`n" +
                "user_pref(`"network.proxy.socks_port`", $Port);`r`n"
    [IO.File]::AppendAllText($profUserJs, $override, (New-Object System.Text.UTF8Encoding $false))
    if (-not (Select-String -Path $profUserJs -Pattern ('network.proxy.socks_port' + '", ' + $Port) -SimpleMatch -Quiet)) {
        Fail ('Не удалось прописать SOCKS-порт ' + $Port + ' в ' + $profUserJs + '. Проверь, не защищён ли файл от записи, и запусти снова.')
    }
    $runningBrowser = @(Get-Process -Name 'librewolf', 'firefox' -ErrorAction SilentlyContinue)
    if ($runningBrowser.Count -gt 0) {
        Log "внимание: уже запущен браузер ($($runningBrowser.Count) проц.) — lock-файлы профиля не трогаю"
    } else {
        Remove-Item (Join-Path $Profile 'parent.lock'), (Join-Path $Profile '.parentlock') -ErrorAction SilentlyContinue
    }
    if ($ProfileTemp) { Log 'профиль сессии на локальном диске (%TEMP%), папка удаляется в конце' }
    Log "профиль: $Profile"

    $script:SessionCfg = New-SessionConfig $Port

    # --- реальный IP ДО старта VPN (один запрос, на диск не пишется) ---
    Write-Host '[..] Определяю прямой IP (для контроля утечки)...' -ForegroundColor DarkGray
    $RealIP = Get-ExtIP
    if ($RealIP) { Log 'прямой IP определён (значение намеренно не пишется в лог)' }
    else { Write-Host '[i] Прямой IP определить не удалось — проверка на утечку будет по ответу прокси' -ForegroundColor Yellow }

    # --- запуск xray ---
    $script:XrayProc = Start-XrayProc
    $stMain = Wait-SocksReady $script:XrayProc
    Assert-SocksOk $stMain 'Запуск не удался.'
    Log "SOCKS 127.0.0.1:$Port поднялся"

    $VpnIP = Get-ExtIP $Port
    if (-not $VpnIP) {
        if (Test-Path $SubFile) {
            Write-Host '[i] Сервера в config.json не отвечают. Обновить подписку отсюда нельзя:' -ForegroundColor Yellow
            Write-Host '    запрос к API идёт только через живой туннель. Дома запусти:' -ForegroundColor Yellow
            Write-Host '    powershell -ExecutionPolicy Bypass -File app\update-sub.ps1' -ForegroundColor Yellow
        }
        Fail 'Через VPN не удалось определить внешний IP (сервер недоступен/блокируется). Браузер НЕ запущен.'
    }
    if ($RealIP -and ($VpnIP -eq $RealIP)) {
        Fail 'УТЕЧКА ещё до старта: через прокси виден тот же IP, что и напрямую (значение не пишу в лог). Браузер НЕ запущен.'
    }
    Log "внешний IP через VPN: $VpnIP"
    Write-Host "[OK] Внешний IP через VPN: $VpnIP" -ForegroundColor Green
    if ($RealIP) { Write-Host '     (прямой IP отличается — значение не показываю)' -ForegroundColor DarkGray }

    # --- АВТООБНОВЛЕНИЕ ПОДПИСКИ ЧЕРЕЗ ТУННЕЛЬ ---
    if ($ForceUpdate -and -not (Test-Path $SubFile)) {
        Write-Host '[i] -ForceUpdate: vpn\sub.txt нет — обновлять нечего (конфиг собран из vless:// ссылок).' -ForegroundColor Yellow
    }
    if ((Test-Path $SubFile) -and ($ForceUpdate -or ($cfgAge -ge $SubMaxAgeDays))) {
        if ($ForceUpdate) {
            Write-Host '[..] -ForceUpdate: обновляю подписку ЧЕРЕЗ VPN принудительно...' -ForegroundColor Yellow
            Log 'принудительное обновление подписки (-ForceUpdate)'
        } else {
            Write-Host "[..] Конфигу $([int]$cfgAge) дн. — обновляю подписку ЧЕРЕЗ VPN..." -ForegroundColor Yellow
            Log "авто-обновление подписки (конфигу $([int]$cfgAge) дн.)"
        }
        try {
            $sp = Read-SubParams $SubFile
            $nodes = @()
            if ($sp -and -not ($sp.url -like 'https://*')) {
                Log 'авто-обновление: URL подписки не https — пропускаю'
            }
            if ($sp -and ($sp.url -like 'https://*')) {
                $text = Get-SubBody $sp.url $sp.hwid $sp.ua $Port
                if ($text) { $nodes = @(ConvertTo-Nodes $text) }
            }
            if ($nodes.Count -gt 0) {
                Copy-Item $Cfg ($Cfg + '.bak.json') -Force
                [IO.File]::WriteAllText($Cfg, (New-ConfigJson $nodes), (New-Object System.Text.UTF8Encoding $false))
                Save-KitCopies
                Log "получено $($nodes.Count) сервер(ов) — перезапускаю xray с новым конфигом"
                Stop-OurXray
                $script:SessionCfg = New-SessionConfig $Port
                $script:XrayProc = Start-XrayProc
                $stNew = Wait-SocksReady $script:XrayProc
                $okNew = ($stNew -eq 'ok')
                $ipNew = ''
                if ($okNew) { $ipNew = Get-ExtIP $Port }
                if ($okNew -and $ipNew -and -not ($RealIP -and ($ipNew -eq $RealIP))) {
                    $VpnIP = $ipNew
                    Log "обновление успешно: $ipNew"
                    Write-Host "[OK] Конфиг обновлён ($($nodes.Count) серверов), IP через VPN: $ipNew" -ForegroundColor Green
                } else {
                    Write-Host '[!] Новый конфиг не заработал — откатываю на прежний' -ForegroundColor Red
                    Log 'новый конфиг не прошёл проверку — откат на config.bak.json'
                    Stop-OurXray
                    Copy-Item ($Cfg + '.bak.json') $Cfg -Force
                    $script:SessionCfg = New-SessionConfig $Port
                    $script:XrayProc = Start-XrayProc
                    $stBack = Wait-SocksReady $script:XrayProc
                    Assert-SocksOk $stBack 'Откат на прежний конфиг не удался.'
                    $ipOld = Get-ExtIP $Port
                    if (-not $ipOld -or ($RealIP -and ($ipOld -eq $RealIP))) {
                        Fail 'После отката VPN не отвечает.'
                    }
                    $VpnIP = $ipOld
                    Log "откат успешен: $ipOld"
                    Write-Host "[OK] Работаю на прежнем конфиге, IP через VPN: $ipOld" -ForegroundColor Green
                }
            } else {
                Log 'обновление не дало серверов — работаю на текущем конфиге'
            }
        } catch {
            if ("$($_.Exception.Message)" -eq '__LWUSB_STOP__') { throw }
            Write-Host ('[!] Обновление подписки не удалось: ' + $_.Exception.Message) -ForegroundColor Yellow
            Log ('ошибка обновления подписки: ' + $_.Exception.Message)
        }
    } elseif ((Test-Path $Cfg) -and ($cfgAge -ge 7)) {
        Write-Host "[i] Конфигу VPN уже $([int]$cfgAge) дн. — серверы могли смениться." -ForegroundColor Yellow
        Write-Host '    vpn\sub.txt нет — авто-обновление невозможно, дома обнови конфиг.' -ForegroundColor Yellow
        Log "конфигу $([int]$cfgAge) дней (sub.txt нет — авто-обновление невозможно)"
    }

    # --- watchdog: xray жив, SOCKS отвечает, IP не совпадает, браузер не ходит мимо ---
    $s = [hashtable]::Synchronized(@{})
    $s.stop = $false
    $s.breach = ''
    $s.xrayPid = $script:XrayProc.Id
    $s.xrayStart = $script:XrayProc.StartTime
    $s.xrayExe = $Xray
    $s.browserExe = $Exe
    $s.browserDir = $BrowserDir
    $s.port = $Port
    $s.lastIP = $VpnIP
    $s.onlyServer = $script:OnlyServer
    $s.serverCount = $srvCount
    $s.ipChanges = 0
    $s.curl = $Curl
    $s.taskkill = $Taskkill
    $s.netstat = $Netstat
    $s.events = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))

    $WatchdogSrc = @'
# $s — синхронизированная hashtable, передана через SessionStateProxy.SetVariable
function Get-IP([int]$P) {
    foreach ($u in @('https://api.ipify.org','https://ifconfig.me/ip')) {
        try {
            $r = & $s.curl -s --max-time 12 --socks5-hostname "127.0.0.1:$P" $u 2>$null
            $r = "$r".Trim()
            if ($r -match '^[0-9a-fA-F.:\[\]]+$' -and $r.Length -le 45) { return $r }
        } catch {}
    }
    return ''
}

# Соединения процессов нашего браузера: любое НЕ на loopback = трафик мимо прокси.
# Это единственный детектор, который ловит обход ещё до смены IP.
function Get-BrowserPids {
    $list = @()
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
        $path = ''
        try { $path = $p.Path } catch {}
        if ($path -and $path.StartsWith($s.browserDir, [StringComparison]::OrdinalIgnoreCase)) { $list += [int]$p.Id }
    }
    return $list
}

function Get-BrowserLeak {
    $pids = @(Get-BrowserPids)
    if ($pids.Count -eq 0) { return '' }
    $loopback = '(^127\.)|(^::1$)|(^0\.0\.0\.0$)|(^::$)|(^::ffff:127\.)'
    try {
        $conns = @(Get-NetTCPConnection -State Established -ErrorAction Stop)
        foreach ($c in $conns) {
            if ($pids -notcontains [int]$c.OwningProcess) { continue }
            $ra = "$($c.RemoteAddress)"
            if ($ra -match $loopback) { continue }
            return "браузер соединился с ${ra}:$($c.RemotePort) мимо прокси"
        }
        return ''
    } catch {}
    # запасной путь: netstat -ano
    try {
        foreach ($l in @(& $s.netstat -ano 2>$null)) {
            $t = ("$l".Trim()) -split '\s+'
            if ($t.Count -lt 5 -or "$l" -notmatch 'ESTABLISHED') { continue }
            if ($pids -notcontains [int]$t[-1]) { continue }
            $remote = "$($t[2])"
            $ip = $remote.Substring(0, $remote.LastIndexOf(':'))
            if ($ip -match $loopback) { continue }
            return "браузер соединился с $remote мимо прокси"
        }
    } catch {}
    return ''
}

function Breach([string]$why) {
    try {
        foreach ($bp in @(Get-BrowserPids)) { & $s.taskkill /PID $bp /T /F 2>$null | Out-Null }
        foreach ($p in @(Get-Process -Name 'librewolf','firefox','xray' -ErrorAction SilentlyContinue)) {
            $path = ''
            try { $path = $p.Path } catch {}
            if ($path -and (($path.StartsWith($s.browserDir, [StringComparison]::OrdinalIgnoreCase)) -or ($path -ieq $s.xrayExe))) {
                Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {}
    $admin = $false
    try {
        $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
                 ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {}
    if ($admin) {
        try {
            New-NetFirewallRule -DisplayName 'LibreWolf-USB-KILLSWITCH' -Direction Outbound `
                -Program $s.browserExe -Action Block -ErrorAction SilentlyContinue | Out-Null
            New-NetFirewallRule -DisplayName 'LibreWolf-USB-KILLSWITCH-XRAY' -Direction Outbound `
                -Program "$($s.xrayExe)" -Action Block -ErrorAction SilentlyContinue | Out-Null
        } catch {}
    }
    $s.breach = $why
}

$ipFail = 0
$sockFail = 0
$leakWarned = $false
while (-not $s.stop) {
    Start-Sleep -Milliseconds 5000
    if ($s.stop) { break }

    $xp = $null
    try { $xp = Get-Process -Id $s.xrayPid -ErrorAction Stop } catch {}
    if (-not $xp) { Breach 'Xray прекратил работу (обход VPN стал возможен)'; break }
    $xpath = ''
    try { $xpath = $xp.Path } catch {}
    $sameFile = $true
    if ($xpath) { $sameFile = ($xpath -ieq $s.xrayExe) }
    $sameStart = $false
    try { $sameStart = ($xp.StartTime -eq $s.xrayStart) } catch {}
    if ((-not $sameFile) -and (-not $sameStart)) { Breach 'процесс с PID xray оказался другим файлом'; break }

    $sockOk = $false
    try {
        $tc = New-Object Net.Sockets.TcpClient
        $tt = $tc.ConnectAsync('127.0.0.1', $s.port)
        if ($tt.Wait(1500) -and $tc.Connected) { $sockOk = $true }
        $tc.Dispose()
    } catch {}
    if (-not $sockOk) {
        $sockFail++
        if ($sockFail -ge 3) { Breach 'SOCKS-прокси перестал отвечать'; break }
    } else { $sockFail = 0 }

    $leak = Get-BrowserLeak
    if ($leak) { Breach $leak; break }

    $ip = Get-IP $s.port
    if ($ip) {
        if ($s.lastIP -and ($ip -ne $s.lastIP)) {
            [void]$s.events.Add("IP через VPN сменился: $($s.lastIP) -> $ip")
            $s.ipChanges = [int]$s.ipChanges + 1
            if (($s.onlyServer -gt 0) -and ([int]$s.ipChanges -eq 2)) {
                [void]$s.events.Add("ВНИМАНИЕ: включён режим -Server $($s.onlyServer), но выходной IP меняется — этот сервер сам меняет выход. Перебери номера (меню, пункт 2).")
            }
            $s.lastIP = $ip
        }
        if ($s.realIP -and ($ip -eq $s.realIP)) { Breach 'УТЕЧКА: через прокси виден тот же IP, что и напрямую'; break }
        $ipFail = 0
    } else {
        $ipFail++
        if ($ipFail -ge 3) { Breach 'VPN перестал отвечать (IP через прокси не определяется)'; break }
    }
}
'@

    $s.realIP = $RealIP
    $Rs = [runspacefactory]::CreateRunspace()
    $Rs.ApartmentState = 'STA'
    $Rs.Open()
    $Rs.SessionStateProxy.SetVariable('s', $s)
    $Ps = [powershell]::Create()
    $Ps.Runspace = $Rs
    [void]$Ps.AddScript($WatchdogSrc)
    $Handle = $Ps.BeginInvoke()
    Log 'kill-switch активен (xray + SOCKS + IP + соединения браузера)'

    # --- запуск браузера ---
    Log 'запуск LibreWolf (профиль на флешке, прокси зашит в user.js)'
    $Browser = Start-Process -FilePath $Exe -ArgumentList ('-no-remote -profile "' + $Profile + '"') -PassThru
    $s.browserPid = $Browser.Id
    $script:BrowserPid = $Browser.Id

    Write-Host ''
    Write-Host '[>>] Браузер запущен. Закрой его сам, когда закончишь.' -ForegroundColor Green
    Write-Host '     kill-switch работает в этом окне — не закрывай его до конца сессии.' -ForegroundColor Yellow
    Write-Host ('     SOCKS-порт этой сессии: ' + $Port + '  (в about:config параметр network.proxy.socks_port должен быть такой же)') -ForegroundColor Cyan
    Write-Host '     Окно браузера с флешки может появиться через 20-60 секунд — это нормально.' -ForegroundColor DarkGray
    Write-Host '     Не запускай START.bat второй раз и не закрывай это окно.' -ForegroundColor DarkGray
    Write-Host ''

    # --- браузер обязан взять НАШ профиль: ждём lock-файл в папке профиля ---
    $lockSeen = $false
    for ($i = 0; $i -lt 24; $i++) {
        if ((Test-Path (Join-Path $Profile 'parent.lock')) -or (Test-Path (Join-Path $Profile '.parentlock')) -or (Test-Path (Join-Path $Profile 'lock'))) { $lockSeen = $true; break }
        if (-not (Get-Process -Id $Browser.Id -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Milliseconds 500
    }
    if ($lockSeen) {
        Log 'профиль на флешке занят браузером (lock-файл есть) — порт берётся из user.js'
    } else {
        Log 'ВНИМАНИЕ: браузер не занял профиль на флешке (lock-файла нет)'
        Write-Host '[!] Браузер не взял профиль с флешки — похоже, он открылся со своим профилем.' -ForegroundColor Red
        Write-Host ('    Должен быть профиль: ' + $Profile) -ForegroundColor Red
        Write-Host '    Проверь в браузере: about:support -> Profile Folder.' -ForegroundColor Yellow
        Write-Host '    Если путь другой — закрой ВСЕ окна LibreWolf и запусти START.bat заново.' -ForegroundColor Yellow
        Write-Host ''
    }

    # --- ожидание завершения / срабатывания kill-switch ---
    # PID от Start-Process — это лончер: он умирает, передав работу настоящему процессу.
    # Следим за всеми процессами из папки браузера + за lock-файлом профиля.
    $sawLock = $false
    $goneFor = 0
    while ($true) {
        if ($s.breach) { $script:Breach = "$($s.breach)"; break }
        $bpids = @(Get-KitBrowserPids $BrowserDir)
        $lockNow = ((Test-Path (Join-Path $Profile 'parent.lock')) -or (Test-Path (Join-Path $Profile '.parentlock')))
        if ($lockNow) { $sawLock = $true }
        if (($bpids.Count -gt 0) -or $lockNow) {
            $goneFor = 0
        } else {
            $goneFor++
            $limit = 20
            if ($sawLock) { $limit = 8 }
            if ($goneFor -ge $limit) { break }
        }
        while ($s.events.Count -gt 0) {
            $ev = $s.events[0]; $s.events.RemoveAt(0)
            Log $ev
        }
        Start-Sleep -Milliseconds 1000
    }

    # --- остановка watchdog ---
    $s.stop = $true
    Start-Sleep -Milliseconds 6500
    if (-not $Ps.IsCompleted) { try { $Ps.Stop() } catch {} }
    try { $Ps.Dispose(); $Rs.Close() } catch {}

    if ($script:Breach) {
        Log "сессия ПРЕРВАНА: $($script:Breach)"
        foreach ($bp in @(Get-KitBrowserPids $BrowserDir)) { & $Taskkill /PID $bp /T /F 2>$null | Out-Null }
        Stop-OurXray
        Write-Host ''
        Write-Host "[!!] Сессия прервана kill-switch'ем: $($script:Breach)" -ForegroundColor Red
        Write-Host '     Если хочешь продолжить — проверь интернет/VPN и запусти START.bat заново.' -ForegroundColor Yellow
        $script:FailCode = 2
        throw '__LWUSB_STOP__'
    }

    Log 'браузер закрыт пользователем, xray остановлен, сессия чистая'
    Write-Host ''
    Write-Host '[OK] Браузер закрыт. VPN выключен, правила брандмауэра снимаются.' -ForegroundColor Green

    if (Ask-Cleanup) {
        Write-Host ''
        Log 'чистка следов по запросу после закрытия браузера'
        & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $App 'clean-traces.ps1')
        Write-Host ''
        Write-Host '[OK] Следы этой сессии убраны. Флешку можно вынимать.' -ForegroundColor Green
    } else {
        Write-Host '[i] Следы не тронуты. Убрать позже: меню → пункт 6.' -ForegroundColor DarkGray
    }
}
catch {
    $msg = "$($_.Exception.Message)"
    if ($msg -ne '__LWUSB_STOP__') {
        Write-Host ''
        Write-Host "[X] Непредвиденная ошибка: $msg" -ForegroundColor Red
        try { Add-Content -Path $LogFile -Value "[XX] $msg" -Encoding UTF8 } catch {}
        $script:FailCode = 1
    }
}
finally {
    # уборка при любом выходе: без неё xray переживал скрипт (баг из отчёта)
    Stop-OurXray
    try {
        $left = @(Get-NetFirewallRule -DisplayName 'LibreWolf-USB-KILLSWITCH*' -ErrorAction SilentlyContinue)
        if ($left.Count -gt 0) {
            $left | Remove-NetFirewallRule -ErrorAction SilentlyContinue
            Log ("сняты правила брандмауэра этой сессии: " + $left.Count)
        }
    } catch {}
    if ($script:SessionCfg -and (Test-Path $script:SessionCfg)) {
        Remove-Item $script:SessionCfg -Force -ErrorAction SilentlyContinue
    }
    if ($ProfileTemp -and $Profile -and (Test-Path $Profile)) {
        for ($i = 0; $i -lt 6; $i++) {
            try { Remove-Item $Profile -Recurse -Force -ErrorAction Stop; break } catch { Start-Sleep -Milliseconds 500 }
        }
        if (Test-Path $Profile) { Log ("не удалось удалить временный профиль: " + $Profile) }
        else { Log 'временный профиль удалён с локального диска' }
    }
    Log 'сессия завершена'
}

exit $script:FailCode
