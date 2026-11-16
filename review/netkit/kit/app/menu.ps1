# menu.ps1 — главное меню комплекта LibreWolf-USB.
# Без анимации и без ANSI: цвета задаются консольными цветами (работают в conhost,
# Windows Terminal и в переадресованном выводе), экран перерисовывается только
# после действия. Пункты сгруппированы, у каждого — пояснение и справка (?N).
$ErrorActionPreference = 'Stop'

$App     = $PSScriptRoot
$Root    = Split-Path -Parent $App
$Vpn     = Join-Path $Root 'vpn'
$Cfg     = Join-Path $Vpn 'config.json'
$SubFile = Join-Path $Vpn 'sub.txt'

$Build = 'F-66'

$psExe = 'powershell.exe'
if (-not $env:SystemRoot) {
    $p = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($p) { $psExe = $p.Source }
}

$W = 78   # ширина рамки

# ---------------------------------------------------------------- данные
function Get-Servers {
    $res = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path $Cfg)) { return $res }
    try {
        $o = Get-Content $Cfg -Raw -Encoding UTF8 | ConvertFrom-Json
        $i = 0
        foreach ($ob in @($o.outbounds)) {
            $i++
            $addr = '(без адреса)'
            try { $v = @($ob.settings.vnext)[0]; $addr = "$($v.address):$($v.port)" } catch { }
            $sec = "$($ob.streamSettings.security)"
            if (-not $sec) { $sec = '?' }
            $res.Add(@($i, $addr, $sec))
        }
    } catch { }
    return $res
}

function Get-State {
    $s = New-Object System.Collections.Generic.List[object]
    $browser = Test-Path (Join-Path $App 'LibreWolf\LibreWolf.exe')
    $xray = Test-Path (Join-Path $Vpn 'xray.exe')
    $s.Add(@('Браузер', $(if ($browser) { 'есть' } else { 'нет' }), $browser, 'пункт 4'))
    $s.Add(@('Xray', $(if ($xray) { 'есть' } else { 'нет' }), $xray, 'пункт 4'))
    $servers = @(Get-Servers)
    if ($servers.Count -gt 0) {
        $age = [int]((Get-Date) - (Get-Item $Cfg).LastWriteTime).TotalDays
        $s.Add(@('Серверы', ("$($servers.Count) шт., обновлены $age дн. назад"), $true, 'пункт 3'))
    } else {
        $s.Add(@('Серверы', 'нет', $false, 'пункт 3/4'))
    }
    $hasSub = ((Test-Path $SubFile) -and ((Get-Content $SubFile -Raw -ErrorAction SilentlyContinue) -match 'url\s*=\s*\S+'))
    $s.Add(@('Подписка', $(if ($hasSub) { 'настроена' } else { 'нет' }), $hasSub, 'пункт 4'))
    $s.Add(@('Профиль', $(if (Test-Path (Join-Path $Root 'profile')) { 'на флешке есть' } else { 'чистый' }), $true, ''))
    return $s
}

# ---------------------------------------------------------------- рисование
function Write-Rule([string]$text) {
    $d = [string][char]0x2500
    $head = ' ' + $text + ' '
    $n = $W - 2 - $head.Length
    if ($n -lt 2) { $n = 2 }
    Write-Host ('  ' + $d + $d) -ForegroundColor DarkCyan -NoNewline
    Write-Host $head -ForegroundColor Cyan -NoNewline
    Write-Host ($d * $n) -ForegroundColor DarkCyan
}

function Show-Header {
    $d = [string][char]0x2500
    $c = [string][char]0x250C
    $c2 = [string][char]0x2510
    $c3 = [string][char]0x2514
    $c4 = [string][char]0x2518
    $v = [string][char]0x2502

    $title = ' LibreWolf-USB '
    $ver = ' ' + $Build + ' '
    $fill = $W - 2 - $title.Length - $ver.Length
    if ($fill -lt 2) { $fill = 2 }

    Write-Host ('  ' + $c) -ForegroundColor DarkCyan -NoNewline
    Write-Host $title -ForegroundColor White -NoNewline
    Write-Host ($d * $fill) -ForegroundColor DarkCyan -NoNewline
    Write-Host $ver -ForegroundColor DarkCyan -NoNewline
    Write-Host $c2 -ForegroundColor DarkCyan

    $l1 = ' Портативный браузер с обходом блокировок'
    $l2 = ' Ничего не устанавливается: всё живёт на флешке'
    foreach ($l in @($l1, $l2)) {
        Write-Host ('  ' + $v) -ForegroundColor DarkCyan -NoNewline
        Write-Host $l -ForegroundColor Gray -NoNewline
        Write-Host ((' ' * [Math]::Max(0, $W - 2 - $l.Length)) + $v) -ForegroundColor DarkCyan
    }

    Write-Host ('  ' + $c3 + ($d * ($W - 2)) + $c4) -ForegroundColor DarkCyan
}

function Show-State {
    $st = @(Get-State)
    Write-Host '  ' -NoNewline
    $i = 0
    foreach ($s in $st) {
        if ($i -gt 0) { Write-Host '  ·  ' -ForegroundColor DarkGray -NoNewline }
        Write-Host ($s[0] + ': ') -ForegroundColor DarkGray -NoNewline
        if ($s[2]) { Write-Host $s[1] -ForegroundColor Green -NoNewline }
        else { Write-Host $s[1] -ForegroundColor Red -NoNewline }
        $i++
    }
    Write-Host ''
    $bad = @($st | Where-Object { -not $_[2] })
    if ($bad.Count -gt 0) {
        $what = @($bad | ForEach-Object { $_[0] }) -join ', '
        $hints = @($bad | ForEach-Object { $_[3] } | Where-Object { $_ -ne '' } | Select-Object -Unique) -join ', '
        Write-Host ('  Не хватает: ' + $what) -ForegroundColor Yellow -NoNewline
        if ($hints) { Write-Host ('  →  ' + $hints) -ForegroundColor DarkYellow }
        else { Write-Host '' }
    }
}

function Show-Item([string]$num, [string]$name, [string]$desc) {
    $color = 'Yellow'
    if ($num -eq '0') { $color = 'Red' }
    Write-Host ('   [' + $num + '] ') -ForegroundColor $color -NoNewline
    Write-Host $name -ForegroundColor White
    if ($desc) { Write-Host ('        ' + $desc) -ForegroundColor DarkGray }
}

function Show-Menu {
    Show-Header
    Write-Host ''
    Show-State
    Write-Host ''

    Write-Rule 'ЗАПУСК'
    Show-Item '1' 'Запустить браузер через VPN' 'сервер выбирается автоматически; если ключи под паролем — спросит пароль'
    Show-Item '2' 'Запустить и выбрать сервер' 'один сервер на сессию — для YouTube и Госуслуг, где важна постоянная страна'

    Write-Rule 'ДОМА (нужен домашний интернет)'
    Show-Item '3' 'Обновить список серверов из подписки' 'берёт свежие сервера; в колледже не запускать'
    Show-Item '4' 'Подготовка комплекта' 'скачать браузер и Xray, вставить ключ или подписку'

    Write-Rule 'ОБСЛУЖИВАНИЕ'
    Show-Item '5' 'Собрать архив для переноса' 'один zip из этого комплекта (можно без секретов)'
    Show-Item '6' 'Почистить следы на этом ПК' 'история, кэш миниатюр, временные файлы'
    Show-Item '7' 'Проверить комплект' 'офлайн-проверки конфига, ничего не меняет'
    Show-Item '8' 'Ускорить флешку и проводник' 'замер, где тормозит, и настройки Windows против лагов'
    Show-Item '9' 'Проверить IP и страну' 'браузер не нужен: что видят сайты через туннель'
    Show-Item '10' 'Задержка до серверов (пинг)' 'какой сервер быстрее отвечает; браузер не нужен'
    Show-Item '0' 'Выход' ''

    Write-Host ''
    Write-Host '  Введи номер и нажми Enter.  ' -ForegroundColor DarkGray -NoNewline
    Write-Host 'Подробнее о пункте: ?4' -ForegroundColor DarkCyan
}

function Show-Help([string]$num) {
    $lines = @()
    switch ($num) {
        '1' {
            $lines = @(
                'Пункт 1 — обычный запуск.',
                '',
                'Что делает: поднимает туннель Xray, проверяет, что браузер реально идёт',
                'через прокси, и открывает LibreWolf с профилем на флешке. Пока браузер',
                'открыт, скрипт следит за утечками: если xray упал или браузер пошёл мимо',
                'прокси, сессия закрывается.',
                '',
                'Сервер выбирается балансировщиком на каждое соединение, поэтому выходной',
                'IP меняется. Для YouTube, Google и Госуслуг это плохо — используй пункт 2.',
                '',
                'Когда закроешь окно браузера, сессия сама погасит VPN и предложит почистить',
                'следы на этом ПК: Enter — чистить, N — оставить, 30 секунд без ответа — пропустить.',
                '',
                'Пароль: если ключи на флешке зашифрованы, при каждом запуске спрашивается',
                'пароль (ввод не отображается, 3 попытки). Задаётся он один раз — при первом',
                'запуске пункта 1: скрипт предложит поставить пароль и сразу зашифрует',
                'config.json и sub.txt. Забыл пароль — ключи не восстановить.'
                '',
                'Команда: powershell -ExecutionPolicy Bypass -File app\start.ps1'
            )
        }
        '2' {
            $lines = @(
                'Пункт 2 — запуск с выбором сервера.',
                '',
                'Покажет список серверов из vpn\config.json с номерами и адресами.',
                'Введи номер — вся сессия пойдёт через один сервер, выходной IP перестанет',
                'меняться. Если номер не вводить, будет как в пункте 1.',
                '',
                'Дополнительно можно добавить:',
                '  -IgnorePolicies — запуститься, даже если в реестре заданы политики Firefox.',
                '      Без флага скрипт откажется: политика может подсунуть свой прокси или',
                '      расширение, и браузер пойдёт мимо туннеля. Нужен только на своём ПК.',
                '  -Debug — подробный вывод, если что-то не работает.',
                'Оба флага обычно не нужны: Enter — и запуск пойдёт как в пункте 1, но через',
                'выбранный сервер.',
                '',
                'Команда: powershell -ExecutionPolicy Bypass -File app\start.ps1 -Server N'
            )
        }
        '3' {
            $lines = @(
                'Пункт 3 — обновление серверов из подписки.',
                '',
                'Запрашивает список серверов по ссылке из vpn\sub.txt и пересобирает',
                'vpn\config.json. Требуется домашний интернет: в колледже запрос к серверу',
                'подписки не пройдёт. Старый конфиг сохраняется как config.json.bak.json.',
                '',
                'Команда: powershell -ExecutionPolicy Bypass -File app\update-sub.ps1'
            )
        }
        '4' {
            $lines = @(
                'Пункт 4 — подготовка комплекта (только дома).',
                '',
                '1) Скачивает портативный LibreWolf с GitLab и Xray с GitHub.',
                '2) Сверяет sha256 с опубликованными суммами.',
                '3) Распаковывает всё на флешку и спрашивает ключ vless:// или ссылку',
                '   подписки, после чего собирает vpn\config.json.',
                '',
                'Уже установленное пропускается; переустановить — добавить -Force.',
                'Скачанное складывается в _download\ и удаляется после распаковки.',
                '',
                'Команда: powershell -ExecutionPolicy Bypass -File app\prepare-home.ps1'
            )
        }
        '5' {
            $lines = @(
                'Пункт 5 — собрать архив для переноса.',
                '',
                'Упаковывает комплект в один zip: батник, скрипты, README и пример',
                'конфига. Браузер, Xray и профиль в архив не попадают (они большие).',
                'Ключ -NoSecrets исключает vpn\sub.txt и vpn\config.json — используй его,',
                'если архив кому-то передаёшь.',
                '',
                'Команда: powershell -ExecutionPolicy Bypass -File app\make-bundle.ps1 -NoSecrets'
            )
        }
        '6' {
            $lines = @(
                'Пункт 6 — чистка следов на этом ПК.',
                '',
                'Убирает историю PowerShell, временные файлы комплекта, кэш миниатюр,',
                'списки недавних файлов, журналы ошибок и DNS-кэш. С -Deep дополнительно',
                'чистит Prefetch (нужен администратор), с -Scrub стирает профиль браузера',
                'на флешке.',
                '',
                'Кэш оперативной памяти скриптом не чистится — это ограничение Windows.',
                '',
                'Команда: powershell -ExecutionPolicy Bypass -File app\clean-traces.ps1 -Deep'
            )
        }
        '7' {
            $lines = @(
                'Пункт 7 — проверка комплекта.',
                '',
                'Прогоняет офлайн-проверки: разбор vless-ссылок, сборка JSON, отбрасывание',
                'незашифрованных узлов, линтер конфига. Ничего не скачивает и не меняет',
                'настройки ПК — можно запускать где угодно.',
                '',
                'Команда: powershell -ExecutionPolicy Bypass -File app\self-check.ps1'
            )
        }
        '8' {
            $lines = @(
                'Пункт 8 — почему проводник тормозит и как это уменьшить.',
                '',
                '1) Считает файлы и время обхода по папкам комплекта: корень флешки,',
                '   app\LibreWolf (сам браузер), profile (история и кэш). Проводник делает',
                '   ту же работу при входе в папку, поэтому сразу видно виновника.',
                '2) Меряет скорость мелких операций записи — главный тормоз дешёвых флешек.',
                '3) По согласию меняет настройки проводника: значки вместо эскизов, без',
                '   подсказок-задержек, без недавних документов, не индексировать флешку.',
                '',
                'Ничего не удаляет. Откат указан в конце вывода.',
                '',
                'Команда: powershell -ExecutionPolicy Bypass -File app\speed-up.ps1'
            )
        }
        '9' {
            $lines = @(
                'Пункт 9 — что о вас знают сайты.',
                '',
                'Поднимает туннель на отдельном порту (браузер не запускается) и спрашивает',
                'три сервиса: ipinfo.io, api.myip.com, ipapi.co. Показывает IP, страну, город',
                'и провайдера. Если сервисы расходятся по стране — так и скажет.',
                '',
                'Зачем: когда «VPN включён, а Google показывает не ту страну». Google берёт',
                'страну не только из IP: ещё из cookie профиля и из DNS-подсказки сервера.',
                'Проверка в приватном окне (Ctrl+Shift+P) показывает, кто виноват.',
                '',
                'Команда: powershell -ExecutionPolicy Bypass -File app\ip-check.ps1'
            )
        }
        '10' {
            $lines = @(
                'Пункт 10 — пинг серверов.',
                '',
                'Меряет задержку до каждого сервера из vpn\config.json: TCP-подключение',
                'к его адресу и порту, без ICMP и без прав администратора. Показывает',
                'миллисекунды по каждому и подсказывает, какой номер брать в пункте 2.',
                '',
                'Это задержка до сервера, а не скорость через него: 40 мс — отличный',
                'сервер, 150-250 мс — рабочий, 800+ или «нет ответа» — сервер далеко',
                'или перегружен.',
                '',
                'То же самое сессия делает сама: пока браузер открыт, задержки печатаются',
                'раз в 30 секунд. Нажать пинг вручную в сессии — клавиша p, затем Enter.',
                '',
                'Команда: powershell -ExecutionPolicy Bypass -File app\ping-servers.ps1'
            )
        }
        '0' {
            $lines = @('Пункт 0 — выйти из меню. Сессия браузера при этом не закрывается.')
        }
        default {
            $lines = @('Такого пункта нет. Введи ?1 … ?9 или ?0.')
        }
    }
    Write-Host ''
    foreach ($l in $lines) {
        if ($l -like 'Пункт*') { Write-Host ('  ' + $l) -ForegroundColor Cyan }
        elseif ($l -like 'Команда:*') { Write-Host ('  ' + $l) -ForegroundColor DarkCyan }
        elseif ($l -eq '') { Write-Host '' }
        else { Write-Host ('  ' + $l) -ForegroundColor Gray }
    }
    Write-Host ''
    Write-Host '  Enter — назад в меню...' -ForegroundColor DarkGray -NoNewline
    $null = Read-Host
}

# ---------------------------------------------------------------- действия
function Run-PS([string]$Script, [string[]]$ScriptArgs = @()) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Script) + $ScriptArgs
    Write-Host ''
    # Out-Host: вывод идёт на экран, а функция возвращает только код
    & $psExe @a | Out-Host
    $code = $LASTEXITCODE
    Write-Host ''
    Write-Host ('   [код возврата: ' + $code + ']') -ForegroundColor DarkGray
    return $code
}

function Pause-Menu {
    Write-Host ''
    Write-Host '   Enter — назад в меню...' -ForegroundColor DarkGray -NoNewline
    $null = Read-Host
}

function Ask-Server {
    $list = @(Get-Servers)
    if ($list.Count -eq 0) {
        Write-Host ''
        Write-Host '   В vpn\config.json нет серверов — сначала пункт 3 или 4.' -ForegroundColor Yellow
        return $null
    }
    Write-Host ''
    Write-Host ('   Серверов в конфиге: ' + $list.Count) -ForegroundColor Gray
    foreach ($s in $list) {
        Write-Host ('   ' + (' ' + $s[0]).PadLeft(3) + '.  ') -ForegroundColor Yellow -NoNewline
        Write-Host ($s[1].PadRight(30)) -ForegroundColor White -NoNewline
        Write-Host $s[2] -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '   Номер сервера (Enter — без фиксации, IP будет меняться):' -ForegroundColor Gray
    Write-Host '   > ' -ForegroundColor Green -NoNewline
    $num = (Read-Host).Trim()

    $args2 = @()
    if ($num -match '^\d+$' -and [int]$num -ge 1) {
        if ([int]$num -gt $list.Count) {
            Write-Host ('   В конфиге ' + $list.Count + ' сервер(ов) — запускаю без фиксации.') -ForegroundColor Yellow
            Start-Sleep -Milliseconds 900
        } else {
            $args2 += @('-Server', $num)
            Write-Host ('   Выбран сервер ' + $num + ': ' + $list[[int]$num - 1][1] + ' — IP меняться не будет.') -ForegroundColor Green
        }
    } elseif ($num -ne '') {
        Write-Host '   Номер не разобран — запускаю без фиксации.' -ForegroundColor Yellow
        Start-Sleep -Milliseconds 900
    } else {
        Write-Host '   Без номера: балансировщик, выходной IP будет меняться.' -ForegroundColor Yellow
        Start-Sleep -Milliseconds 700
    }

    Write-Host ''
    Write-Host '   Дополнительно (обычно не нужно — просто Enter):' -ForegroundColor Gray
    Write-Host '     -IgnorePolicies  запуститься, даже если на ПК заданы политики Firefox' -ForegroundColor DarkGray
    Write-Host '     -Debug           подробный вывод для разбора проблем' -ForegroundColor DarkGray
    Write-Host '   > ' -ForegroundColor Green -NoNewline
    $extra = (Read-Host).Trim()
    if ($extra -ne '') { $args2 += ($extra -split '\s+') }
    return ,$args2
}

function Ask-Clean {
    Write-Host ''
    Write-Host '   Обычная чистка — Enter.' -ForegroundColor Gray
    Write-Host '   -Deep  — плюс Prefetch, нужен администратор.' -ForegroundColor Gray
    Write-Host '   -Scrub — плюс стереть профиль браузера на флешке.' -ForegroundColor Gray
    Write-Host '   > ' -ForegroundColor Green -NoNewline
    $extra = (Read-Host).Trim()
    if ($extra -eq '') { return @() }
    return ($extra -split '\s+')
}

# ---------------------------------------------------------------- цикл
while ($true) {
    Clear-Host
    Show-Menu
    Write-Host '  Выбор > ' -ForegroundColor Green -NoNewline
    $choice = (Read-Host).Trim()

    if ($choice -match '^\?') {
        Show-Help ($choice.TrimStart('?').Trim())
        continue
    }

    switch ($choice) {
        '1' {
            [void](Run-PS (Join-Path $App 'start.ps1'))
            Pause-Menu
        }
        '2' {
            $a = Ask-Server
            if ($null -ne $a) { [void](Run-PS (Join-Path $App 'start.ps1') $a) }
            Pause-Menu
        }
        '3' {
            [void](Run-PS (Join-Path $App 'start.ps1') @('-ForceUpdate'))
            Pause-Menu
        }
        '4' {
            [void](Run-PS (Join-Path $App 'prepare-home.ps1'))
            Pause-Menu
        }
        '5' {
            [void](Run-PS (Join-Path $App 'make-bundle.ps1'))
            Pause-Menu
        }
        '6' {
            $a = @(Ask-Clean)
            [void](Run-PS (Join-Path $App 'clean-traces.ps1') $a)
            Pause-Menu
        }
        '7' {
            [void](Run-PS (Join-Path $App 'self-check.ps1'))
            Pause-Menu
        }
        '8' {
            [void](Run-PS (Join-Path $App 'speed-up.ps1'))
            Pause-Menu
        }
        '9' {
            [void](Run-PS (Join-Path $App 'ip-check.ps1'))
            Pause-Menu
        }
        '10' {
            [void](Run-PS (Join-Path $App 'ping-servers.ps1'))
            Pause-Menu
        }
        '0' { break }
        '' { continue }
        default {
            Write-Host ''
            Write-Host '   Такого пункта нет. Есть 1–10 и 0. Справка: ?1 … ?10.' -ForegroundColor Red
            Start-Sleep -Milliseconds 1200
        }
    }
    if ($choice -eq '0') { break }
}

Clear-Host
Write-Host ''
Write-Host '  Меню закрыто. Если браузер ещё открыт — он работает; VPN закроется вместе с ним.' -ForegroundColor Cyan
Write-Host ''
