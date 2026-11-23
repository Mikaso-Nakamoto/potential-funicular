#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$vaultToolDirectory = $PSScriptRoot
function Initialize-VaultCrypto {
    if ('VicAVault.Crypto' -as [type]) { return }
    $dll = [IO.Path]::GetFullPath((Join-Path $vaultToolDirectory 'lib\vica-sodium.dll'))
    $manifestPath = Join-Path $vaultToolDirectory 'lib\dependency.json'
    if (-not (Test-Path -LiteralPath $dll) -or -not (Test-Path -LiteralPath $manifestPath)) { throw 'Run Install-VaultDependency.ps1 first.' }
    if ((Get-Item -LiteralPath $manifestPath).Length -gt 4096) { throw 'Invalid dependency manifest.' }
    $manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    if ($manifest.version -ne '1.0.22' -or $manifest.build -ne 'msvc-v143-x64-release' -or $manifest.archiveSha256 -ne '3e03a726fac4bc09cb61d8f29d658ef7a5eca0811de59082130414f7ca2e4279' -or
        (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash -ne $manifest.dllSha256) { throw 'Crypto dependency integrity check failed.' }
    $sourcePath = Join-Path $vaultToolDirectory 'VaultCrypto.cs'
    if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne '9594757c1adfad80c89757d6a614244c2759a170769e798930a6c50c1b35f788') { throw 'Crypto source integrity check failed.' }
    & (Join-Path $vaultToolDirectory 'Test-SodiumImports.ps1') -Path $dll
    $source = [IO.File]::ReadAllText($sourcePath).Replace('__SODIUM_DLL__', $dll.Replace('"','""'))
    Add-Type -TypeDefinition $source -ErrorAction Stop
    [VicAVault.Crypto]::CheckSupport()
}
function Read-BoundedVaultBytes([string]$Path) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $length = $stream.Length
        if ($length -lt 52 -or $length -gt 8388660) { throw 'Vault size outside allowed range.' }
        $bytes = New-Object byte[] ([int]$length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $count = $stream.Read($bytes, $offset, $bytes.Length - $offset)
            if ($count -eq 0) { throw 'Truncated vault.' }
            $offset += $count
        }
        if ($stream.ReadByte() -ne -1) { throw 'Vault changed during read.' }
        return ,$bytes
    } finally { $stream.Dispose() }
}
function Assert-VaultDocument($Document) {
    Assert-Fields $Document @('version','createdAtUtc','subscription','activeConfig') @('version','subscription','activeConfig')
    if ($Document.version -ne 1) { throw 'Unsupported payload version.' }
    Assert-Fields $Document.subscription @('url','hwid') @('url','hwid')
    $uri = $null
    if (-not [Uri]::TryCreate([string]$Document.subscription.url, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Fragment) { throw 'Invalid subscription URL.' }
    $null = Convert-DeviceHwid $Document.subscription.hwid
    Assert-ConfigObjectPolicy $Document.activeConfig
}
function Read-Vault([string]$Path, [Security.SecureString]$Password) {
    Initialize-VaultCrypto
    $plain = $null
    try {
        $plain = [VicAVault.Crypto]::Open((Read-BoundedVaultBytes $Path), $Password)
        $utf8 = New-Object Text.UTF8Encoding($false, $true)
        $document = $utf8.GetString($plain) | ConvertFrom-Json
        Assert-VaultDocument $document
        return $document
    } catch { throw 'Vault could not be opened: wrong password, modified file, unavailable crypto or unsupported format. No fallback used.' }
    finally { if ($plain) { [Array]::Clear($plain, 0, $plain.Length) } }
}
function Write-NewVault([string]$Path, $Document, [Security.SecureString]$Password, [Security.SecureString]$Confirmation) {
    Initialize-VaultCrypto
    if (Test-Path -LiteralPath $Path) { throw 'Vault already exists; this preview never overwrites it.' }
    [VicAVault.Crypto]::ValidateNewPassword($Password)
    # Validate JSON-shaped payload before creating any file.
    Assert-VaultDocument ($Document | ConvertTo-Json -Depth 30 -Compress | ConvertFrom-Json)
    $ownsTemp = $false
    $plain = $null; $verified = $null; $temp = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $plain = [Text.Encoding]::UTF8.GetBytes(($Document | ConvertTo-Json -Depth 30 -Compress))
        $sealed = [VicAVault.Crypto]::Seal($plain, $Password)
        # Read-back with the confirmation password before publishing; never create an unusable vault silently.
        try { $verified = [VicAVault.Crypto]::Open($sealed, $Confirmation) }
        catch { throw 'Password confirmation does not match.' }
        if ($verified.Length -ne $plain.Length) { throw 'Read-back mismatch.' }
        $difference = 0
        for ($k = 0; $k -lt $plain.Length; $k++) { $difference = $difference -bor ($plain[$k] -bxor $verified[$k]) }
        if ($difference -ne 0) { throw 'Read-back mismatch.' }
        $stream = [IO.File]::Open($temp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $ownsTemp = $true
        try { $stream.Write($sealed, 0, $sealed.Length); $stream.Flush($true) }
        finally { $stream.Dispose() }
        # Verify the ciphertext actually written to disk too.
        $null = Read-Vault $temp $Confirmation
        [IO.File]::Move($temp, $Path)
    } catch { throw 'Vault creation failed (confirmation, validation or I/O). Original configuration was not changed.' }
    finally {
        if ($plain) { [Array]::Clear($plain, 0, $plain.Length) }
        if ($verified) { [Array]::Clear($verified, 0, $verified.Length) }
        if ($ownsTemp -and (Test-Path -LiteralPath $temp)) { try { Remove-Item -LiteralPath $temp -Force } catch { Write-Warning 'Encrypted staging file was not removed.' } }
    }
}
