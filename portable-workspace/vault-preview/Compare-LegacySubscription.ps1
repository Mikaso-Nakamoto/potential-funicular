#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Root = 'Z:\Iran\Browser\Working-Vault-Preview\WorkingRuntime',
    [string]$LegacyEncrypted = 'F:\Data\Iran\LibreWolf Browser\vpn\sub.txt.enc',
    [switch]$Apply
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Use 64-bit Windows PowerShell 5.1.' }
# Read-Vault validates the document using functions from Workspace.Common.ps1.
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Workspace.Common.ps1')
. (Join-Path $PSScriptRoot 'Vault.Common.ps1')
. (Join-Path $PSScriptRoot 'XrayPipe.Common.ps1')
. (Join-Path $PSScriptRoot 'VaultRefresh.Diagnostics.ps1')
. (Join-Path $PSScriptRoot 'VaultRefresh.Common.ps1')
# Standalone reader of the supplied kit-enc/1 format. Never executes legacy scripts.
$lock = $null; $password = $null; $legacySecret = $null; $ptr = [IntPtr]::Zero
$kdf = $null; $hmac = $null; $aes = $null; $decryptor = $null
$key = $null; $enc = $null; $macKey = $null; $plain = $null
$document = $null; $text = $null; $legacyPassword = $null; $params = $null
$xray = $null; $curl = $null; $requestBytes = $null; $response = $null
$oldTemp = $env:TEMP; $oldTmp = $env:TMP
function Escape-CurlValue([string]$Value) {
    if ($Value -match '[\x00-\x1f\x7f]') { throw 'Control characters prohibited.' }
    return $Value.Replace('\','\\').Replace('"','\"')
}
function Wait-OwnedCleanup($Handle,[string]$Name) {
    if ($null -eq $Handle) { return }
    try { $Handle.Dispose() } catch { Write-Warning ($Name + ' cleanup raised an error.') }
    if (-not $Handle.CleanupConfirmed) {
        Write-Warning ($Name + ' cleanup unconfirmed. Lock retained; do not force-close PowerShell.')
        while (-not $Handle.CleanupConfirmed) { Start-Sleep -Seconds 1 }
    }
}
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
    $tmp = Join-Path $Root 'private\tmp'
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $env:TEMP = $tmp; $env:TMP = $tmp
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
    $oldGuid = [Guid]::Empty; $vaultGuid = [Guid]::Empty
    if (-not [Guid]::TryParse($params['hwid'],[ref]$oldGuid) -or
        -not [Guid]::TryParse([string]$document.subscription.hwid,[ref]$vaultGuid)) {
        throw 'HWID is not a UUID; no request sent.'
    }
    if ($oldGuid -eq [Guid]::Empty -or $vaultGuid -eq [Guid]::Empty) { throw 'Zero UUID; no request sent.' }
    if ($oldGuid -eq $vaultGuid) {
        Write-Host 'HWID UUID VALUE: MATCH. Text formatting only; no live request sent.'
        if ($Apply) { throw 'No distinct legacy UUID to apply; unchanged.' }
    } else {
        Write-Host 'HWID UUID VALUE: DIFFERENT. Testing old parameters once; vault stays unchanged.'
    if (Test-ProfileBusy (Join-Path $Root 'private\profile')) { throw 'Close the browser first.' }
    if (@(Get-NetTCPConnection -State Listen -LocalPort 17890 -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Port occupied; no process will be stopped.' }
    $phase = 'xray-hash'
    $exe = Join-Path $Root 'Xray\xray.exe'
    if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne '1ca7a2cf61ba2c5d20b21a80d405b57933939751081cb289f07bd8ddf7cc3185') { throw 'Xray differs from the previously tested binary.' }
    $phase = 'windows-curl-signature'
    $curlExe = Join-Path ([Environment]::SystemDirectory) 'curl.exe'
    $signature = Get-AuthenticodeSignature -LiteralPath $curlExe
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') { throw 'Valid Microsoft-signed Windows curl required. No bypass.' }
    $tmp = Join-Path $Root 'private\tmp'
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $env:TEMP = $tmp; $env:TMP = $tmp
    $config = $document.activeConfig
    $uri = [Uri]$params['url']
    if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Fragment) { throw 'Invalid legacy URL.' }
    $hwid = [string]$params['hwid']
    $ua = [string]$params['ua']
    $request = @(
        'url = "' + (Escape-CurlValue $uri.AbsoluteUri) + '"'
        'header = "User-Agent: ' + (Escape-CurlValue $ua) + '"'
        'header = "x-hwid: ' + (Escape-CurlValue $hwid) + '"'
        'proxy = "socks5h://127.0.0.1:17890"'
        'noproxy = ""'
        'proto = "=https"'
        'proto-redir = "=https"'
        'connect-timeout = 10'
        'max-time = 30'
        'silent'
        'show-error'
        'fail'
        'write-out = "\nVICA_STATUS:%{http_code}"'
    ) -join "`n"
    $requestBytes = [Text.Encoding]::UTF8.GetBytes($request + "`n")
    $request = $null; $uri = $null; $hwid = $null
    $phase = 'compile-curl-helper'
    $source = Join-Path $PSScriptRoot 'CurlPipe.cs'
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne 'c8e14d3ea10de6bb075bb8ab7e039c660c022e878d27f22484abe1b6769d84b8') { throw 'curl helper integrity mismatch.' }
    if (-not ('VicaCurl.Session' -as [type])) { Add-Type -TypeDefinition ([IO.File]::ReadAllText($source)) -ErrorAction Stop }
    $phase = 'native-validation'
    Test-XrayObjectInMemory $exe $config
    $phase = 'owned-tunnel-start'
    $xray = Open-XrayRunSession $exe $config
    Send-XrayRunConfig $xray $config
    $config = $null
    $ready = $false
    for ($i=0; $i -lt 50; $i++) {
        if ($xray.HasFailed -or $xray.HasExited) { throw 'Xray exited.' }
        $listeners = @(Get-NetTCPConnection -State Listen -LocalPort 17890 -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -eq '127.0.0.1' -and $_.OwningProcess -eq $xray.Id })
        if ($listeners.Count -eq 1) { $ready = $true; break }
        Start-Sleep -Milliseconds 200
    }
    if (-not $ready) { throw 'Owned listener not ready.' }
    Write-Host 'LIVE REQUEST: exact old HWID and UA through owned Xray SOCKS5h. Remote DNS; no direct fallback; no browser; vault is read-only.'
    $phase = 'curl-through-tunnel'
    $curl = [VicaCurl.Session]::Begin($curlExe,$tmp)
    $response = $curl.Fetch($requestBytes)
    [Array]::Clear($requestBytes,0,$requestBytes.Length); $requestBytes = $null
    if ($xray.HasFailed -or $xray.HasExited) { throw 'Tunnel exited during request.' }
    $phase = 'response-status'
    $utf8 = New-Object Text.UTF8Encoding($false,$true)
    $text = $utf8.GetString($response)
    if ($text -notmatch '\nVICA_STATUS:([0-9]{3})$') { throw 'Missing curl status.' }
    $status = $Matches[1]
    Write-Host ('HTTP STATUS: ' + $status)
    if ($status -cne '200') { throw 'Only HTTP 200 accepted; redirects are not followed.' }
    $text = $text.Substring(0,$text.LastIndexOf("`nVICA_STATUS:"))
    $phase = 'diagnose'
    Get-RefreshResponseDiagnostics $text
    if ($Apply) {
        $phase = 'parse-for-publication'
        $parsed = Convert-RefreshSubscription $text
        $nodes = @($parsed.nodes)
        $previous = Get-RefreshNodeIdentity $document.activeConfig.outbounds[0]
        $matching = @()
        for ($j = 0; $j -lt $nodes.Count; $j++) {
            if ((Get-RefreshNodeIdentity $nodes[$j]) -ceq $previous) { $matching += $j }
        }
        $selected = -1
        if ($matching.Count -eq 1) {
            $selected = $matching[0]
            Write-Host 'Existing outbound uniquely matches refreshed list; preserving it.'
        } else {
            Write-Host ('Supported nodes: ' + $nodes.Count + '. Private labels/hosts are not printed.')
            $number = 0
            if (-not [int]::TryParse((Read-Host 'Node number (1-based; Enter cancels)'),[ref]$number)) { throw 'Cancelled.' }
            $selected = $number - 1
        }
        if ($selected -lt 0 -or $selected -ge $nodes.Count) { throw 'Invalid selection.' }
        $next = $document | ConvertTo-Json -Depth 30 -Compress | ConvertFrom-Json
        # Preserve the authenticated old UUID text; never generate a device identity.
        $next.subscription.hwid = $params['hwid']
        $next.activeConfig.outbounds = @($nodes[$selected])
        Assert-VaultDocument $next
        $phase = 'stop-fetch-children'
        Wait-OwnedCleanup $curl 'curl'
        Wait-OwnedCleanup $xray 'Xray'
        $curl = $null; $xray = $null
        $phase = 'validate-new-config'
        Test-XrayObjectInMemory $exe $next.activeConfig
        $phase = 'publication-confirmation'
        Write-Warning 'This replaces HWID and active outbound in the working encrypted vault. An encrypted previous version is retained. Native validation does not prove remote connectivity.'
        if ((Read-Host 'Type APPLY to publish; anything else cancels') -cne 'APPLY') { throw 'Cancelled; no publication.' }
        $phase = 'encrypted-publication'
        $backup = Write-RefreshReplacement $vaultPath $next $password $before
        Write-Host 'APPLIED: working vault HWID and config updated.'
        Write-Host ('Encrypted previous version: ' + $backup)
    }
    }
    $phase = 'unchanged-check'
    if (-not $Apply -and (Get-FileHash -LiteralPath $vaultPath -Algorithm SHA256).Hash -ne $before) { throw 'Vault changed externally.' }
    if (-not $Apply) { Write-Host 'READ-ONLY: vault unchanged. No legacy code execution, plaintext file, config update or browser launch. Stopping owned children.' }
    Write-Host 'LIMIT: stored text comparison, not proof of identical HTTP requests. Managed strings cannot be reliably wiped.'
} catch {
    throw ('Legacy comparison stopped at: ' + $phase + '. Details suppressed; do not share secrets.')
} finally {
    foreach ($item in @($decryptor,$aes,$hmac,$kdf,$password,$legacySecret)) { if ($null -ne $item) { $item.Dispose() } }
    if ($ptr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    foreach ($bytes in @($key,$enc,$macKey,$plain)) { if ($null -ne $bytes) { [Array]::Clear($bytes,0,$bytes.Length) } }
    $legacyPassword = $null; $text = $null; $params = $null; $document = $null
    $request = $null; $uri = $null; $hwid = $null; $ua = $null; $config = $null; $next = $null; $parsed = $null; $nodes = $null
    if ($requestBytes) { [Array]::Clear($requestBytes,0,$requestBytes.Length) }
    if ($response) { [Array]::Clear($response,0,$response.Length) }
    Wait-OwnedCleanup $curl 'curl'
    Wait-OwnedCleanup $xray 'Xray'
    $env:TEMP = $oldTemp; $env:TMP = $oldTmp
    if ($lock) { $lock.Dispose() }
}
