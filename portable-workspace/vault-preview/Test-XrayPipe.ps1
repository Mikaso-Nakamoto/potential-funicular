#requires -Version 5.1
[CmdletBinding()]
param([string]$XrayExe = '')
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Use 64-bit Windows PowerShell 5.1.' }
. (Join-Path $PSScriptRoot 'XrayPipe.Common.ps1')
$stage = Join-Path $PSScriptRoot ('.pipe-tests-' + [Guid]::NewGuid().ToString('N'))
$owned = $false; $session = $null; $payload = $null
$oldTemp = $env:TEMP; $oldTmp = $env:TMP
$report = Join-Path $PSScriptRoot 'xray-pipe-test-report.txt'
$log = New-Object 'Collections.Generic.List[string]'
function Note([string]$Text) { Write-Host $Text; $log.Add($Text) }
function New-Case([string]$Name) {
    $dir = Join-Path $stage $Name
    New-Item -ItemType Directory -Path $dir | Out-Null
    Copy-Item -LiteralPath $fixture -Destination (Join-Path $dir 'fixture.exe')
    [IO.File]::WriteAllText((Join-Path $dir 'mode.txt'), $Name)
    return (Join-Path $dir 'fixture.exe')
}
function Assert-ChildExited([string]$Exe, [int]$ExpectedPid = 0) {
    $pidPath = Join-Path (Split-Path -Parent $Exe) 'pid.txt'
    if (-not (Test-Path -LiteralPath $pidPath)) { throw 'Fixture PID marker missing; scenario completion is not established.' }
    $childId = [int][IO.File]::ReadAllText($pidPath)
    if ($ExpectedPid -ne 0 -and $childId -ne $ExpectedPid) { throw 'Fixture marker does not match the started process.' }
    $child = Get-Process -Id $childId -ErrorAction SilentlyContinue
    if ($child) {
        try { if (-not $child.WaitForExit(1000)) { throw 'Fixture child still running after cleanup.' } }
        finally { $child.Dispose() }
    }
}
function Wait-BlockedFixtureReady($Child, [string]$Exe) {
    $directory = Split-Path -Parent $Exe
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while ($watch.ElapsedMilliseconds -lt 15000) {
        if ($Child.HasExited) { throw 'Blocked-input fixture exited before readiness; stdin timeout was not tested.' }
        $pidMarker = Join-Path $directory 'pid.txt'
        $readyMarker = Join-Path $directory 'blocked-ready.txt'
        if ((Test-Path -LiteralPath $pidMarker) -and (Test-Path -LiteralPath $readyMarker)) {
            try {
                $markedPid = 0; $readyPid = 0
                $hasPid = [int]::TryParse([IO.File]::ReadAllText($pidMarker), [ref]$markedPid)
                $hasReady = [int]::TryParse([IO.File]::ReadAllText($readyMarker), [ref]$readyPid)
                if ($hasPid -and $hasReady -and $markedPid -eq $Child.Id -and $readyPid -eq $Child.Id) {
                    Note ('READY: no-read fixture branch and both PID markers confirmed before input; startup ms=' + $watch.ElapsedMilliseconds)
                    return
                }
            } catch [IO.IOException] { } # marker still being written; do not infer readiness
        }
        Start-Sleep -Milliseconds 50
    }
    throw 'Blocked-input fixture did not signal readiness in 15 seconds; no stdin timeout PASS is claimed.'
}
function Must-Reject([string]$Name, [scriptblock]$Action, [string]$ExpectedReason = '') {
    $rejected = $false; $watch = [Diagnostics.Stopwatch]::StartNew()
    try { $null = & $Action } catch {
        $rejected = $true
        $e = $_.Exception
        $reasonMatched = -not $ExpectedReason
        while ($e) {
            if ($e.Message.Contains('VIC-A-PIPE-SYNTHETIC-SECRET-DO-NOT-PRINT')) { throw 'Child output leaked into an exception.' }
            if ($ExpectedReason -and $e.Message.Contains($ExpectedReason)) { $reasonMatched = $true }
            $e = $e.InnerException
        }
        if (-not $reasonMatched) { throw ('Wrong failure category: ' + $Name) }
    }
    if (-not $rejected) { throw ('Expected failure: ' + $Name) }
    if ($watch.ElapsedMilliseconds -gt 25000) { throw ('Deadline regression: ' + $Name) }
}
try {
    New-Item -ItemType Directory -Path $stage | Out-Null
    $owned = $true; $env:TEMP = $stage; $env:TMP = $stage
    Note ('Xray stdin transport tests R2 (readiness handshake); PS ' + $PSVersionTable.PSVersion + '; CLR ' + [Environment]::Version)
    foreach ($name in @('XrayPipe.cs','XrayPipe.Common.ps1','Test-XrayPipe.ps1','tests\XrayPipeFixture.cs')) {
        Note ('SHA256 ' + (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name) -Algorithm SHA256).Hash + '  ' + $name)
    }
    Note ('SHA256 ' + (Get-FileHash -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'Workspace.Common.ps1') -Algorithm SHA256).Hash + '  ../Workspace.Common.ps1')
    Initialize-XrayPipe
    $fixture = Join-Path $stage 'fixture.exe'
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'tests\XrayPipeFixture.cs'))) -OutputAssembly $fixture -OutputType ConsoleApplication -ErrorAction Stop
    $outbound = Convert-Vless 'vless://12345678-1234-4234-8234-123456789abc@example.invalid:443?security=tls&type=tcp&sni=example.invalid&fp=chrome'
    $config = @{
        log = @{ loglevel = 'none' }
        inbounds = @(@{ listen = '127.0.0.1'; port = 17890; protocol = 'socks'; settings = @{ auth = 'noauth'; udp = $false } })
        outbounds = @($outbound)
    } | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $payload = [Text.Encoding]::UTF8.GetBytes(($config | ConvertTo-Json -Depth 30 -Compress))
    $exe = New-Case 'ok'
    Test-XrayObjectInMemory $exe $config 5000
    Assert-ChildExited $exe
    Note 'PASS: exact Xray argument shape, UTF-8 JSON stdin, EOF and zero-exit validation; no child output published'
    foreach ($mode in @('reject','hang-after-input','stderr-flood','stdout-flood')) {
        $exe = New-Case $mode
        if ($mode -in @('stderr-flood','stdout-flood')) {
            Must-Reject $mode { [VicAXrayPipe.Session]::Validate($exe, (Split-Path -Parent $exe), $payload, 3000) } 'Xray output limit exceeded.'
        } else { Must-Reject $mode { Test-XrayObjectInMemory $exe $config 3000 } }
        Assert-ChildExited $exe
        Note ('PASS: ' + $mode + '; child exit confirmed')
    }
    $exe = New-Case 'blocked-input'
    $large = New-Object byte[] 4194304
    try {
        # Start child and drains first. Do not start the writer deadline until fixture is ready.
        $session = [VicAXrayPipe.Session]::BeginValidation($exe, (Split-Path -Parent $exe))
        $blockedPid = $session.Id
        Note ('STARTED: blocked-input fixture; PID=' + $blockedPid + '; input not sent yet')
        Wait-BlockedFixtureReady $session $exe
        Must-Reject 'blocked stdin writer' { $session.SendAndValidate($large, 3000) } 'Xray stdin input timed out.'
        if (-not $session.CleanupConfirmed) { throw 'Blocked-input cleanup was not confirmed.' }
        Assert-ChildExited $exe $blockedPid
        Note 'PASS: blocked stdin writer timeout AFTER readiness; exact child exit and cleanup confirmed'
    } finally {
        if ($session) { $session.Dispose(); $session = $null }
        [Array]::Clear($large, 0, $large.Length)
    }
    $exe = New-Case 'serve'
    $session = Start-XrayObjectInMemory $exe $config 5000
    if ($session.HasExited -or $session.HasFailed) { throw 'Live-session fixture failed.' }
    $session.Dispose()
    if (-not $session.CleanupConfirmed) { throw 'Live-session cleanup was not confirmed.' }
    $session = $null
    Assert-ChildExited $exe
    Note 'PASS: live child session is retained then stopped/disposed with confirmed cleanup'
    $invalid = $config | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $invalid.inbounds[0].listen = '0.0.0.0'
    $exe = New-Case 'policy-reject'
    Must-Reject 'unsafe config rejected before child start' { Test-XrayObjectInMemory $exe $invalid 3000 }
    if (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $exe) 'pid.txt')) { throw 'Unsafe configuration started a child.' }
    Note 'PASS: unsafe config rejected before child start'
    if ($XrayExe) {
        $actual = [IO.Path]::GetFullPath($XrayExe)
        Note ('ACTUAL XRAY SHA256 ' + (Get-FileHash -LiteralPath $actual -Algorithm SHA256).Hash)
        Test-XrayObjectInMemory $actual $config 30000
        Note 'PASS: supplied real Xray accepted synthetic TLS config through stdin in -test mode; no network/listener test'
    } else { Note 'NOT RUN: actual Xray validation. Fixture tests do not establish compatibility with the real binary.' }
    Note 'RESULT: PASS for implemented tests only. Production launcher/updater unchanged; no migration.'
} catch {
    Note ('RESULT: FAIL: ' + $_.Exception.Message)
    throw
} finally {
    if ($session) { $session.Dispose() }
    if ($payload) { [Array]::Clear($payload, 0, $payload.Length) }
    $env:TEMP = $oldTemp; $env:TMP = $oldTmp
    [IO.File]::WriteAllLines($report, $log.ToArray(), (New-Object Text.UTF8Encoding($true)))
    if ($owned) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
