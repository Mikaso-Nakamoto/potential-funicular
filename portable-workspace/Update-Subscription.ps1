#requires -Version 5.1
[CmdletBinding()]
param([string]$Root = '')
# Resolve the location in the script body, not in a parameter default expression.
$scriptDirectory = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDirectory)) {
    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if ([string]::IsNullOrWhiteSpace($scriptDirectory)) { throw 'Cannot determine script location. Run the saved PS1 file with -File.' }
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Join-Path $scriptDirectory 'Runtime' }
. (Join-Path $scriptDirectory 'Workspace.Common.ps1')
$Root = Get-Workspace $Root
$private = Join-Path $Root 'private'
New-Item -ItemType Directory -Path $private -Force | Out-Null
$secret = $null; $lock = $null; $candidate = $null; $ptr = [IntPtr]::Zero
try {
    # Same exclusive lock as the launcher: never update a running managed session.
    $lock = [IO.File]::Open((Join-Path $Root '.session.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    if (Test-ProfileBusy (Join-Path $private 'profile')) { throw 'Browser profile is in use, possibly after the launcher was closed. Close LibreWolf before updating.' }
    Write-Host 'Subscription is fetched over the current Windows connection, not through this tunnel.'
    Write-Host 'URL is hidden during input and is not saved. Redirects are rejected.'
    $secret = Read-Host 'Paste the complete HTTPS subscription URL' -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
    $url = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    $uri = $null
    if (-not [Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Fragment) { throw 'An HTTPS subscription URL without userinfo/fragment is required.' }
    $text = Get-SubscriptionText $uri
    if ($text -match '<\s*(!doctype|html|head|body)\b') { throw 'Server returned HTML, not a supported subscription.' }
    if ($text -notmatch '(?m)^\s*[a-z][a-z0-9+.-]*://') {
        try {
            $encoded = $text -replace '\s',''
            $encoded = $encoded.Replace('-','+').Replace('_','/')
            $encoded = $encoded.PadRight($encoded.Length + ((4 - $encoded.Length % 4) % 4), '=')
            $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded)).Trim().TrimStart([char]0xFEFF)
        } catch { throw 'Response is neither a plain VLESS list nor a Base64 list.' }
    }
    $lines = @($text -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($lines.Count -eq 0) { throw 'Empty subscription.' }
    $nodes = @(); $skipped = 0; $reasons = @{}
    foreach ($line in $lines) {
        try {
            $outbound = Convert-Vless $line
            $nodes += ,$outbound
        } catch {
            $skipped++
            # Only fixed, known parser messages are printable; never echo native URI exceptions.
            $r = 'Invalid or unsupported link.'
            $safeReasons = @(
                'Not a VLESS URI.', 'VLESS UUID required.', 'Zero UUID is prohibited.',
                'Explicit server and port required.', 'Unexpected URI path.',
                'Invalid query parameter.', 'Duplicate parameter.', 'Unsupported query parameter.',
                'Insecure TLS is prohibited.', 'Unsupported VLESS encryption.',
                'Only TLS or REALITY is supported.', 'Only TCP/RAW or WebSocket is supported.',
                'REALITY is supported only over TCP here.', 'Unsupported headerType.', 'Unsupported flow.',
                'Unsupported TLS fingerprint.', 'REALITY public key missing.',
                'REALITY ALPN parameter is not supported here.', 'Invalid REALITY key encoding.',
                'Invalid REALITY key.', 'Invalid REALITY short ID.', 'Explicit REALITY SNI is required.',
                'REALITY parameters on TLS URI.', 'WebSocket parameters on TCP URI.'
            )
            if ($_.Exception.Message -in $safeReasons) { $r = $_.Exception.Message }
            else {
                # Fixed categories only: exception messages can contain full URIs.
                $exception = $_.Exception
                while ($exception.InnerException) { $exception = $exception.InnerException }
                if ($exception -is [UriFormatException]) { $r = 'URI format error.' }
                elseif ($exception -is [FormatException]) { $r = 'Value format error.' }
                elseif ($exception -is [System.Management.Automation.ParameterBindingException]) { $r = 'Parser parameter binding error.' }
                elseif ($exception -is [System.Management.Automation.RuntimeException]) { $r = 'PowerShell parser/runtime compatibility error.' }
            }
            # Reveal only allowlisted transport metadata; never hosts, UUIDs, keys, labels or arbitrary values.
            $shape = @{ type = 'unspecified'; security = 'unspecified'; fp = 'unspecified' }
            try {
                $nodeUri = $null
                if ([Uri]::TryCreate($line, [UriKind]::Absolute, [ref]$nodeUri)) {
                    foreach ($pair in $nodeUri.Query.TrimStart('?').Split('&')) {
                        $kv = $pair.Split('=', 2)
                        if ($kv.Count -ne 2) { continue }
                        $name = [Uri]::UnescapeDataString($kv[0])
                        $value = [Uri]::UnescapeDataString($kv[1])
                        if ($name -in @('type','security','fp')) {
                            $shape[$name] = 'other'
                            if ($value -in @('tcp','raw','ws','grpc','xhttp','httpupgrade','tls','reality','none','chrome','firefox','safari','edge','random','randomized','unsafe')) {
                                # Emit a canonical constant from the allowlist, not raw server text.
                                $shape[$name] = $value.ToLowerInvariant()
                            }
                        }
                    }
                }
            } catch { }
            $r += ' [type=' + $shape.type + '; security=' + $shape.security + '; fp=' + $shape.fp + ']'
            if ($reasons.ContainsKey($r)) { $reasons[$r]++ } else { $reasons[$r] = 1 }
        }
    }
    foreach ($entry in $reasons.GetEnumerator()) { Write-Host ('Skipped x{0}: {1}' -f $entry.Value, $entry.Key) }
    if ($nodes.Count -eq 0) { throw 'No supported VLESS nodes. Active config unchanged. Do not share raw links; provide parameter names only for troubleshooting.' }
    Write-Host "Supported nodes: $($nodes.Count); unsupported entries: $skipped"
    # Do not print subscription labels/hosts: they can contain private information or terminal control sequences.
    for ($i = 0; $i -lt $nodes.Count; $i++) { Write-Host ("{0}: node {0} ({1}/{2})" -f ($i+1), $nodes[$i].streamSettings.network, $nodes[$i].streamSettings.security) }
    $selection = 0
    if (-not [int]::TryParse((Read-Host 'Node number'), [ref]$selection) -or $selection -lt 1 -or $selection -gt $nodes.Count) { throw 'Invalid node number.' }
    $config = @{
        log = @{ loglevel = 'none' }
        inbounds = @(@{ tag = 'browser'; listen = '127.0.0.1'; port = 17890; protocol = 'socks'; settings = @{ auth = 'noauth'; udp = $false } })
        outbounds = @($nodes[$selection-1])
    }
    $candidate = Join-Path $private ('candidate-' + [Guid]::NewGuid().ToString('N') + '.json')
    [IO.File]::WriteAllText($candidate, ($config | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
    Test-XrayConfig (Join-Path $Root 'Xray\xray.exe') $candidate
    $active = Join-Path $private 'xray.json'
    if (Test-Path -LiteralPath $active) {
        # File.Replace requires a filesystem that supports replacement (use NTFS).
        # On failure leave the active file untouched; no delete-then-move fallback.
        [IO.File]::Replace($candidate, $active, $null)
    } else { [IO.File]::Move($candidate, $active) }
    Write-Host 'Configuration validated and saved. This does NOT test remote connectivity.'
} finally {
    try {
        if ($ptr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
        if ($secret) { $secret.Dispose() }
        $url = $null; $uri = $null; $text = $null; $nodes = $null
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            try { Remove-Item -LiteralPath $candidate -Force }
            catch { Write-Warning 'Could not remove candidate config. It contains credentials; inspect private folder.' }
        }
    } finally { if ($lock) { $lock.Dispose() } }
}
