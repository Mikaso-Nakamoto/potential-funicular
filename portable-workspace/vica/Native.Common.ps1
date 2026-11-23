#requires -Version 5.1
$nativeDirectory = $PSScriptRoot
function Initialize-VicaNative {
    $source = Join-Path $nativeDirectory 'ContainedSession.cs'
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne '244f7e515e9243408107d9c89750b470cf4100c5bad8d7e63e0a3794e4205325') { throw 'Contained native helper integrity mismatch.' }
    if (-not ('VicaContained.Session' -as [type])) { Add-Type -TypeDefinition ([IO.File]::ReadAllText($source)) -ErrorAction Stop }
}
function Stop-VicaNative($Owner) {
    if ($null -eq $Owner) { return }
    while (-not $Owner.CleanupConfirmed) {
        try { $Owner.Dispose() } catch { Write-Warning 'Native cleanup error; retaining ownership and session lock.' }
        if (-not $Owner.CleanupConfirmed) { Write-Warning 'Waiting for contained children to exit. Do not force-close this window.'; Start-Sleep -Seconds 1 }
    }
}
function Test-XrayObjectInMemory([string]$Exe, $Config, [int]$TimeoutMs = 30000) {
    Initialize-VicaNative
    Assert-ConfigObjectPolicy $Config
    $bytes = $null; $validation = $null
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($Config | ConvertTo-Json -Depth 30 -Compress))
        $validation = [VicaContained.Session]::Open($Exe,(Split-Path -Parent $Exe),'test')
        $validation.Validate($bytes,$TimeoutMs)
    } catch { throw 'Contained Xray validation failed. Native diagnostics suppressed.' }
    finally {
        if ($bytes) { [Array]::Clear($bytes,0,$bytes.Length) }
        Stop-VicaNative $validation
    }
}
function Open-XrayRunSession([string]$Exe, $Config) {
    Initialize-VicaNative
    Assert-ConfigObjectPolicy $Config
    return [VicaContained.Session]::Open($Exe,(Split-Path -Parent $Exe),'run')
}
function Send-XrayRunConfig($Session, $Config) {
    Assert-ConfigObjectPolicy $Config
    $bytes = $null
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($Config | ConvertTo-Json -Depth 30 -Compress))
        $Session.Send($bytes,10000)
        if ($Session.HasFailed -or $Session.HasExited) { throw 'Xray exited.' }
    } finally { if ($bytes) { [Array]::Clear($bytes,0,$bytes.Length) } }
}
function Assert-VicaXray([string]$Root) {
    $exe = Join-Path $Root 'Xray\xray.exe'
    if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne '1ca7a2cf61ba2c5d20b21a80d405b57933939751081cb289f07bd8ddf7cc3185') { throw 'Xray differs from the official binary already tested. No bypass.' }
}
function Get-VicaCurl {
    $exe = Join-Path ([Environment]::SystemDirectory) 'curl.exe'
    $signature = Get-AuthenticodeSignature -LiteralPath $exe
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') { throw 'Valid Microsoft-signed System32 curl required.' }
    return $exe
}
function Escape-VicaCurl([string]$Value) {
    if ($Value -match '[\x00-\x1f\x7f]') { throw 'Control characters prohibited.' }
    return $Value.Replace('\','\\').Replace('"','\"')
}
function Get-VicaTunnelSubscription([string]$Root, $Document) {
    $xray = $null; $curl = $null; $requestBytes = $null; $response = $null; $request = $null; $text = $null
    try {
        Assert-VicaXray $Root
        $curlExe = Get-VicaCurl
        if (@(Get-NetTCPConnection -State Listen -LocalPort 17890 -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Port occupied; no process will be stopped.' }
        $exe = Join-Path $Root 'Xray\xray.exe'
        Test-XrayObjectInMemory $exe $Document.activeConfig
        $xray = Open-XrayRunSession $exe $Document.activeConfig
        Send-XrayRunConfig $xray $Document.activeConfig
        $ready = $false
        for ($i=0; $i -lt 50; $i++) {
            if ($xray.HasFailed -or $xray.HasExited) { throw 'Tunnel exited.' }
            $listeners = @(Get-NetTCPConnection -State Listen -LocalPort 17890 -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -eq '127.0.0.1' -and $_.OwningProcess -eq $xray.Id })
            if ($listeners.Count -eq 1) { $ready = $true; break }
            Start-Sleep -Milliseconds 200
        }
        if (-not $ready) { throw 'Owned listener not ready.' }
        $uri = [Uri]$Document.subscription.url
        $null = Convert-DeviceHwid $Document.subscription.hwid
        # Retain stored header text exactly; the working UUID was migrated, not generated.
        $request = @(
            'url = "' + (Escape-VicaCurl $uri.AbsoluteUri) + '"'
            'header = "User-Agent: INCY/3.0.28"'
            'header = "x-hwid: ' + (Escape-VicaCurl ([string]$Document.subscription.hwid)) + '"'
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
        $curl = [VicaContained.Session]::Open($curlExe,(Join-Path $Root 'private\tmp'),'curl')
        $response = $curl.Fetch($requestBytes)
        if ($xray.HasFailed -or $xray.HasExited) { throw 'Tunnel exited during request.' }
        $utf8 = New-Object Text.UTF8Encoding($false,$true)
        $text = $utf8.GetString($response)
        if ($text -notmatch '\nVICA_STATUS:200$') { throw 'Only direct HTTP200 accepted; redirects not followed.' }
        return $text.Substring(0,$text.LastIndexOf("`nVICA_STATUS:"))
    } finally {
        if ($requestBytes) { [Array]::Clear($requestBytes,0,$requestBytes.Length) }
        if ($response) { [Array]::Clear($response,0,$response.Length) }
        $request = $null; $text = $null
        Stop-VicaNative $curl
        Stop-VicaNative $xray
    }
}
