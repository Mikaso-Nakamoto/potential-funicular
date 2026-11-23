#requires -Version 5.1
# Tests only the PE inspector with an in-memory synthetic image; never loads this image.
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'SodiumPe.cs'))) -ErrorAction Stop
function Put16([byte[]]$Bytes, [int]$Offset, [uint16]$Value) { [Array]::Copy([BitConverter]::GetBytes($Value), 0, $Bytes, $Offset, 2) }
function Put32([byte[]]$Bytes, [int]$Offset, [uint32]$Value) { [Array]::Copy([BitConverter]::GetBytes($Value), 0, $Bytes, $Offset, 4) }
function Reject-Pe([byte[]]$Bytes) {
    $failed = $false
    try { $null = [VicAReview.SodiumPe]::Imports($Bytes) } catch { $failed = $true }
    if (-not $failed) { throw 'Malformed PE accepted by inspector.' }
}
$bytes = New-Object byte[] 1024
Put16 $bytes 0 0x5a4d
Put32 $bytes 60 0x80
Put32 $bytes 0x80 0x4550
Put16 $bytes 0x84 0x8664
Put16 $bytes 0x86 1
Put16 $bytes 0x94 240
Put16 $bytes 0x98 0x20b
Put32 $bytes (0x98 + 60) 0x200
Put32 $bytes (0x98 + 108) 16
Put32 $bytes (0x98 + 120) 0x1000
Put32 $bytes (0x98 + 124) 40
Put32 $bytes (0x188 + 12) 0x1000
Put32 $bytes (0x188 + 16) 0x200
Put32 $bytes (0x188 + 20) 0x200
Put32 $bytes (0x200 + 12) 0x1040
$name = [Text.Encoding]::ASCII.GetBytes("KERNEL32.dll`0")
[Array]::Copy($name, 0, $bytes, 0x240, $name.Length)
$imports = @([VicAReview.SodiumPe]::Imports($bytes))
if ($imports.Count -ne 1 -or $imports[0] -cne 'kernel32.dll') { throw 'Synthetic import mismatch.' }
Reject-Pe (New-Object byte[] 32)
$bad = [byte[]]$bytes.Clone(); Put32 $bad 60 ([uint32]::MaxValue); Reject-Pe $bad
$bad = [byte[]]$bytes.Clone(); Put32 $bad (0x98 + 112 + 13 * 8) 1; Reject-Pe $bad
$bad = [byte[]]$bytes.Clone(); Put32 $bad (0x98 + 124) 20; Reject-Pe $bad
$bad = [byte[]]$bytes.Clone(); Put32 $bad (0x200 + 12) 4294967280; Reject-Pe $bad
Write-Host 'PASS: synthetic PE imports; invalid size, offset, delay imports, missing terminator and unmapped RVA rejected.'
