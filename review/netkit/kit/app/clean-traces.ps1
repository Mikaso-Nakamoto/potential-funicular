# clean-traces.ps1 — очистка следов использования LibreWolf-USB.
#   ЧИСТКА.bat          — стандартная очистка (права пользователя).
#   -Deep               — плюс Prefetch-файлы LIBREWOLF*/XRAY* (нужен запуск от имени
#                         администратора). Чужие счётчики cmd/powershell не трогаем.
#   -Scrub              — ДОПОЛНИТЕЛЬНО стереть весь профиль браузера на флешке
#                         (история, куки, кэш). config.json (ключ VPN) остаётся.
param(
    [switch]$Deep,
    [switch]$Scrub
)
$ErrorActionPreference = 'SilentlyContinue'
$App     = $PSScriptRoot
$Root    = Split-Path -Parent $App
$Vpn     = Join-Path $Root 'vpn'
$LogsDir = Join-Path $Vpn  'logs'
$Profile = Join-Path $Root 'profile'
$script:Removed = 0
$script:Skipped = 0
$Marker  = 'librewolf|xray|LibreWolf-USB'

function Rot13([string]$t) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $t.ToCharArray()) {
        $o = [int]$c
        if     ($o -ge 97  -and $o -le 122) { $o = ((($o - 97) + 13) % 26) + 97 }
        elseif ($o -ge 65  -and $o -le 90)  { $o = ((($o - 65) + 13) % 26) + 65 }
        [void]$sb.Append([char]$o)
    }
    return $sb.ToString()
}

Write-Host ""
Write-Host "=== LibreWolf-USB: ЧИСТКА СЛЕДОВ ===" -ForegroundColor Cyan
Write-Host "($([Environment]::UserName) @ $([Environment]::MachineName))" -ForegroundColor DarkGray
Write-Host ""

# --- 0. остановить процессы, если остались ---
foreach ($p in @(Get-Process -Name 'librewolf', 'firefox', 'xray' -ErrorAction SilentlyContinue)) {
    $path = ''
    try { $path = $p.Path } catch {}
    if ($path -and $path.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase)) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
}

# --- 0b. правила брандмауэра, добавленные kill-switch'ем (иначе он блокирует браузер навсегда) ---
$fw = 0
try {
    $rules = @(Get-NetFirewallRule -DisplayName 'LibreWolf-USB-KILLSWITCH*' -ErrorAction SilentlyContinue)
    if ($rules.Count -gt 0) {
        $rules | Remove-NetFirewallRule -ErrorAction SilentlyContinue
        $fw = $rules.Count
        $script:Removed += $fw
    }
} catch {}
Write-Host "[0] Правила брандмауэра kill-switch: снято — $fw" -ForegroundColor Green

# --- 1. флешка: логи сессий ---
$m = 0
if (Test-Path $LogsDir) {
    foreach ($f in @(Get-ChildItem $LogsDir -File)) {
        Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $f.FullName)) { $m++; $script:Removed++ }
    }
    Write-Host "[1] Логи сессий на флешке: удалено файлов — $m" -ForegroundColor Green
} else {
    Write-Host "[1] Логов на флешке нет" -ForegroundColor Green
}
if (Test-Path (Join-Path $Profile 'minidumps')) {
    Get-ChildItem (Join-Path $Profile 'minidumps') -Filter '*.dmp' | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem (Join-Path $Profile 'minidumps') -Filter '*.extra' | Remove-Item -Force -ErrorAction SilentlyContinue
}
if (Test-Path (Join-Path $Profile 'crashes')) {
    Get-ChildItem (Join-Path $Profile 'crashes') -File | Remove-Item -Force -ErrorAction SilentlyContinue
}

if ($Scrub) {
    if (Test-Path $Profile) {
        Get-ChildItem $Profile -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[1b] -Scrub: профиль браузера на флешке полностью стёрт (config.json цел)" -ForegroundColor Yellow
        $script:Removed++
    }
}

# --- 2. %TEMP% на ПК: папки/файлы с нашими именами ---
$m = 0
foreach ($h in @(Get-ChildItem $env:TEMP -Force | Where-Object { $_.Name -match $Marker })) {
    Remove-Item $h.FullName -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path $h.FullName)) { $m++; $script:Removed++ } else { $script:Skipped++ }
}
Write-Host ("[2] TEMP ({0}): удалено объектов — {1}" -f $env:TEMP, $m) -ForegroundColor Green

# --- 3. Prefetch: только наши exe, только в -Deep (нужен администратор) ---
# FIREFOX*.pf не трогаем: это может быть браузер другого человека на этой машине.
$pf = 0
if ($Deep) {
    foreach ($p in @('LIBREWOLF*.pf', 'XRAY*.pf')) {
        $hits = Get-ChildItem "$env:SystemRoot\Prefetch" -Filter $p -ErrorAction SilentlyContinue
        foreach ($f in $hits) {
            Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path $f.FullName)) { $pf++; $script:Removed++ } else { $script:Skipped++ }
        }
    }
    if ($pf -gt 0) { Write-Host "[3] Prefetch: удалено файлов — $pf" -ForegroundColor Green }
    else { Write-Host "[3] Prefetch: нет доступа/ничего нет (нужен запуск от администратора)" -ForegroundColor DarkGray }
} else {
    Write-Host "[3] Prefetch: пропущено (только с -Deep и правами администратора)" -ForegroundColor DarkGray
}

# --- 4. RunMRU (Win+R) ---
$m = 0
$runMru = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\RunMRU'
if (Test-Path $runMru) {
    $item = Get-Item $runMru
    foreach ($v in @($item.GetValueNames())) {
        $data = "$($item.GetValue($v))"
        if ($data -match $Marker) {
            $item.DeleteValue($v); $m++; $script:Removed++
        }
    }
}
Write-Host "[4] Win+R история: удалено записей — $m" -ForegroundColor Green

# --- 5. MuiCache (память имён запущенных программ) ---
$m = 0
$mui = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache'
if (Test-Path $mui) {
    $item = Get-Item $mui
    foreach ($v in @($item.GetValueNames())) {
        if ($v -match $Marker) {
            $item.DeleteValue($v); $m++; $script:Removed++
        }
    }
}
Write-Host "[5] MuiCache: удалено записей — $m" -ForegroundColor Green

# --- 6. UserAssist (ROT13-журнал запуска программ) ---
$m = 0
$uaRoot = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\UserAssist'
Get-ChildItem $uaRoot -ErrorAction SilentlyContinue | ForEach-Object {
    $countKey = Join-Path $_.PSPath 'Count'
    if (Test-Path $countKey) {
        $item = Get-Item $countKey
        foreach ($v in @($item.GetValueNames())) {
            $dec = Rot13 $v
            # только наши записи: чужие счётчики (в т.ч. cmd/powershell других людей) не трогаем
            if ($dec -match $Marker) {
                $item.DeleteValue($v); $m++; $script:Removed++
            }
        }
    }
}
Write-Host ("[6] UserAssist: удалено записей — {0} (только наши; чужие счётчики не трогаем)" -f $m) -ForegroundColor Green

# --- 7. отчёты об ошибках (WER) ---
$m = 0
foreach ($sub in @('ReportArchive', 'ReportQueue')) {
    $wer = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\WER\$sub"
    if (Test-Path $wer) {
        Get-ChildItem $wer -Directory | Where-Object { $_.Name -match $Marker } | ForEach-Object {
            if (Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue) {}
            if (-not (Test-Path $_.FullName)) { $m++; $script:Removed++ } else { $script:Skipped++ }
        }
    }
}
Write-Host "[7] Отчёты об ошибках (WER): удалено — $m" -ForegroundColor Green

# --- 8. история команд PowerShell (PSReadLine) ---
$h = Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt'
if (Test-Path $h) {
    $lines = [IO.File]::ReadAllLines($h)
    $keep  = @($lines | Where-Object { $_ -notmatch $Marker -and $_ -notmatch '(?i)vless://|start\.ps1|clean-traces|prepare-home' })
    if ($null -eq $keep) { $keep = @() }
    if ($keep.Count -ne $lines.Count) {
        [IO.File]::WriteAllLines($h, $keep)
        Write-Host ("[8] История PowerShell: удалено строк — {0}" -f ($lines.Count - $keep.Count)) -ForegroundColor Green
        $script:Removed++
    } else {
        Write-Host "[8] История PowerShell: наших строк нет" -ForegroundColor Green
    }
} else {
    Write-Host "[8] История PowerShell: файла нет" -ForegroundColor Green
}

# --- 9. кэш DNS (от администратора сработает тихо, без прав — просто нет) ---
$null = & ipconfig.exe /flushdns 2>$null
Write-Host "[9] Кэш DNS: сброшен (если хватило прав)" -ForegroundColor Green

Write-Host ""
Write-Host "=== Итог: удалено объектов — $script:Removed, пропущено (нет прав) — $script:Skipped ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "ЧТО ОСТАЁТСЯ (честно, без иллюзий):" -ForegroundColor Yellow
Write-Host " - Пользовательские: MountPoints2 (факт подключения ЭТОЙ флешки), списки недавних"
Write-Host "   документов, если открывали что-то с флешки в проводнике/блокноте."
Write-Host " - Для администратора домена: Amcache и BAM/DAM (какие exe запускались и когда),"
Write-Host "   SRUM (сетевой трафик по процессам), журнал событий (4688 — запуск процесса;"
Write-Host "   4104 — ПОЛНЫЙ ТЕКСТ запущенного скрипта), история Windows Defender."
Write-Host " - Prefetch для CMD.EXE и POWERSHELL.EXE: видно, что с флешки что-то запускали."
Write-Host " - На машине с включённым аудитом содержимое start.ps1 остаётся в журнале, и убрать"
Write-Host "   это без прав администратора нельзя. Комплект этого и не обещает."
Write-Host " - БЕЗ -Deep: Prefetch LIBREWOLF*/XRAY* мог остаться — запусти чистку от администратора:"
Write-Host '     powershell -ExecutionPolicy Bypass -File "<буква флешки>:\LibreWolf-USB\app\clean-traces.ps1" -Deep'
if (-not $Scrub) {
    Write-Host " - Профиль (история/куки) хранится на флешке и НЕ стёрт. Полное стирание: ЧИСТКА с -Scrub."
}
Write-Host ""
exit 0
