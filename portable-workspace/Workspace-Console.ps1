#requires -Version 5.1
[CmdletBinding()]
param([switch]$NoSplash)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$homeDir = $PSScriptRoot
if (-not $homeDir) { $homeDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$runtimeDir = Join-Path $homeDir 'Runtime'
. (Join-Path $homeDir 'Workspace.Common.ps1')
$supervisor = $null
$openedAt = Get-Date
$cachedStamp = ''; $cachedPolicy = 'NOT CHECKED'
$interactive = $false
try { $interactive = -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected } catch { }
function Row([string]$Text = '', [string]$Color = 'Gray') { return @{ Text = $Text; Color = $Color } }
function Paint($Rows) {
    if (-not $interactive) { foreach ($r in $Rows) { Write-Host $r.Text -ForegroundColor $r.Color }; return }
    $width = [Math]::Max(1, [Math]::Min(92, [Console]::WindowWidth - 1))
    $height = [Math]::Max(1, [Console]::WindowHeight - 1)
    if ($Rows.Count -gt $height) {
        # A compact dashboard keeps controls visible in the classic 25-row console.
        # Eye frames are handled separately by Show-Eye's minimum-size check.
        if ($Rows.Count -eq 28) { $Rows = @($Rows[0,1,7,8,9,11,14,17,18,19,20,21,22,23,25,26]) }
    }
    [Console]::SetCursorPosition(0, 0)
    for ($i = 0; $i -lt [Math]::Min($Rows.Count, $height); $i++) {
        $text = $Rows[$i].Text
        if ($text.Length -gt $width) { $text = $text.Substring(0, $width) }
        Write-Host $text.PadRight($width) -ForegroundColor $Rows[$i].Color
    }
}
function Show-Eye {
    if (-not $interactive) { Write-Host 'IRIS / Portable Workspace'; return }
    Clear-Host
    try {
        . (Join-Path $homeDir 'Iris.Intro.ps1')
        Show-IrisIntro
    } catch {
        # A decorative failure must never block access to the working menu.
        Write-Host 'IRIS / Intro unavailable in this console. Opening menu.' -ForegroundColor DarkGray
        Start-Sleep -Milliseconds 400
    }
}
function Get-LocalStatus {
    $exe = Join-Path $runtimeDir 'Xray\xray.exe'
    $browserRoot = Join-Path $runtimeDir 'LibreWolf'
    $configPath = Join-Path $runtimeDir 'private\xray.json'
    $browserFiles = @(); if (Test-Path -LiteralPath $browserRoot) { $browserFiles = @(Get-ChildItem -LiteralPath $browserRoot -Filter librewolf.exe -Recurse -File -ErrorAction SilentlyContinue) }
    $config = Get-Item -LiteralPath $configPath -ErrorAction SilentlyContinue
    $stamp = 'missing'
    if ($config) { $stamp = $config.LastWriteTimeUtc.Ticks.ToString() + ':' + $config.Length }
    if ($stamp -ne $script:cachedStamp) {
        $script:cachedStamp = $stamp
        $script:cachedPolicy = 'MISSING'
        if ($config) {
            try { Assert-ConfigPolicy $configPath; $script:cachedPolicy = 'PASS (local policy only)' }
            catch { $script:cachedPolicy = 'FAIL - regenerate configuration' }
        }
    }
    $xrayProcesses = @(); $browserProcesses = @(); $processKnown = $true
    try {
        $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'xray.exe' OR Name = 'librewolf.exe'" -ErrorAction Stop)
        foreach ($process in $processes) {
            if (-not $process.ExecutablePath) { $processKnown = $false; continue }
            if ($process.ExecutablePath -eq $exe) { $xrayProcesses += $process }
            if ($browserFiles.Count -eq 1 -and $process.ExecutablePath -eq $browserFiles[0].FullName) { $browserProcesses += $process }
        }
    } catch { $processKnown = $false }
    $port = 'IDLE / not listening'; $portColor = 'DarkGray'
    try {
        $listeners = @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object { $_.LocalPort -eq 17890 })
        if ($listeners.Count -gt 0) {
            $valid = @($listeners | Where-Object { $_.LocalAddress -eq '127.0.0.1' -and $_.OwningProcess -in @($xrayProcesses | ForEach-Object { $_.ProcessId }) })
            if ($valid.Count -eq $listeners.Count -and $processKnown) { $port = 'READY / owner matches this Xray'; $portColor = 'Green' }
            else { $port = 'WARNING / owner or binding not verified'; $portColor = 'Yellow' }
        }
    } catch { $port = 'UNKNOWN / listener inspection unavailable'; $portColor = 'Yellow' }
    $memory = 0.0
    foreach ($p in @($xrayProcesses) + @($browserProcesses)) { $memory += [double]$p.WorkingSetSize }
    $memoryText = ('{0:N0} MiB (matching processes)' -f ($memory / 1048576))
    if (-not $processKnown) { $memoryText += ' / partial or unknown' }
    $space = 'UNKNOWN'
    try {
        $drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($runtimeDir))
        $space = '{0:N1} GiB free / {1:N1} GiB' -f ($drive.AvailableFreeSpace / 1073741824), ($drive.TotalSize / 1073741824)
    } catch { }
    $updated = 'not saved'; if ($config) { $updated = $config.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') }
    return @{
        Xray = (Test-Path -LiteralPath $exe); Browser = ($browserFiles.Count -eq 1)
        Policy = $script:cachedPolicy; Port = $port; PortColor = $portColor
        Processes = ('Xray: {0} / LibreWolf: {1}' -f $xrayProcesses.Count, $browserProcesses.Count)
        Memory = $memoryText; Space = $space; Updated = $updated
    }
}
function Start-ManagedWindow {
    if ($script:supervisor -and -not $script:supervisor.HasExited) { throw 'The session window is already open. Close LibreWolf normally first.' }
    $path = Join-Path $homeDir 'Start-Workspace.ps1'
    $script:supervisor = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','RemoteSigned','-File', ('"' + $path + '"'), '-Root', ('"' + $runtimeDir + '"')) -WorkingDirectory $homeDir -PassThru
}
function Request-BrowserClose {
    $profileDir = Join-Path $runtimeDir 'private\profile'
    $binaries = @(Get-ChildItem -LiteralPath (Join-Path $runtimeDir 'LibreWolf') -Filter librewolf.exe -Recurse -File -ErrorAction Stop)
    if ($binaries.Count -ne 1) { throw 'Cannot identify this LibreWolf installation.' }
    $profilePattern = '(?i)(?:^|\s)-profile\s+(?:"' + [regex]::Escape($profileDir) + '"|' + [regex]::Escape($profileDir) + ')(?:\s|$)'
    $matches = @(Get-CimInstance Win32_Process -Filter "Name = 'librewolf.exe'" -ErrorAction Stop | Where-Object {
        $_.ExecutablePath -eq $binaries[0].FullName -and $_.CommandLine -and $_.CommandLine -match $profilePattern
    })
    $sent = 0
    foreach ($match in $matches) {
        try {
            $p = Get-Process -Id $match.ProcessId -ErrorAction Stop
            if ($p.MainWindowHandle -ne 0 -and $p.Path -eq $binaries[0].FullName -and $p.CloseMainWindow()) { $sent++ }
        } catch { }
    }
    if ($sent -eq 0) { Write-Host 'No identifiable main window found. Close LibreWolf yourself; no process was killed.' -ForegroundColor Yellow }
    else { Write-Host 'Normal window-close requested. Handle browser prompts and wait for the session window to finish.' -ForegroundColor Cyan }
}
$oldTitle = ''; $oldCursor = $true
try {
    if ($interactive) { $oldTitle = [Console]::Title; $oldCursor = [Console]::CursorVisible; [Console]::Title = 'IRIS | Portable Workspace'; [Console]::CursorVisible = $false }
    if (-not $NoSplash) { Show-Eye }
    Clear-Host
    $done = $false
    while (-not $done) {
        $s = Get-LocalStatus
        $age = (Get-Date) - $openedAt
        $rows = @(
            (Row '  I R I S   /   CONTROL ROOM' Cyan),
            (Row '  ---------------------------------------------------------------------' DarkCyan),
            (Row ('  {0}    |    Console uptime {1:hh\:mm\:ss}' -f (Get-Date -Format 'HH:mm:ss'), $age) DarkGray),
            (Row ''),
            (Row '  LOCAL HEALTH                                           LIVE / 2 SEC' White),
            (Row ('  Xray files      : ' + $(if ($s.Xray) { 'FOUND' } else { 'MISSING' })) Gray),
            (Row ('  LibreWolf files : ' + $(if ($s.Browser) { 'FOUND' } else { 'MISSING / AMBIGUOUS' })) Gray),
            (Row ('  Config policy   : ' + $s.Policy) $(if ($s.Policy.StartsWith('PASS')) { 'Green' } else { 'Yellow' })),
            (Row ('  SOCKS :17890    : ' + $s.Port) $s.PortColor),
            (Row ('  Processes       : ' + $s.Processes) Gray),
            (Row ('  Memory          : ' + $s.Memory) Gray),
            (Row ('  SSD             : ' + $s.Space) Gray),
            (Row ('  Config saved    : ' + $s.Updated) DarkGray),
            (Row ''),
            (Row '  REMOTE IP / DNS / LEAKS : NOT TESTED BY THIS DASHBOARD' Yellow),
            (Row '  Local listener readiness is NOT proof of a private connection.' DarkGray),
            (Row ''),
            (Row '  [1] Launch browser + tunnel (separate session window)' Cyan),
            (Row '  [2] Request normal browser close (no forced termination)' Gray),
            (Row '  [3] Update subscription + existing device UUID / choose node' Gray),
            (Row '  [4] Open downloads folder' Gray),
            (Row '  [5] Offline tests (synthetic inputs only)' Gray),
            (Row '  [6] Replay cinematic intro' Magenta),
            (Row '  [0] Exit dashboard (does NOT stop the separate session)' Gray),
            (Row ''),
            (Row '  Close LibreWolf, then its session window, before unplugging SSD.' DarkGray),
            (Row '  Keep session window open. Forced shell exit is not safe cleanup.' Yellow),
            (Row '  ---------------------------------------------------------------------' DarkCyan)
        )
        Paint $rows
        $choice = $null
        if ($interactive) {
            for ($tick = 0; $tick -lt 20; $tick++) {
                if ([Console]::KeyAvailable) { $choice = [Console]::ReadKey($true).KeyChar.ToString(); break }
                Start-Sleep -Milliseconds 100
            }
        } else { $choice = Read-Host 'Option' }
        if ($choice -notin @('0','1','2','3','4','5','6')) { continue }
        if ($interactive) { [Console]::CursorVisible = $true }
        Clear-Host
        try {
            switch ($choice) {
                '0' { $done = $true }
                '1' { Start-ManagedWindow; Write-Host 'Session window opened. It owns the browser/tunnel lifecycle.' }
                '2' { Request-BrowserClose }
                '3' { & (Join-Path $homeDir 'Update-Subscription.ps1') -Root $runtimeDir -UseDeviceHwid; $script:cachedStamp = '' }
                '4' {
                    $folder = Join-Path $runtimeDir 'private\downloads'
                    if (-not (Test-Path -LiteralPath $folder)) { throw 'Downloads folder does not exist yet. Start a session first.' }
                    Start-Process -FilePath explorer.exe -ArgumentList ('"' + $folder + '"')
                }
                '5' {
                    foreach ($test in @('Test-Parser.ps1','Test-CryptoPolicy.ps1','Test-DeviceHwid.ps1')) { & (Join-Path $homeDir $test) }
                }
                '6' { if ($interactive) { [Console]::CursorVisible = $false }; Show-Eye }
            }
        } catch { Write-Host 'Action failed. No automatic security bypass was attempted. Check required files or use the original script for diagnostics.' -ForegroundColor Red }
        if (-not $done -and $choice -ne '6') { $null = Read-Host 'Enter to return to dashboard' }
        if ($interactive) { [Console]::CursorVisible = $false }
        Clear-Host
    }
} finally {
    if ($interactive) {
        try { [Console]::CursorVisible = $oldCursor; [Console]::Title = $oldTitle } catch { }
    }
}
