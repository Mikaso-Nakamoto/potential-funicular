#requires -Version 5.1
# Installs a pinned official MSVC binary only; never reads Runtime or installs a VC runtime.
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) { throw 'Windows x64 / 64-bit PowerShell required.' }
$directory = $PSScriptRoot
$target = Join-Path $directory 'lib'
if (Test-Path -LiteralPath $target) { throw 'lib already exists. Use a fresh test folder; installer will not overwrite it.' }
$stage = Join-Path $directory ('.dependency-' + [Guid]::NewGuid().ToString('N'))
$ownedStage = $false
$oldTemp = $env:TEMP; $oldTmp = $env:TMP
$oldTls = [Net.ServicePointManager]::SecurityProtocol
$oldRevocation = [Net.ServicePointManager]::CheckCertificateRevocationList
try {
    New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null
    $ownedStage = $true
    $env:TEMP = $stage; $env:TMP = $stage
    if ([Net.ServicePointManager]::ServerCertificateValidationCallback) { throw 'Custom TLS validation callback prohibited.' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    [Net.ServicePointManager]::CheckCertificateRevocationList = $true
    $archive = Join-Path $stage 'sodium.zip'
    $expected = '3e03a726fac4bc09cb61d8f29d658ef7a5eca0811de59082130414f7ca2e4279'
    $url = 'https://github.com/jedisct1/libsodium/releases/download/1.0.22-RELEASE/libsodium-1.0.22-msvc.zip'
    Write-Host 'Downloading official libsodium 1.0.22 MSVC package (not MinGW)...'
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $archive -TimeoutSec 120
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expected) { throw 'Archive SHA-256 mismatch.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        if ($zip.Entries.Count -gt 20000) { throw 'Too many ZIP entries.' }
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -match '(^/|\\|:|[\x00-\x1f]|(^|/)\.\.(/|$))') { throw 'Unsafe ZIP entry.' }
        }
        # Output.props defines x64/Release/v143/dynamic. Never choose Debug, ARM, static or another toolset.
        $candidates = @($zip.Entries | Where-Object { $_.FullName -cmatch '^(libsodium/)?x64/Release/v143/dynamic/libsodium\.dll$' })
        if ($candidates.Count -ne 1) { throw 'Expected one x64/Release/v143/dynamic/libsodium.dll. Package layout needs review; no guessing.' }
        $entry = $candidates[0]
        $unixType = (([int64]$entry.ExternalAttributes -shr 16) -band 0xf000)
        if ($unixType -notin @(0,0x8000) -or ($entry.ExternalAttributes -band 0x10) -ne 0 -or
            $entry.Length -lt 256 -or $entry.Length -gt 16777216) { throw 'DLL ZIP member is not a bounded regular file.' }
        # Read just this member to a fixed filename in an owned directory. No archive-controlled extraction paths.
        $dllPath = Join-Path $stage 'vica-sodium.dll'
        $inputStream = $entry.Open()
        $outputStream = $null
        try {
            $outputStream = [IO.File]::Open($dllPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $buffer = New-Object byte[] 65536
            $total = 0L
            while (($count = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $total += $count
                if ($total -gt $entry.Length -or $total -gt 16777216) { throw 'ZIP member exceeded its size.' }
                $outputStream.Write($buffer, 0, $count)
            }
            if ($total -ne $entry.Length) { throw 'Truncated ZIP member.' }
            $outputStream.Flush($true)
        } finally {
            if ($outputStream) { $outputStream.Dispose() }
            $inputStream.Dispose()
        }
        $archiveMember = $entry.FullName
    } finally { $zip.Dispose() }
    # Non-executing AMD64/import check, including installed Microsoft VC runtime signatures.
    & (Join-Path $directory 'Test-SodiumImports.ps1') -Path $dllPath
    $bundle = Join-Path $stage 'lib'
    New-Item -ItemType Directory -Path $bundle | Out-Null
    $installed = Join-Path $bundle 'vica-sodium.dll'
    [IO.File]::Move($dllPath, $installed)
    @{ version = '1.0.22'; build = 'msvc-v143-x64-release'; source = $url; archiveMember = $archiveMember;
       archiveSha256 = $expected; dllSha256 = (Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $bundle 'dependency.json') -Encoding UTF8
    [IO.Directory]::Move($bundle, $target)
    Write-Host 'Installed official MSVC dependency. No user configuration was read or changed.' -ForegroundColor Green
} finally {
    [Net.ServicePointManager]::SecurityProtocol = $oldTls
    [Net.ServicePointManager]::CheckCertificateRevocationList = $oldRevocation
    $env:TEMP = $oldTemp; $env:TMP = $oldTmp
    if ($ownedStage -and (Test-Path -LiteralPath $stage)) {
        try { Remove-Item -LiteralPath $stage -Recurse -Force } catch { Write-Warning 'Dependency staging cleanup failed.' }
    }
}
