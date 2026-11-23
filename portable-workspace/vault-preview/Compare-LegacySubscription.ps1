#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Root = 'Z:\Iran\Browser\Working-Vault-Preview\WorkingRuntime',
    [string]$LegacyEncrypted = 'F:\Data\Iran\LibreWolf Browser\vpn\sub.txt.enc'
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Use 64-bit Windows PowerShell 5.1.' }
. (Join-Path $PSScriptRoot 'Vault.Common.ps1')
# Standalone reader of the supplied kit-enc/1 format. Never executes legacy scripts.
$lock = $null; $password = $null; $legacySecret = $null; $ptr = [IntPtr]::Zero
$kdf = $null; $hmac = $null; $aes = $null; $decryptor = $null
$key = $null; $enc = $null; $macKey = $null; $plain = $null
$document = $null; $text = $null; $legacyPassword = $null; $params = $null
$phase = 'preflight'
try {
    $Root = [IO.Path]::GetFullPath($Root)
    $lock = [IO.File]::Open((Join-Path $Root '.session.lock'),'OpenOrCreate','ReadWrite','None')
    $vaultPath = Join-Path $Root 'private\workspace.vault'
    $before = (Get-FileHash -LiteralPath $vaultPath -Algorithm SHA256).Hash
    # Read one bounded ciphertext snapshot; no temporary plaintext file.
    $stream = [IO.File]::Open($LegacyEncrypted,'Open','Read','Read')
    try {
        if ($stream.Length -le 0 -or $stream.Length -gt 33554432) { throw 'Invalid size.' }
        $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8, $true)
        try { $container = $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
    $lines = $container -split '\r?\n'
    if ($lines[0].Trim() -cne 'kit-enc/1') { throw 'Invalid format.' }
    $meta = @{}
    foreach ($line in $lines | Select-Object -Skip 1) {
        if ($line -match '^([A-Za-z0-9_]+)=(.*)$') {
            if ($meta.ContainsKey($Matches[1])) { throw 'Duplicate field.' }
            $meta[$Matches[1]] = $Matches[2].Trim()
        }
    }
    $salt = [Convert]::FromBase64String($meta['salt'])
    $iv = [Convert]::FromBase64String($meta['iv'])
    $want = [Convert]::FromBase64String($meta['mac'])
    $data = [Convert]::FromBase64String($meta['data'])
    $iters = 0
    if (-not [int]::TryParse($meta['iters'],[ref]$iters) -or $iters -lt 1000 -or $iters -gt 2000000) { throw 'Invalid iterations.' }
    if ($salt.Length -ne 16 -or $iv.Length -ne 16 -or $want.Length -ne 32 -or $data.Length -lt 16 -or $data.Length % 16 -ne 0) { throw 'Invalid fields.' }
    $prf = $meta['prf']; if (-not $prf) { $prf = 'SHA1' }
    if ($prf -notin @('SHA1','SHA256')) { throw 'Invalid PRF.' }
    $phase = 'vault-unlock'
    $password = Read-Host 'Current vault passphrase (hidden)' -AsSecureString
    $document = Read-Vault $vaultPath $password
    $phase = 'legacy-unlock'
    $legacySecret = Read-Host 'OLD USB password (hidden; may differ from vault)' -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($legacySecret)
    $legacyPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    $algorithm = [Security.Cryptography.HashAlgorithmName]::SHA1
    if ($prf -eq 'SHA256') { $algorithm = [Security.Cryptography.HashAlgorithmName]::SHA256 }
    $kdf = [Security.Cryptography.Rfc2898DeriveBytes]::new($legacyPassword,$salt,$iters,$algorithm)
    $key = $kdf.GetBytes(64)
    $enc = New-Object byte[] 32; $macKey = New-Object byte[] 32
    [Array]::Copy($key,0,$enc,0,32); [Array]::Copy($key,32,$macKey,0,32)
    $both = New-Object byte[] ($iv.Length + $data.Length)
    [Array]::Copy($iv,0,$both,0,16); [Array]::Copy($data,0,$both,16,$data.Length)
    $hmac = New-Object Security.Cryptography.HMACSHA256(, $macKey)
    $got = $hmac.ComputeHash($both); $difference = 0
    for ($i = 0; $i -lt 32; $i++) { $difference = $difference -bor ($got[$i] -bxor $want[$i]) }
    if ($difference -ne 0) { throw 'Authentication failed.' }
    $aes = [Security.Cryptography.Aes]::Create()
    $aes.Mode = [Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [Security.Cryptography.PaddingMode]::PKCS7
    $aes.Key = $enc; $aes.IV = $iv
    $decryptor = $aes.CreateDecryptor()
    $plain = $decryptor.TransformFinalBlock($data,0,$data.Length)
    $phase = 'compare'
    $utf8 = New-Object Text.UTF8Encoding($false,$true)
    $text = $utf8.GetString($plain).TrimStart([char]0xFEFF)
    $params = @{}
    foreach ($line in ($text -split '\r?\n')) {
        if ($line -match '^\s*(\w+)\s*=\s*(.*)$') {
            $name = $Matches[1].ToLowerInvariant()
            if ($name -in @('url','hwid','ua')) {
                if ($params.ContainsKey($name)) { throw 'Duplicate subscription parameter.' }
                # Deliberately no Trim, URI canonicalization or GUID normalization.
                $params[$name] = $Matches[2]
            }
        }
    }
    if (-not $params.ContainsKey('url') -or -not $params.ContainsKey('hwid') -or -not $params.ContainsKey('ua')) { throw 'Missing subscription parameter.' }
    foreach ($pair in @(@('URL','url'),@('HWID','hwid'))) {
        $value = [string]$document.subscription.($pair[1])
        $result = 'DIFFERENT'
        if ([string]::Equals($params[$pair[1]],$value,[StringComparison]::Ordinal)) { $result = 'MATCH' }
        Write-Host ($pair[0] + ': ' + $result + ' (exact stored text)')
    }
    foreach ($candidate in @('INCY/3.0.28','v2rayNG')) {
        $result = 'DIFFERENT'
        if ([string]::Equals($params['ua'],$candidate,[StringComparison]::Ordinal)) { $result = 'MATCH' }
        Write-Host ('OLD UA vs ' + $candidate + ': ' + $result)
    }
    $phase = 'unchanged-check'
    if ((Get-FileHash -LiteralPath $vaultPath -Algorithm SHA256).Hash -ne $before) { throw 'Vault changed externally.' }
    Write-Host 'READ-ONLY: vault unchanged. No network, legacy code execution, plaintext file, config update or browser launch.'
    Write-Host 'LIMIT: stored text comparison, not proof of identical HTTP requests. Managed strings cannot be reliably wiped.'
} catch {
    throw ('Legacy comparison stopped at: ' + $phase + '. Details suppressed; do not share secrets.')
} finally {
    foreach ($item in @($decryptor,$aes,$hmac,$kdf,$password,$legacySecret)) { if ($null -ne $item) { $item.Dispose() } }
    if ($ptr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    foreach ($bytes in @($key,$enc,$macKey,$plain)) { if ($null -ne $bytes) { [Array]::Clear($bytes,0,$bytes.Length) } }
    $legacyPassword = $null; $text = $null; $params = $null; $document = $null
    if ($lock) { $lock.Dispose() }
}
