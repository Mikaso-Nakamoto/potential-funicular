#requires -Version 5.1
[CmdletBinding()]
param([string]$Root = 'Z:\Iran\Browser\Working-Vault-Preview\WorkingRuntime')
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Use 64-bit Windows PowerShell 5.1.' }
. (Join-Path $PSScriptRoot 'Vault.Common.ps1')
. (Join-Path $PSScriptRoot 'XrayPipe.Common.ps1')
. (Join-Path $PSScriptRoot 'VaultRefresh.Diagnostics.ps1')
$lock = $null; $password = $null; $document = $null; $xray = $null; $curl = $null
$config = $null; $requestBytes = $null; $response = $null; $text = $null; $request = $null; $uri = $null
$oldTemp = $env:TEMP; $oldTmp = $env:TMP; $phase = 'preflight'
function Escape-CurlValue([string]$Value) {
    if ($Value -match '[\x00-\x1f\x7f]') { throw 'Control characters prohibited.' }
    return $Value.Replace('\','\\').Replace('"','\"')
}
function Wait-OwnedCleanup($Handle,[string]$Name) {
    if ($null -eq $Handle) { return }
    try { $Handle.Dispose() } catch { Write-Warning ($Name + ' cleanup raised an error.') }
    if (-not $Handle.CleanupConfirmed) {
        Write-Warning ($Name + ' cleanup unconfirmed. Lock retained; do not force-close PowerShell. Forced exit is not managed cleanup.')
        while (-not $Handle.CleanupConfirmed) { Start-Sleep -Seconds 1 }
    }
}
try {
    $Root = Get-Workspace $Root
    $lock = [IO.File]::Open((Join-Path $Root '.session.lock'),'OpenOrCreate','ReadWrite','None')
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
    $phase = 'unlock'
    $password = Read-Host 'Vault passphrase (hidden)' -AsSecureString
    $path = Join-Path $Root 'private\workspace.vault'
    $before = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $document = Read-Vault $path $password
    $password.Dispose(); $password = $null
    $config = $document.activeConfig
    $uri = [Uri]$document.subscription.url
    $hwid = Convert-DeviceHwid $document.subscription.hwid
    $request = @(
        'url = "' + (Escape-CurlValue $uri.AbsoluteUri) + '"'
        'header = "User-Agent: INCY/3.0.28"'
        'header = "x-hwid: ' + $hwid + '"'
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
    $request = $null; $uri = $null; $hwid = $null; $document = $null
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
    Write-Host 'LIVE REQUEST: Windows curl + INCY/3.0.28 through this owned Xray SOCKS5h. Remote DNS; no direct fallback; no browser; vault is read-only.'
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
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $before) { throw 'Vault changed externally.' }
    Write-Host 'READ-ONLY: vault ciphertext unchanged. No response/config saved. Stopping owned curl and Xray now.'
} catch {
    throw ('Tunnel subscription check stopped at: ' + $phase + '. Details suppressed. Do not send secrets or raw response.')
} finally {
    if ($password) { $password.Dispose() }
    if ($requestBytes) { [Array]::Clear($requestBytes,0,$requestBytes.Length) }
    if ($response) { [Array]::Clear($response,0,$response.Length) }
    $document = $null; $config = $null; $request = $null; $text = $null; $uri = $null; $hwid = $null
    # Do not release session ownership until both native children confirm cleanup.
    Wait-OwnedCleanup $curl 'curl'
    Wait-OwnedCleanup $xray 'Xray'
    $env:TEMP = $oldTemp; $env:TMP = $oldTmp
    if ($lock) { $lock.Dispose() }
}
