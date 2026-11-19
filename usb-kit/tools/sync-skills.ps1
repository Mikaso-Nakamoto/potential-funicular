#requires -version 5
<# Копирует категории маркдаун-скиллов из ..\agent-skills (или $env:SKILLS_SRC) в config\skills.
   Категории — аргументы; по умолчанию набор для сетевой безопасности и крипто. #>
$ErrorActionPreference = 'Stop'
$ROOT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

if ($env:SKILLS_SRC) { $SRC = $env:SKILLS_SRC } else { $SRC = Join-Path (Split-Path -Parent $ROOT) 'agent-skills' }
$DST = Join-Path $ROOT 'config\skills'

if (-not (Test-Path $SRC)) {
  Write-Warning "agent-skills не найден ($SRC) — пропускаю синк маркдаун-скиллов."
  Write-Warning "Укажите SKILLS_SRC=\путь\к\agent-skills, если они лежат отдельно."
  exit 0
}
New-Item -ItemType Directory -Force $DST | Out-Null

$DEFAULT = @('network-security', 'security-crypto', 'crypto-engineering', 'ai-integration')
$CATS = @($args); if ($CATS.Count -eq 0 -or ($CATS.Count -eq 1 -and -not $CATS[0])) { $CATS = $DEFAULT }

foreach ($cat in $CATS) {
  $from = Join-Path $SRC $cat
  if (Test-Path $from) {
    Copy-Item -Recurse -Force $from $DST
    $n = @(Get-ChildItem -Recurse (Join-Path $DST $cat) -Filter SKILL.md).Count
    Write-Host "  + $cat ($n скиллов)"
  } else {
    Write-Warning "  ? категория не найдена: $cat"
  }
}
Write-Host "Назначение: $DST  (Pi подхватит при старте или /reload)"
