#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Path)
$ErrorActionPreference = 'Stop'
if (-not ('VicAReview.SodiumPe' -as [type])) {
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'SodiumPe.cs'))) -ErrorAction Stop
}
$stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
try {
    if ($stream.Length -lt 256 -or $stream.Length -gt 16777216) { throw 'DLL size outside allowed range.' }
    $bytes = New-Object byte[] ([int]$stream.Length)
    $offset = 0
    while ($offset -lt $bytes.Length) {
        $count = $stream.Read($bytes, $offset, $bytes.Length - $offset)
        if ($count -eq 0) { throw 'Truncated DLL.' }
        $offset += $count
    }
    if ($stream.ReadByte() -ne -1) { throw 'DLL changed during read.' }
} finally { $stream.Dispose() }
$imports = @([VicAReview.SodiumPe]::Imports($bytes))
# Deliberately narrow; never auto-download an unexpected runtime dependency.
$allowed = @('kernel32.dll','advapi32.dll','bcrypt.dll','msvcrt.dll','ucrtbase.dll','ntdll.dll')
foreach ($name in $imports) {
    if ($name -notin $allowed) { throw ('Unreviewed dependency: ' + $name + '. Stop; do not edit the allowlist to bypass this check.') }
}
Write-Host ('PE import gate PASS: ' + (($imports | Sort-Object -Unique) -join ', '))
Write-Host 'Direct imports only. Not a full recursive audit of Windows system modules or dynamic GetProcAddress calls.'
