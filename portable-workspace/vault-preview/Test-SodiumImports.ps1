#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Path)
$ErrorActionPreference = 'Stop'
if (-not [Environment]::Is64BitProcess -or $env:OS -ne 'Windows_NT') { throw 'Windows x64 process required for System32 inspection.' }
if (-not ('VicAReview.SodiumPe' -as [type])) {
    $peBytes = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'SodiumPe.cs'))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $digest = ([BitConverter]::ToString($sha.ComputeHash($peBytes))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
    if ($digest -cne '79c7dd318eb2dda05d8d6e316c1848821c6d511a05ab1c18dbcf9edf9381f4df') { throw 'PE source integrity check failed.' }
    Add-Type -TypeDefinition ([Text.Encoding]::UTF8.GetString($peBytes)) -ErrorAction Stop
}
function Get-ImageImports([string]$ImagePath) {
    $stream = [IO.File]::Open($ImagePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
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
    return [VicAReview.SodiumPe]::Imports($bytes)
}
$system = [Environment]::GetFolderPath('System')
$allowed = @('kernel32.dll','advapi32.dll','bcrypt.dll','msvcrt.dll','ucrtbase.dll','ntdll.dll')
$vcRuntime = @('vcruntime140.dll','vcruntime140_1.dll')
$seen = @{}
$pending = New-Object 'Collections.Generic.Queue[string]'
$pending.Enqueue([IO.Path]::GetFullPath($Path))
while ($pending.Count -gt 0) {
    $image = $pending.Dequeue()
    $imports = @(Get-ImageImports $image)
    Write-Host (([IO.Path]::GetFileName($image)) + ' imports: ' + (($imports | Sort-Object -Unique) -join ', '))
    foreach ($name in $imports) {
        if ($name -in $vcRuntime) {
            if ($seen.ContainsKey($name)) { continue }
            $seen[$name] = $true
            $runtimePath = Join-Path $system $name
            if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
                throw ('Missing Microsoft VC++ x64 runtime in System32: ' + $name + '. No runtime is downloaded or installed by this tool. Stop and report this message.')
            }
            if (((Get-Item -LiteralPath $runtimePath).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'VC runtime reparse point refused.' }
            $signature = Get-AuthenticodeSignature -LiteralPath $runtimePath
            if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
                $signature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') {
                throw ('Microsoft signature check failed for System32 runtime: ' + $name)
            }
            Write-Host ('Microsoft signature PASS: System32\' + $name)
            # Review its direct imports too; Windows OS modules/API-set mappings remain platform trust.
            $pending.Enqueue($runtimePath)
        } elseif ($name -in $allowed) {
            if (-not (Test-Path -LiteralPath (Join-Path $system $name) -PathType Leaf)) { throw ('Missing System32 module: ' + $name) }
        } elseif ($name -cmatch '^api-ms-win-crt-(conio|convert|environment|filesystem|heap|locale|math|multibyte|private|process|runtime|stdio|string|time|utility)-l1-1-0\.dll$') {
            if (-not (Test-Path -LiteralPath (Join-Path $system 'ucrtbase.dll') -PathType Leaf)) { throw 'Windows UCRT is unavailable.' }
        } else {
            throw ('Unreviewed dependency: ' + $name + '. Stop; do not edit the allowlist to bypass this check.')
        }
    }
}
Write-Host 'PE import gate PASS: only approved Windows modules/API contracts and signature-verified System32 VC runtime.'
Write-Host 'Not a recursive audit of Windows OS components or dynamic GetProcAddress calls; no PATH lookup or runtime installation.'
