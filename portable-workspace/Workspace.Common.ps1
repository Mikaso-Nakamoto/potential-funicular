#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Get-Workspace([string]$Root) {
    $r = [IO.Path]::GetFullPath($Root)
    if (-not (Test-Path -LiteralPath (Join-Path $r 'Xray\xray.exe'))) { throw 'Xray installation not found.' }
    return $r
}
function Convert-Vless([string]$Link) {
    $u = $null
    if (-not [Uri]::TryCreate($Link, [UriKind]::Absolute, [ref]$u) -or $u.Scheme -ne 'vless') { throw 'Not a VLESS URI.' }
    $id = [Uri]::UnescapeDataString($u.UserInfo)
    $uuid = [Guid]::Empty
    if (-not [Guid]::TryParse($id, [ref]$uuid)) { throw 'VLESS UUID required.' }
    if ($uuid -eq [Guid]::Empty) { throw 'Zero UUID is prohibited.' }
    if ($u.Port -lt 1 -or $u.Port -gt 65535 -or -not $u.Host) { throw 'Explicit server and port required.' }
    if ($u.AbsolutePath -notin @('', '/')) { throw 'Unexpected URI path.' }
    $q = @{}
    foreach ($pair in $u.Query.TrimStart('?').Split('&')) {
        if (-not $pair) { continue }
        $kv = $pair.Split('=', 2)
        if ($kv.Count -ne 2) { throw 'Invalid query parameter.' }
        $k = [Uri]::UnescapeDataString($kv[0])
        if ($q.ContainsKey($k)) { throw 'Duplicate parameter.' }
        $q[$k] = [Uri]::UnescapeDataString($kv[1])
    }
    $allowed = @('encryption','security','type','flow','sni','fp','alpn','pbk','sid','spx','path','host','allowInsecure','headerType')
    foreach ($k in $q.Keys) { if ($k -notin $allowed) { throw 'Unsupported query parameter.' } }
    if ($q.ContainsKey('allowInsecure') -and $q.allowInsecure -notin @('0','false')) { throw 'Insecure TLS is prohibited.' }
    if ($q.ContainsKey('encryption') -and $q.encryption -ne 'none') { throw 'Unsupported VLESS encryption.' }
    $security = 'none'; if ($q.ContainsKey('security')) { $security = $q.security }
    if ($security -notin @('tls','reality')) { throw 'Only TLS or REALITY is supported.' }
    $network = 'tcp'; if ($q.ContainsKey('type')) { $network = $q.type }
    if ($network -eq 'raw') { $network = 'tcp' }
    if ($network -notin @('tcp','ws')) { throw 'Only TCP/RAW or WebSocket is supported.' }
    if ($security -eq 'reality' -and $network -ne 'tcp') { throw 'REALITY is supported only over TCP here.' }
    if ($q.ContainsKey('headerType') -and ($network -ne 'tcp' -or $q.headerType -ne 'none')) { throw 'Unsupported headerType.' }
    $user = @{ id = $uuid.ToString(); encryption = 'none' }
    if ($q.ContainsKey('flow') -and $q.flow) {
        if ($q.flow -ne 'xtls-rprx-vision' -or $network -ne 'tcp') { throw 'Unsupported flow.' }
        $user.flow = $q.flow
    }
    $stream = @{ network = $network; security = $security }
    $tls = @{ serverName = $u.DnsSafeHost; fingerprint = 'chrome' }
    if ($q.ContainsKey('sni') -and $q.sni) { $tls.serverName = $q.sni }
    if ($q.ContainsKey('fp') -and $q.fp) { $tls.fingerprint = $q.fp }
    Assert-Fingerprint $tls.fingerprint
    if ($security -eq 'reality') {
        if (-not $q.ContainsKey('pbk') -or -not $q.pbk) { throw 'REALITY public key missing.' }
        if ($q.ContainsKey('alpn')) { throw 'REALITY ALPN parameter is not supported here.' }
        Assert-RealityKey $q.pbk
        if (-not $q.ContainsKey('sni') -or -not $q.sni) { throw 'Explicit REALITY SNI is required.' }
        $tls.password = $q.pbk
        $tls.shortId = ''; if ($q.ContainsKey('sid')) { $tls.shortId = $q.sid }
        Assert-ShortId $tls.shortId
        if ($q.ContainsKey('spx')) { $tls.spiderX = $q.spx }
        $stream.realitySettings = $tls
    } else {
        foreach ($k in @('pbk','sid','spx')) { if ($q.ContainsKey($k)) { throw 'REALITY parameters on TLS URI.' } }
        $tls.allowInsecure = $false
        $tls.minVersion = '1.2'
        if ($q.ContainsKey('alpn') -and $q.alpn) { $tls.alpn = @($q.alpn.Split(',')) }
        $stream.tlsSettings = $tls
    }
    if ($network -eq 'ws') {
        $ws = @{ path = '/' }
        if ($q.ContainsKey('path') -and $q.path) { $ws.path = $q.path }
        if ($q.ContainsKey('host') -and $q.host) { $ws.host = $q.host }
        $stream.wsSettings = $ws
    } else {
        foreach ($k in @('path','host')) { if ($q.ContainsKey($k)) { throw 'WebSocket parameters on TCP URI.' } }
    }
    return @{ tag = 'tunnel'; protocol = 'vless'; settings = @{ vnext = @(@{ address = $u.DnsSafeHost.Trim('[',']'); port = $u.Port; users = @($user) }) }; streamSettings = $stream }
}
function Test-XrayConfig([string]$Exe, [string]$Config) {
    Assert-ConfigPolicy $Config
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = 'run -test -config "' + $Config + '"'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = $null
    try {
        $p = [Diagnostics.Process]::Start($psi)
        $stdout = $p.StandardOutput.ReadToEndAsync()
        $stderr = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit(30000)) {
            $p.Kill()
            $p.WaitForExit()
            throw 'Xray config test timed out.'
        }
        # Drain both pipes concurrently. Neither output is routed through PowerShell's error stream.
        $null = $stdout.GetAwaiter().GetResult()
        $null = $stderr.GetAwaiter().GetResult()
        if ($p.ExitCode -ne 0) { throw 'Xray rejected the configuration.' }
    } catch { throw 'Xray config test failed or timed out. Diagnostics suppressed to protect secrets.' }
    finally { if ($p) { $p.Dispose() } }
}
function Get-SubscriptionText([Uri]$Uri) {
    $response = $null; $stream = $null; $memory = $null
    $oldProtocols = [Net.ServicePointManager]::SecurityProtocol
    $oldRevocation = [Net.ServicePointManager]::CheckCertificateRevocationList
    try {
        if ($Uri.Scheme -ne 'https') { throw 'HTTPS required.' }
        if ($null -ne [Net.ServicePointManager]::ServerCertificateValidationCallback) { throw 'Custom certificate validation callback is prohibited.' }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        [Net.ServicePointManager]::CheckCertificateRevocationList = $true
        $request = [Net.HttpWebRequest]::Create($Uri)
        $request.CheckCertificateRevocationList = $true
        $request.Method = 'GET'
        $request.UserAgent = 'v2rayNG'
        $request.Accept = 'text/plain'
        $request.AllowAutoRedirect = $false
        $request.Timeout = 45000
        $request.ReadWriteTimeout = 15000
        $request.AutomaticDecompression = [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
        $response = $request.GetResponse()
        if ([int]$response.StatusCode -ne 200) { throw 'Unexpected HTTP status.' }
        $limit = 4194304
        if ($response.ContentLength -gt $limit) { throw 'Response too large.' }
        $stream = $response.GetResponseStream()
        $memory = New-Object IO.MemoryStream
        $buffer = New-Object byte[] 8192
        $watch = [Diagnostics.Stopwatch]::StartNew()
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if ($watch.Elapsed.TotalSeconds -gt 45 -or ($memory.Length + $read) -gt $limit) { throw 'Response limit exceeded.' }
            $memory.Write($buffer, 0, $read)
        }
        return [Text.Encoding]::UTF8.GetString($memory.ToArray()).Trim().TrimStart([char]0xFEFF)
    } catch { throw 'Subscription fetch failed (HTTP, redirect, TLS, timeout or 4 MiB limit). URL and body suppressed.' }
    finally {
        if ($stream) { $stream.Dispose() }
        if ($memory) { $memory.Dispose() }
        if ($response) { $response.Close() }
        [Net.ServicePointManager]::SecurityProtocol = $oldProtocols
        [Net.ServicePointManager]::CheckCertificateRevocationList = $oldRevocation
    }
}
function Test-ProfileBusy([string]$ProfileDir) {
    $file = Join-Path $ProfileDir 'parent.lock'
    if (-not (Test-Path -LiteralPath $file)) { return $false }
    $handle = $null
    try { $handle = [IO.File]::Open($file, 'Open', 'ReadWrite', 'None'); return $false }
    catch { return $true }
    finally { if ($handle) { $handle.Dispose() } }
}

function Assert-Fingerprint([string]$Value) {
    if ($Value -notin @('chrome','firefox','safari','edge')) { throw 'Unsupported TLS fingerprint.' }
}
function Assert-RealityKey([string]$Value) {
    if ($Value -cnotmatch '^[A-Za-z0-9_-]{43}$') { throw 'Invalid REALITY key encoding.' }
    try { $bytes = [Convert]::FromBase64String($Value.Replace('-','+').Replace('_','/') + '=') }
    catch { throw 'Invalid REALITY key encoding.' }
    $canonical = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
    if ($bytes.Length -ne 32 -or $canonical -cne $Value -or @($bytes | Where-Object { $_ -ne 0 }).Count -eq 0) { throw 'Invalid REALITY key.' }
    # Shape/canonical encoding only. X25519 peer validation remains the responsibility of Xray/REALITY.
}
function Assert-ShortId([string]$Value) {
    if ($Value -cnotmatch '^(?:[0-9a-fA-F]{2}){0,8}$') { throw 'Invalid REALITY short ID.' }
}
function Assert-Fields($Object, [string[]]$Allowed, [string[]]$Required = @()) {
    if ($null -eq $Object -or $Object -isnot [pscustomobject]) { throw 'Expected JSON object.' }
    foreach ($property in $Object.PSObject.Properties) {
        if ($property.Name -notin $Allowed) { throw 'Unexpected configuration field.' }
    }
    foreach ($name in $Required) {
        if ($name -notin @($Object.PSObject.Properties.Name)) { throw 'Required configuration field missing.' }
    }
}
function Assert-ConfigPolicy([string]$Path) {
    try {
        $c = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
        Assert-Fields $c @('log','inbounds','outbounds') @('log','inbounds','outbounds')
        Assert-Fields $c.log @('loglevel') @('loglevel')
        if ($c.log.loglevel -cne 'none' -or @($c.inbounds).Count -ne 1 -or @($c.outbounds).Count -ne 1) { throw 'Invalid topology.' }
        $i = $c.inbounds[0]
        Assert-Fields $i @('tag','listen','port','protocol','settings') @('listen','port','protocol','settings')
        Assert-Fields $i.settings @('auth','udp') @('auth','udp')
        if ($i.listen -cne '127.0.0.1' -or $i.port -ne 17890 -or $i.protocol -cne 'socks' -or $i.settings.auth -cne 'noauth' -or $i.settings.udp -isnot [bool] -or $i.settings.udp) { throw 'Invalid listener.' }
        $o = $c.outbounds[0]
        Assert-Fields $o @('tag','protocol','settings','streamSettings') @('protocol','settings','streamSettings')
        if ($o.protocol -cne 'vless') { throw 'Only VLESS allowed.' }
        Assert-Fields $o.settings @('vnext') @('vnext')
        if (@($o.settings.vnext).Count -ne 1) { throw 'Invalid servers.' }
        $v = $o.settings.vnext[0]
        Assert-Fields $v @('address','port','users') @('address','port','users')
        if (-not $v.address -or $v.port -lt 1 -or $v.port -gt 65535 -or @($v.users).Count -ne 1) { throw 'Invalid server.' }
        $u = $v.users[0]; $id = [Guid]::Empty
        Assert-Fields $u @('id','encryption','flow') @('id','encryption')
        if (-not [Guid]::TryParse($u.id, [ref]$id) -or $id -eq [Guid]::Empty -or $u.encryption -cne 'none') { throw 'Invalid user.' }
        $t = $o.streamSettings
        Assert-Fields $t @('network','security','tlsSettings','realitySettings','wsSettings') @('network','security')
        if ($t.network -notin @('tcp','ws') -or $t.security -notin @('tls','reality')) { throw 'Unprotected transport.' }
        if ('flow' -in @($u.PSObject.Properties.Name) -and ($u.flow -cne 'xtls-rprx-vision' -or $t.network -cne 'tcp')) { throw 'Unsupported flow.' }
        if ($t.security -ceq 'tls') {
            if ('realitySettings' -in @($t.PSObject.Properties.Name)) { throw 'Mixed security settings.' }
            $tls = $t.tlsSettings
            Assert-Fields $tls @('serverName','fingerprint','allowInsecure','minVersion','alpn') @('serverName','fingerprint','allowInsecure','minVersion')
            if (-not $tls.serverName -or $tls.allowInsecure -isnot [bool] -or $tls.allowInsecure -or $tls.minVersion -cne '1.2') { throw 'Unsafe TLS settings.' }
            Assert-Fingerprint $tls.fingerprint
        } else {
            if ($t.network -cne 'tcp' -or 'tlsSettings' -in @($t.PSObject.Properties.Name)) { throw 'Invalid REALITY transport.' }
            $r = $t.realitySettings
            Assert-Fields $r @('serverName','fingerprint','password','shortId','spiderX') @('serverName','fingerprint','password','shortId')
            if (-not $r.serverName) { throw 'REALITY SNI required.' }
            Assert-Fingerprint $r.fingerprint
            Assert-RealityKey $r.password
            Assert-ShortId $r.shortId
        }
        if ($t.network -ceq 'ws') { Assert-Fields $t.wsSettings @('path','host') @('path') }
        elseif ('wsSettings' -in @($t.PSObject.Properties.Name)) { throw 'Unexpected WebSocket settings.' }
    } catch { throw 'Configuration violates the local TLS/tunnel policy. Regenerate it using Update-Subscription.ps1. Details suppressed.' }
}
