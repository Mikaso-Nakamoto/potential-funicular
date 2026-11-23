#requires -Version 5.1
# Installs only a pinned official crypto dependency beside this script. Does not read Runtime.
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) { throw 'Windows x64 / 64-bit PowerShell required.' }
$directory = $PSScriptRoot
$target = Join-Path $directory 'lib'
if (Test-Path -LiteralPath $target) { throw 'lib already exists. Verify it before replacing anything; installer will not overwrite it.' }
$stage = Join-Path $directory ('.dependency-' + [Guid]::NewGuid().ToString('N'))
$oldTls = [Net.ServicePointManager]::SecurityProtocol
$oldRevocation = [Net.ServicePointManager]::CheckCertificateRevocationList
try {
    New-Item -ItemType Directory -Path $stage | Out-Null
    if ([Net.ServicePointManager]::ServerCertificateValidationCallback) { throw 'Custom TLS validation callback prohibited.' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    [Net.ServicePointManager]::CheckCertificateRevocationList = $true
    $archive = Join-Path $stage 'sodium.tar.gz'
    $expected = '1d99e0afaf27bce664249232e9dc628ae6bb7b49f0ab53ad6db372b028a35d9d'
    $url = 'https://github.com/jedisct1/libsodium/releases/download/1.0.22-RELEASE/libsodium-1.0.22-mingw.tar.gz'
    Write-Host 'Downloading official libsodium 1.0.22 MinGW package...'
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $archive -TimeoutSec 120
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expected) { throw 'Archive SHA-256 mismatch.' }
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (-not (Test-Path -LiteralPath $tar)) { throw 'Windows tar.exe required. No alternate archive tool is downloaded.' }
    $unpack = Join-Path $stage 'unpack'
    New-Item -ItemType Directory -Path $unpack | Out-Null
    # Never unpack the whole archive. Only one explicitly listed regular-file member.
    $members = @(& $tar -tzf $archive)
    if ($LASTEXITCODE -ne 0 -or $members.Count -gt 20000) { throw 'Cannot inspect archive.' }
    foreach ($member in $members) {
        if ($member -match '(^/|\\|:|[\x00-\x1f]|(^|/)\.\.(/|$))') { throw 'Unsafe archive entry.' }
    }
    $candidates = @($members | Where-Object { $_ -cmatch '^(\./)?libsodium-win64/bin/libsodium-[0-9]+\.dll$' })
    if ($candidates.Count -ne 1) { throw 'Expected exactly one libsodium-win64/bin/libsodium-N.dll member.' }
    $member = $candidates[0]
    $listing = @(& $tar -tvzf $archive -- $member)
    if ($LASTEXITCODE -ne 0 -or $listing.Count -ne 1 -or -not $listing[0].StartsWith('-')) { throw 'DLL must be one regular file, not a link.' }
    & $tar -xzf $archive -C $unpack -- $member
    if ($LASTEXITCODE -ne 0) { throw 'Archive extraction failed.' }
    $dllPath = Join-Path $unpack $member
    $item = Get-Item -LiteralPath $dllPath
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -gt 16777216) { throw 'Invalid extracted DLL.' }
    $bytes = [IO.File]::ReadAllBytes($dllPath)
    if ($bytes.Length -lt 256 -or $bytes[0] -ne 77 -or $bytes[1] -ne 90) { throw 'Invalid PE image.' }
    $offset = [BitConverter]::ToInt32($bytes, 60)
    if ($offset -lt 64 -or $offset -gt ($bytes.Length - 6) -or [BitConverter]::ToUInt32($bytes, $offset) -ne 17744 -or [BitConverter]::ToUInt16($bytes, $offset + 4) -ne 34404) { throw 'DLL is not AMD64 PE.' }
    $bundle = Join-Path $stage 'lib'
    New-Item -ItemType Directory -Path $bundle | Out-Null
    $installed = Join-Path $bundle 'vica-sodium.dll'
    Copy-Item -LiteralPath $dllPath -Destination $installed
    @{ version = '1.0.22'; source = $url; archiveSha256 = $expected; dllSha256 = (Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $bundle 'dependency.json') -Encoding UTF8
    [IO.Directory]::Move($bundle, $target)
    Write-Host 'Installed. Next run Test-Vault.ps1. No secrets were read or changed.' -ForegroundColor Green
} finally {
    [Net.ServicePointManager]::SecurityProtocol = $oldTls
    [Net.ServicePointManager]::CheckCertificateRevocationList = $oldRevocation
    if (Test-Path -LiteralPath $stage) {
        try { Remove-Item -LiteralPath $stage -Recurse -Force } catch { Write-Warning 'Dependency staging cleanup failed.' }
    }
}
