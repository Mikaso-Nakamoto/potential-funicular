#requires -Version 5.1
[CmdletBinding()]
param([string]$Base = 'Z:\Iran\Browser')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Base = [IO.Path]::GetFullPath($Base).TrimEnd('\')
$new = Join-Path $Base 'VIC-A-New\Runtime'
$locks = New-Object 'Collections.Generic.List[IDisposable]'
$report = New-Object 'Collections.Generic.List[object]'
# Delete the exact compared file through its still-open handle, not by a second path lookup.
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class VicaCleanupFile {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint mode, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool SetFileInformationByHandle(SafeFileHandle file, int kind, ref int value, uint size);
    public static FileStream Open(string path) {
        var h=CreateFile(path,0x80010000,1,IntPtr.Zero,3,0,IntPtr.Zero);
        if(h.IsInvalid) { h.Dispose(); throw new IOException("Cannot lock source for deletion."); }
        try { return new FileStream(h,FileAccess.Read); } catch { h.Dispose(); throw; }
    }
    public static void Delete(FileStream file) {
        int yes=1;
        if(!SetFileInformationByHandle(file.SafeFileHandle,4,ref yes,4))
            throw new IOException("Delete disposition failed.");
    }
}
'@
function Assert-PlainPath([string]$Path) {
    $p = [IO.Path]::GetFullPath($Path)
    while ($p) {
        if (Test-Path -LiteralPath $p) {
            if ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Links/junctions are not supported.' }
        }
        $parent = [IO.Path]::GetDirectoryName($p)
        if ($parent -eq $p) { break }; $p = $parent
    }
}
function Same-Stream($A,$B) {
    if ($A.Length -ne $B.Length) { return $false }
    $A.Position=0; $B.Position=0
    $x=New-Object byte[] 65536; $y=New-Object byte[] 65536
    while (($n=$A.Read($x,0,$x.Length)) -gt 0) {
        $offset=0
        while ($offset -lt $n) { $m=$B.Read($y,$offset,($n-$offset)); if ($m -eq 0) { return $false }; $offset+=$m }
        for ($i=0;$i -lt $n;$i++) { if ($x[$i] -ne $y[$i]) { return $false } }
    }
    return $true
}
try {
    Assert-PlainPath $Base
    Assert-PlainPath $new
    if (-not (Test-Path -LiteralPath (Join-Path $new 'private\workspace.vault') -PathType Leaf)) { throw 'New Runtime/vault missing. No cleanup.' }
    $header=New-Object byte[] 8
    $f=[IO.File]::OpenRead((Join-Path $new 'private\workspace.vault'))
    try { if ($f.Read($header,0,8) -ne 8 -or [Text.Encoding]::ASCII.GetString($header) -cne 'VICAPK03') { throw 'New V03 vault required.' } } finally { $f.Dispose() }
    if (@(Get-Process -Name librewolf,xray -ErrorAction SilentlyContinue).Count) { throw 'Close browsers and Xray normally first. Nothing will be killed.' }
    if (@(Get-NetTCPConnection -State Listen -LocalPort 17890 -ErrorAction SilentlyContinue).Count) { throw 'Tunnel port occupied. No cleanup.' }
    $launcher=Join-Path $Base 'VIC-A-New\vica\Start-VicaSession.ps1'
    Assert-PlainPath $launcher
    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { throw 'New launcher missing.' }
    Write-Host 'First: authenticate NEW vault and run offline native config validation. Enter NEW password locally.'
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File $launcher -Root $new -ValidateOnly
    if ($LASTEXITCODE -ne 0) { throw 'New installation validation failed. No cleanup.' }
    $roots=@((Join-Path $Base 'Runtime'),(Join-Path $Base 'Working-Vault-Preview\WorkingRuntime'))
    foreach ($root in @($new)+$roots) {
        if (Test-Path -LiteralPath $root -PathType Container) {
            Assert-PlainPath $root
            $locks.Add([IO.File]::Open((Join-Path $root '.session.lock'),'OpenOrCreate','ReadWrite','None'))
        }
    }
    Write-Host 'Only identical Xray, LibreWolf and private\downloads files in the two known old Runtime folders are eligible.'
    Write-Host 'Profiles, vaults, configs, backups, scripts and unknown folders are NEVER deleted. New Runtime is read-only.'
    if ((Read-Host 'Type CLEAN to remove verified duplicates; Enter cancels') -cne 'CLEAN') { return }
    foreach ($root in $roots) {
        foreach ($area in @('Xray','LibreWolf','private\downloads')) {
            $dir=Join-Path $root $area
            if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
            Assert-PlainPath $dir
            # Enumerate one level at a time: never recurse into junctions.
            $pending=New-Object 'Collections.Generic.Queue[string]'; $pending.Enqueue($dir)
            while ($pending.Count) {
                foreach ($item in @(Get-ChildItem -LiteralPath $pending.Dequeue() -Force)) {
                    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { $report.Add([pscustomobject]@{Path=$item.FullName;Result='KEPT_LINK'}); continue }
                    if ($item.PSIsContainer) { $pending.Enqueue($item.FullName); continue }
                    $relative=$item.FullName.Substring($root.Length).TrimStart('\')
                    $target=Join-Path $new $relative
                    $result='KEPT_UNIQUE'; $a=$null; $b=$null
                    try {
                        Assert-PlainPath $item.FullName; Assert-PlainPath $target
                        if (Test-Path -LiteralPath $target -PathType Leaf) {
                            # Deny writes while comparing; keep the destination locked through deletion.
                            $b=[IO.File]::Open($target,'Open','Read','Read')
                            $a=[VicaCleanupFile]::Open($item.FullName)
                            if (Same-Stream $a $b) {
                                [VicaCleanupFile]::Delete($a)
                                $result='DELETED_IDENTICAL'
                            } else { $result='KEPT_DIFFERENT' }
                        }
                    } catch { $result='KEPT_ERROR' }
                    finally { if ($a) { $a.Dispose() }; if ($b) { $b.Dispose() } }
                    $report.Add([pscustomobject]@{Path=$item.FullName;Result=$result})
                }
            }
        }
    }
    Write-Host ('Deleted identical files: ' + @($report | Where-Object Result -eq 'DELETED_IDENTICAL').Count)
    Write-Host 'Unique data and all profiles/vaults retained. Old installations may now be incomplete; use VIC-A-New only.'
} catch { Write-Warning 'Cleanup stopped safely. Close applications and verify the installation paths. No automatic process termination.' }
finally {
    foreach ($l in $locks) { $l.Dispose() }
    if ($report.Count) {
        $out=Join-Path $PSScriptRoot ('cleanup-report-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'.csv')
        $report | Export-Csv -LiteralPath $out -NoTypeInformation -Encoding UTF8
        Write-Host ('Local report (file names only; do not publish): '+$out)
    }
    Read-Host 'Enter to close' | Out-Null
}
