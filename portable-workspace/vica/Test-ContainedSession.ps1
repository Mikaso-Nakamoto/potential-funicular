#requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Bootstrap.Common.ps1')
Assert-VicaPlatform
. (Join-Path $PSScriptRoot 'Native.Common.ps1')
$stage = Join-Path $PSScriptRoot ('.contained-test-' + [Guid]::NewGuid().ToString('N'))
$oldTemp = $env:TEMP; $oldTmp = $env:TMP; $oldKeyLog = $env:SSLKEYLOGFILE
$owner = $null; $supervisor = $null; $payload = $null; $owned = $false; $safe = $false
function Wait-Marker([string]$Path) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path -LiteralPath $Path) -and $timer.Elapsed.TotalSeconds -lt 15) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath $Path)) { throw 'Fixture readiness deadline.' }
}
function New-Case([string]$Mode) {
    $dir = Join-Path $stage $Mode
    New-Item -ItemType Directory -Path $dir -ErrorAction Stop | Out-Null
    Copy-Item -LiteralPath $fixture -Destination (Join-Path $dir 'fixture.exe')
    [IO.File]::WriteAllText((Join-Path $dir 'mode.txt'),$Mode)
    return $dir
}
try {
    New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null; $owned = $true
    $env:TEMP = $stage; $env:TMP = $stage
    Initialize-VicaNative
    $fixture = Join-Path $stage 'fixture.exe'
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ContainmentFixture.cs'))) -OutputAssembly $fixture -OutputType ConsoleApplication -ErrorAction Stop
    $payload = [Text.Encoding]::UTF8.GetBytes('TEST_ONLY')
    foreach ($mode in @('valid','reject','hang')) {
        $dir = New-Case $mode
        $owner = [VicaContained.Session]::Open((Join-Path $dir 'fixture.exe'),$dir,'test')
        $failed = $false
        try { $owner.Validate($payload,1000) } catch { $failed = $true }
        if (($mode -eq 'valid' -and $failed) -or ($mode -ne 'valid' -and -not $failed)) { throw 'Unexpected validation outcome.' }
        Stop-VicaNative $owner; $owner = $null
        Write-Host ('PASS: contained ' + $mode)
    }
    $dir = New-Case 'blocked'
    $owner = [VicaContained.Session]::Open((Join-Path $dir 'fixture.exe'),$dir,'test')
    Wait-Marker (Join-Path $dir 'ready.txt')
    $large = New-Object byte[] 8388608; $failed = $false
    try { $owner.Send($large,200) } catch { $failed = $true } finally { [Array]::Clear($large,0,$large.Length) }
    if (-not $failed) { throw 'Blocked stdin unexpectedly succeeded.' }
    Stop-VicaNative $owner; $owner = $null
    Write-Host 'PASS: bounded blocked stdin'
    $dir = New-Case 'flood'
    $owner = [VicaContained.Session]::Open((Join-Path $dir 'fixture.exe'),$dir,'test')
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while (-not $owner.HasFailed -and $timer.Elapsed.TotalSeconds -lt 15) { Start-Sleep -Milliseconds 100 }
    if (-not $owner.HasFailed) { throw 'Output limit failed.' }
    Stop-VicaNative $owner; $owner = $null
    Write-Host 'PASS: bounded discarded stderr'
    $dir = New-Case 'curl'; $env:SSLKEYLOGFILE = Join-Path $dir 'must-not-exist.log'
    $owner = [VicaContained.Session]::Open((Join-Path $dir 'fixture.exe'),$dir,'curl')
    $response = $owner.Fetch($payload)
    if ([Text.Encoding]::UTF8.GetString($response) -cne 'TEST_RESPONSE') { throw 'Captured stdout mismatch.' }
    Stop-VicaNative $owner; $owner = $null
    Write-Host 'PASS: curl mode, raw stdin, isolated stdout and key-log environment removed'
    $dir = New-Case 'tree'
    $owner = [VicaContained.Session]::Open((Join-Path $dir 'fixture.exe'),$dir,'run')
    $owner.Send($payload,5000)
    Wait-Marker (Join-Path $dir 'descendant.pid')
    Stop-VicaNative $owner; $owner = $null
    # Accounted active-process count must be zero, including the descendant, before cleanup confirms.
    Write-Host 'PASS: explicit whole-job cleanup'
    Remove-Item -LiteralPath (Join-Path $dir 'descendant.pid'),(Join-Path $dir 'ready.txt'),(Join-Path $dir 'fixture.pid')
    $scriptPath = Join-Path $stage 'supervise.ps1'
    $body = @'
param([string]$Tools,[string]$CaseDir)
$ErrorActionPreference = 'Stop'
. (Join-Path $Tools 'Native.Common.ps1')
Initialize-VicaNative
$session = [VicaContained.Session]::Open((Join-Path $CaseDir 'fixture.exe'),$CaseDir,'run')
$session.Send([Text.Encoding]::UTF8.GetBytes('TEST_ONLY'),5000)
while ($true) { Start-Sleep -Seconds 1 }
'@
    [IO.File]::WriteAllText($scriptPath,$body)
    $arguments = '-NoProfile -ExecutionPolicy RemoteSigned -File "' + $scriptPath + '" -Tools "' + $PSScriptRoot + '" -CaseDir "' + $dir + '"'
    $supervisor = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -PassThru -WindowStyle Hidden
    Wait-Marker (Join-Path $dir 'descendant.pid')
    $childId = [int][IO.File]::ReadAllText((Join-Path $dir 'fixture.pid'))
    $descendantId = [int][IO.File]::ReadAllText((Join-Path $dir 'descendant.pid'))
    $child = Get-Process -Id $childId -ErrorAction Stop
    $descendant = Get-Process -Id $descendantId -ErrorAction Stop
    try {
        $supervisor.Kill()
        if (-not $supervisor.WaitForExit(10000) -or -not $child.WaitForExit(10000) -or -not $descendant.WaitForExit(10000)) { throw 'Forced owner exit left a fixture alive.' }
    } finally { $child.Dispose(); $descendant.Dispose() }
    $supervisor.Dispose(); $supervisor = $null
    Write-Host 'PASS: forced supervisor exit kills job tree'
    $safe = $true
    Write-Host 'PASS: containment self-check complete. No real Runtime, network or browser used.'
} finally {
    Stop-VicaNative $owner
    if ($supervisor) { try { if (-not $supervisor.HasExited) { $supervisor.Kill(); $null = $supervisor.WaitForExit(10000) } } finally { $supervisor.Dispose() } }
    if ($payload) { [Array]::Clear($payload,0,$payload.Length) }
    $env:TEMP = $oldTemp; $env:TMP = $oldTmp; $env:SSLKEYLOGFILE = $oldKeyLog
    if ($owned) {
        # If inspection is uncertain or a fixture remains, retain evidence/stage instead of deleting executable paths.
        $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'fixture.exe'" -ErrorAction Stop)
        foreach ($process in $processes) { if (-not $process.ExecutablePath -or $process.ExecutablePath.StartsWith($stage,[StringComparison]::OrdinalIgnoreCase)) { $safe = $false } }
        if ($safe) { Remove-Item -LiteralPath $stage -Recurse -Force }
        else { Write-Warning ('Self-check stage retained: ' + $stage) }
    }
}
