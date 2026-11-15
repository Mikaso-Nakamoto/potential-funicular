# vless-to-config.ps1 — конвертер vless:// ссылок в конфиг Xray (мульти-серверный).
# ЗАПУСКАТЬ ДОМА! Ссылки вставляются в консоль здесь же (Read-Host),
# на колледжной машине не появляются нигде.
# Результат: vpn\config.json на флешке (+ бэкап старого в config.bak.json).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'vless-lib.ps1')

$Vpn = Join-Path (Split-Path -Parent $PSScriptRoot) 'vpn'
$OutFile = Join-Path $Vpn 'config.json'

Write-Host ""
Write-Host "=== VLESS -> Xray config (мульти-серверный) ===" -ForegroundColor Cyan
Write-Host "Вставляй ссылки по ОДНОЙ (правая кнопка мыши), после каждой — Enter." -ForegroundColor DarkGray
Write-Host "Пустая строка (просто Enter) — закончить и записать конфиг." -ForegroundColor DarkGray
Write-Host ""

$nodes = @()
$seen = @{}
while ($true) {
    $line = Read-Host "vless:// ссылка №$($nodes.Count + 1) (Enter — закончить)"
    $t = "$line".Trim()
    if (-not $t) { break }
    $n = ConvertFrom-VlessLink $t
    if ($n) {
        $key = "$($n.uuid)|$($n.address)|$($n.port)"
        if ($seen.ContainsKey($key)) { Write-Host "[i] дубликат, пропущен" -ForegroundColor DarkGray; continue }
        $seen[$key] = $true
        $nodes += $n
        Write-Host "[+] proxy-$($nodes.Count): $($n.address):$($n.port) ($($n.net)/$($n.sec))$(if ($n.sni) { ' sni=' + $n.sni })" -ForegroundColor Green
    }
}
if ($nodes.Count -eq 0) {
    Write-Host "[!] Не введено ни одной ссылки — конфиг не меняю." -ForegroundColor Red
    exit 1
}

$json = New-ConfigJson $nodes

New-Item -ItemType Directory -Force -Path $Vpn | Out-Null
if (Test-Path $OutFile) {
    Copy-Item $OutFile ($OutFile + '.bak.json') -Force
    Write-Host "[i] Старый конфиг сохранён как config.bak.json" -ForegroundColor DarkGray
}
[System.IO.File]::WriteAllText($OutFile, $json, (New-Object System.Text.UTF8Encoding $false))

Write-Host ""
Write-Host "[+] Записано: $OutFile" -ForegroundColor Green
Write-Host "[i] Серверов: $($nodes.Count). Всё идёт через балансировщик leastPing —"
Write-Host "    если один сервер умрёт, Xray сам переключит на живой."
Write-Host "[i] Этот файл на колледжном ПК не открывать и нигде не копировать."
