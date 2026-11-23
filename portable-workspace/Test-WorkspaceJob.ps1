#requires -Version 5.1
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Use 64-bit Windows PowerShell 5.1.' }
. (Join-Path $PSScriptRoot 'Workspace.Job.ps1')
$stage = Join-Path $PSScriptRoot ('.job-test-' + [Guid]::NewGuid().ToString('N'))
$oldTemp = $env:TEMP; $oldTmp = $env:TMP
$owner = $null; $supervisor = $null; $created = $false
$log = New-Object 'Collections.Generic.List[string]'
function Note([string]$Message) { Write-Host $Message; $log.Add($Message) }
function Wait-Markers([string]$Prefix) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt 20) {
        if ((Test-Path -LiteralPath ($Prefix + '.parent')) -and (Test-Path -LiteralPath ($Prefix + '.leaf'))) {
            try {
                $parentId = 0; $leafId = 0
                $parentReady = [int]::TryParse([IO.File]::ReadAllText($Prefix + '.parent'),[ref]$parentId)
                $leafReady = [int]::TryParse([IO.File]::ReadAllText($Prefix + '.leaf'),[ref]$leafId)
                if ($parentReady -and $leafReady -and $parentId -gt 0 -and $leafId -gt 0) {
                    $ids = @($parentId,$leafId)
                    foreach ($childId in $ids) { $null = Get-Process -Id $childId -ErrorAction Stop }
                    return $ids
                }
            } catch { } # marker exists before WriteAllText has necessarily completed
        }
        Start-Sleep -Milliseconds 100
    }
    throw 'Fixture parent/descendant did not reach readiness.'
}
function Assert-Exited([int[]]$Ids) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt 10) {
        $alive = @($Ids | ForEach-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
        if ($alive.Count -eq 0) { return }
        Start-Sleep -Milliseconds 100
    }
    throw 'Owned fixture process survived job cleanup.'
}
try {
    New-Item -ItemType Directory -Path $stage | Out-Null; $created = $true
    $env:TEMP = $stage; $env:TMP = $stage
    Note ('Job lifecycle test; PS ' + $PSVersionTable.PSVersion + '; CLR ' + [Environment]::Version)
    foreach ($name in @('WorkspaceJob.cs','Workspace.Job.ps1','Test-WorkspaceJob.ps1')) {
        Note ('SHA256 ' + (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name) -Algorithm SHA256).Hash + '  ' + $name)
    }
    $fixture = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
public static class JobFixture {
    public static void Main(string[] args) {
        if (args.Length == 4 && args[0] == "run" && args[1] == "-test") { File.WriteAllText(args[3] + ".validated", "yes"); return; }
        bool leaf = args.Length == 2 && args[0] == "leaf";
        string marker = leaf ? args[1] : args[2];
        File.WriteAllText(marker + (leaf ? ".leaf" : ".parent"), Process.GetCurrentProcess().Id.ToString());
        if (!leaf) {
            var start = new ProcessStartInfo(Process.GetCurrentProcess().MainModule.FileName, "leaf \"" + marker + "\"");
            start.UseShellExecute = false; start.CreateNoWindow = true;
            using (Process child = Process.Start(start)) {}
        }
        Thread.Sleep(120000);
    }
}
'@
    $exe = Join-Path $stage 'JobFixture.exe'
    Add-Type -TypeDefinition $fixture -OutputAssembly $exe -OutputType ConsoleApplication -ErrorAction Stop
    $marker = Join-Path $stage 'validation'
    $owner = Start-OwnedWorkspaceXray $exe $marker $stage -ValidateOnly
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while (-not $owner.HasExited -and $timer.Elapsed.TotalSeconds -lt 20) { Start-Sleep -Milliseconds 100 }
    if (-not $owner.HasExited -or $owner.ExitCode -ne 0 -or -not (Test-Path -LiteralPath ($marker + '.validated'))) { throw 'Native validation mode did not execute correctly.' }
    Stop-OwnedWorkspaceXray $owner; $owner = $null
    Note 'PASS: native validation argument mode executed under Job and cleanup confirmed'
    $marker = Join-Path $stage 'normal'
    $owner = Start-OwnedWorkspaceXray $exe $marker $stage
    $ids = @(Wait-Markers $marker)
    Stop-OwnedWorkspaceXray $owner
    if (-not $owner.CleanupConfirmed) { throw 'Cleanup was not confirmed.' }
    Assert-Exited $ids
    $owner = $null
    Note 'PASS: suspended start assigned before execution; explicit cleanup stopped parent and descendant; cleanup confirmed'
    $worker = Join-Path $stage 'supervisor.ps1'
    $workerSource = @'
param([string]$Tools,[string]$Exe,[string]$Marker,[string]$Stage)
$ErrorActionPreference = 'Stop'
$env:TEMP = $Stage; $env:TMP = $Stage
. (Join-Path $Tools 'Workspace.Job.ps1')
$owner = Start-OwnedWorkspaceXray $Exe $Marker $Stage
try { Start-Sleep -Seconds 120 } finally { Stop-OwnedWorkspaceXray $owner }
'@
    [IO.File]::WriteAllText($worker,$workerSource)
    $marker = Join-Path $stage 'forced'
    $supervisor = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','RemoteSigned','-File',('"'+$worker+'"'),'-Tools',('"'+$PSScriptRoot+'"'),'-Exe',('"'+$exe+'"'),'-Marker',('"'+$marker+'"'),'-Stage',('"'+$stage+'"')) -PassThru
    $ids = @(Wait-Markers $marker)
    if ($supervisor.HasExited) { throw 'Supervisor exited before forced-termination test.' }
    Stop-Process -InputObject $supervisor -ErrorAction Stop
    if (-not $supervisor.WaitForExit(5000)) { throw 'Supervisor termination not confirmed.' }
    Assert-Exited $ids
    Note 'PASS: forced supervisor termination killed job parent and descendant without managed finally'
    Note 'RESULT: PASS for implemented Windows job fixtures only. Not a browser/real Xray or power-loss test.'
} catch { Note ('RESULT: FAIL: ' + $_.Exception.Message); throw }
finally {
    if ($owner) { Stop-OwnedWorkspaceXray $owner }
    if ($supervisor) {
        if (-not $supervisor.HasExited) { Stop-Process -InputObject $supervisor -ErrorAction SilentlyContinue; $null = $supervisor.WaitForExit(5000) }
        $supervisor.Dispose()
    }
    $env:TEMP = $oldTemp; $env:TMP = $oldTmp
    [IO.File]::WriteAllLines((Join-Path $PSScriptRoot 'job-lifecycle-report.txt'),$log.ToArray(),(New-Object Text.UTF8Encoding($true)))
    # Only delete owned stage if no process running from it remains; retain on inspection failure.
    if ($created) {
        try {
            $alive = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object { ($_.ExecutablePath -and $_.ExecutablePath.StartsWith($stage + '\',[StringComparison]::OrdinalIgnoreCase)) -or (-not $_.ExecutablePath -and $_.Name -eq 'JobFixture.exe') })
            if ($alive.Count -eq 0) { Remove-Item -LiteralPath $stage -Recurse -Force }
            else { Write-Warning ('Test stage retained: ' + $stage) }
        } catch { Write-Warning ('Test stage retained: ' + $stage) }
    }
}
