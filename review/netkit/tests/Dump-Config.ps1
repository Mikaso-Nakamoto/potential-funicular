# Dump-Config.ps1 — прогоняет конвертер комплекта на готовом теле подписки и печатает конфиг.
# Нужен для сверки PowerShell-версии с Python-версией (update-sub.py) на одних и тех же данных.
# Сеть не используется: тело подписки читается из файла.
#
#   pwsh -File tests\Dump-Config.ps1 -Body tests\fixtures\sub-body.txt -Out /tmp/ps-config.json

param(
    [Parameter(Mandatory = $true)][string]$Body,
    [string]$Out = ''
)

$ErrorActionPreference = 'Stop'
$lib = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'inbox\LibreWolf-USB\app\vless-lib.ps1'
if (-not (Test-Path $lib)) {
    # запасной путь: тесты лежат рядом с комплектом
    $lib = Join-Path (Split-Path -Parent $PSScriptRoot) 'inbox/LibreWolf-USB/app/vless-lib.ps1'
}
if (-not (Test-Path $lib)) { throw "не найден vless-lib.ps1: $lib" }
. $lib

$text = Get-Content -Path $Body -Raw -Encoding UTF8
$nodes = @(ConvertTo-Nodes $text)
if ($nodes.Count -eq 0) { throw "конвертер не разобрал ни одной ссылки из $Body" }

$json = New-ConfigJson $nodes
# самопроверка: то, что собрали, обязано парситься обратно
$parsed = $json | ConvertFrom-Json
if ($null -eq $parsed) { throw 'собранный конфиг не парсится обратно' }

Write-Host ("узлов: {0}, outbound: {1}, длина JSON: {2}" -f $nodes.Count, @($parsed.outbounds).Count, $json.Length)
if ($Out) {
    [IO.File]::WriteAllText($Out, $json, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "записано: $Out"
} else {
    Write-Output $json
}
