#requires -Version 5.1
# Output is fixed categories/counts only. Never print exceptions, hosts, labels, URIs or response bytes.
function Get-RefreshResponseDiagnostics([string]$Text) {
    $reasonCodes = @{
        'Not a VLESS URI.' = 'not-vless'
        'VLESS UUID required.' = 'invalid-uuid'
        'Zero UUID is prohibited.' = 'zero-uuid'
        'Explicit server and port required.' = 'endpoint-shape'
        'Unexpected URI path.' = 'uri-path'
        'Invalid query parameter.' = 'query-shape'
        'Duplicate parameter.' = 'duplicate-query'
        'Unsupported query parameter.' = 'unsupported-query'
        'Insecure TLS is prohibited.' = 'insecure-tls'
        'Unsupported VLESS encryption.' = 'unsupported-encryption'
        'Only TLS or REALITY is supported.' = 'unsupported-security'
        'Only TCP/RAW or WebSocket is supported.' = 'unsupported-transport'
        'REALITY is supported only over TCP here.' = 'reality-transport'
        'Unsupported headerType.' = 'unsupported-header'
        'Unsupported flow.' = 'unsupported-flow'
        'Unsupported TLS fingerprint.' = 'unsupported-fingerprint'
        'REALITY public key missing.' = 'missing-reality-key'
        'REALITY ALPN parameter is not supported here.' = 'reality-alpn'
        'Invalid REALITY key encoding.' = 'reality-key-encoding'
        'Invalid REALITY key.' = 'reality-key-shape'
        'Invalid REALITY short ID.' = 'reality-short-id'
        'Explicit REALITY SNI is required.' = 'missing-reality-sni'
        'REALITY parameters on TLS URI.' = 'mixed-security'
        'WebSocket parameters on TCP URI.' = 'mixed-transport'
    }
    if ([string]::IsNullOrWhiteSpace($Text)) { 'FORMAT: empty'; return }
    if ($Text.Length -gt 4194304) { 'FORMAT: oversized'; return }
    $Text = $Text.Trim().TrimStart([char]0xFEFF)
    if ($Text -match '<\s*(!doctype|html|head|body)\b') { 'FORMAT: html'; return }
    $format = 'uri-list'
    if ($Text -notmatch '(?m)^\s*[a-z][a-z0-9+.-]*://') {
        # Detect structural formats without printing any response fragment.
        if ($Text.StartsWith('{') -or $Text.StartsWith('[')) { 'FORMAT: json-like-not-uri-list'; return }
        if ($Text -match '(?m)^\s*(proxies|proxy-groups|mixed-port|port)\s*:') { 'FORMAT: yaml-like-not-uri-list'; return }
        try {
            $encoded = ($Text -replace '\s','').Replace('-','+').Replace('_','/')
            $encoded = $encoded.PadRight($encoded.Length + ((4 - $encoded.Length % 4) % 4),'=')
            $utf8 = New-Object Text.UTF8Encoding($false,$true)
            $Text = $utf8.GetString([Convert]::FromBase64String($encoded)).Trim().TrimStart([char]0xFEFF)
            $format = 'base64'
        } catch { 'FORMAT: neither-uri-list-nor-valid-base64-utf8'; return }
        if ($Text -match '<\s*(!doctype|html|head|body)\b') { 'FORMAT: base64-html'; return }
        if ($Text.StartsWith('{') -or $Text.StartsWith('[')) { 'FORMAT: base64-json-like-not-uri-list'; return }
    }
    $lines = @($Text -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($lines.Count -gt 4096) { 'FORMAT: too-many-entries'; return }
    'FORMAT: ' + $format
    $accepted = 0; $reasons = @{}; $shapes = @{}
    foreach ($line in $lines) {
        try { $null = Convert-Vless $line; $accepted++ }
        catch {
            $code = 'unclassified-parser-error'
            if ($reasonCodes.ContainsKey($_.Exception.Message)) { $code = $reasonCodes[$_.Exception.Message] }
            else {
                $exception = $_.Exception
                for ($i=0; $i -lt 10 -and $exception.InnerException; $i++) { $exception = $exception.InnerException }
                if ($exception -is [UriFormatException]) { $code = 'uri-format' }
                elseif ($exception -is [FormatException]) { $code = 'scalar-format' }
                elseif ($exception -is [System.Management.Automation.ParameterBindingException]) { $code = 'powershell-binding' }
            }
            if (-not $reasons.ContainsKey($code)) { $reasons[$code] = 0 }; $reasons[$code]++
            $shape = @{ type = 'unspecified'; security = 'unspecified'; fp = 'unspecified' }
            try {
                $uri = $null
                if ([Uri]::TryCreate($line,[UriKind]::Absolute,[ref]$uri)) {
                    foreach ($pair in $uri.Query.TrimStart('?').Split('&')) {
                        $kv = $pair.Split('=',2)
                        if ($kv.Count -ne 2) { continue }
                        $key = [Uri]::UnescapeDataString($kv[0])
                        if ($key -notin @('type','security','fp')) { continue }
                        $value = [Uri]::UnescapeDataString($kv[1])
                        $shape[$key] = 'other'
                        foreach ($allowed in @('tcp','raw','ws','grpc','xhttp','httpupgrade','tls','reality','none','chrome','firefox','safari','edge','random','randomized','unsafe')) {
                            if ($value -ceq $allowed) { $shape[$key] = $allowed; break }
                        }
                    }
                }
            } catch { }
            $label = 'type=' + $shape.type + ';security=' + $shape.security + ';fp=' + $shape.fp
            if (-not $shapes.ContainsKey($label)) { $shapes[$label] = 0 }; $shapes[$label]++
        }
    }
    'ENTRIES: ' + $lines.Count + '; supported=' + $accepted + '; skipped=' + ($lines.Count-$accepted)
    foreach ($key in @($reasons.Keys | Sort-Object)) { 'REJECT: ' + $key + '; count=' + $reasons[$key] }
    foreach ($key in @($shapes.Keys | Sort-Object)) { 'SHAPE: ' + $key + '; count=' + $shapes[$key] }
}
