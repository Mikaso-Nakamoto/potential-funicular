#requires -Version 5.1
[CmdletBinding()]
param([string]$Root = '')
$ErrorActionPreference = 'Stop'
$scriptDirectory = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDirectory)) { $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path }
if ([string]::IsNullOrWhiteSpace($scriptDirectory)) { throw 'Run the saved PS1 with -File.' }
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Join-Path $scriptDirectory 'Runtime' }
. (Join-Path $scriptDirectory 'Workspace.Common.ps1')
$Root = Get-Workspace $Root
$private = Join-Path $Root 'private'
New-Item -ItemType Directory -Path $private -Force | Out-Null
$lock = $null; $candidate = $null; $secureId = $null; $ptr = [IntPtr]::Zero
try {
    $lock = [IO.File]::Open((Join-Path $Root '.session.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    if (Test-ProfileBusy (Join-Path $private 'profile')) { throw 'Close LibreWolf before changing configuration.' }
    Write-Host 'Manual VLESS setup. Copy ALL values from your working node, not the subscription URL.'
    Write-Host 'UUID and GUID are the same identifier here. No network request is made by this setup script.'
    $secureId = Read-Host 'UUID / GUID (hidden)' -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureId)
    $idText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr).Trim()
    $id = [Guid]::Empty
    if (-not [Guid]::TryParse($idText, [ref]$id) -or $id -eq [Guid]::Empty) { throw 'A valid, nonzero UUID is required.' }
    $serverAddress = (Read-Host 'Server address: IP or hostname, WITHOUT https:// or port').Trim().Trim('[',']')
    if ([Uri]::CheckHostName($serverAddress) -eq [UriHostNameType]::Unknown) { throw 'Invalid server address.' }
    $port = 0
    if (-not [int]::TryParse((Read-Host 'Server port'), [ref]$port) -or $port -lt 1 -or $port -gt 65535) { throw 'Invalid server port.' }
    $security = (Read-Host 'Security from working node: tls or reality').Trim().ToLowerInvariant()
    if ($security -notin @('tls','reality')) { throw 'Only TLS/REALITY is supported. Do not invent security settings for a security=none server.' }
    $network = (Read-Host 'Transport from working node: tcp or ws').Trim().ToLowerInvariant()
    if ($network -notin @('tcp','ws') -or ($security -eq 'reality' -and $network -ne 'tcp')) { throw 'Supported: TLS over TCP/WS, REALITY over TCP.' }
    $sni = (Read-Host 'SNI / serverName from working node').Trim()
    if ([Uri]::CheckHostName($sni) -eq [UriHostNameType]::Unknown) { throw 'A valid explicit SNI/serverName is required.' }
    $fingerprint = (Read-Host 'Fingerprint: chrome/firefox/safari/edge (Enter = chrome)').Trim()
    if (-not $fingerprint) { $fingerprint = 'chrome' }
    Assert-Fingerprint $fingerprint
    $flow = (Read-Host 'Flow: Enter for empty, or xtls-rprx-vision if specified by provider').Trim()
    $query = [ordered]@{ encryption = 'none'; security = $security; type = $network; sni = $sni; fp = $fingerprint }
    if ($flow) { $query.flow = $flow }
    if ($security -eq 'reality') {
        $query.pbk = (Read-Host 'REALITY PUBLIC key / pbk (NOT a server private key)').Trim()
        Assert-RealityKey $query.pbk
        $query.sid = (Read-Host 'REALITY short ID / sid (Enter if explicitly empty)').Trim()
        Assert-ShortId $query.sid
    }
    if ($network -eq 'ws') {
        $query.path = Read-Host 'WebSocket path exactly as in working node (Enter = /)'
        if (-not $query.path) { $query.path = '/' }
        $wsHost = (Read-Host 'WebSocket Host header (Enter if absent)').Trim()
        if ($wsHost) { $query.host = $wsHost }
    }
    if ($security -eq 'tls') {
        $alpn = (Read-Host 'ALPN comma-separated, only if specified (Enter = default)').Trim()
        if ($alpn) { $query.alpn = $alpn }
    }
    $authority = $serverAddress
    if ($serverAddress.Contains(':')) { $authority = '[' + $serverAddress + ']' }
    $pairs = @($query.GetEnumerator() | ForEach-Object { [Uri]::EscapeDataString([string]$_.Key) + '=' + [Uri]::EscapeDataString([string]$_.Value) })
    $link = 'vless://' + $id.ToString() + '@' + $authority + ':' + $port + '?' + ($pairs -join '&')
    try { $outbound = Convert-Vless $link }
    catch { throw 'Manual parameters are unsupported or invalid. No configuration changed.' }
    $config = @{
        log = @{ loglevel = 'none' }
        inbounds = @(@{ tag = 'browser'; listen = '127.0.0.1'; port = 17890; protocol = 'socks'; settings = @{ auth = 'noauth'; udp = $false } })
        outbounds = @($outbound)
    }
    $candidate = Join-Path $private ('candidate-' + [Guid]::NewGuid().ToString('N') + '.json')
    [IO.File]::WriteAllText($candidate, ($config | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
    Test-XrayConfig (Join-Path $Root 'Xray\xray.exe') $candidate
    $active = Join-Path $private 'xray.json'
    if (Test-Path -LiteralPath $active) { [IO.File]::Replace($candidate, $active, $null) }
    else { [IO.File]::Move($candidate, $active) }
    Write-Host 'Manual configuration validated and saved. Remote connectivity has NOT been tested.'
    Write-Host 'Next: Start-Workspace.ps1. Test IP/DNS and tunnel failure before signing in.'
} finally {
    try {
        if ($ptr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
        if ($secureId) { $secureId.Dispose() }
        $idText = $null; $link = $null; $query = $null; $config = $null
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            try { Remove-Item -LiteralPath $candidate -Force }
            catch { Write-Warning 'Candidate cleanup failed; it contains credentials. Inspect private folder.' }
        }
    } finally { if ($lock) { $lock.Dispose() } }
}
