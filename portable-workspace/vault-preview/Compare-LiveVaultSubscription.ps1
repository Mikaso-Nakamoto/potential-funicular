#requires -Version 5.1
[CmdletBinding()]
param([string]$Root = 'Z:\Iran\Browser\Working-Vault-Preview\WorkingRuntime')
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Use 64-bit Windows PowerShell 5.1.' }
. (Join-Path $PSScriptRoot 'VaultRefresh.Common.ps1')
. (Join-Path $PSScriptRoot 'VaultRefresh.Diagnostics.ps1')
$lock = $null; $password = $null; $document = $null; $url = $null; $hwid = $null; $uri = $null; $body = $null
$oldTemp = $env:TEMP; $oldTmp = $env:TMP; $phase = 'preflight'
function Read-ComparisonSecret([string]$Prompt) {
    $secret = Read-Host $Prompt -AsSecureString
    $ptr = [IntPtr]::Zero
    try {
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        if ($ptr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
        $secret.Dispose()
    }
}
try {
    $Root = Get-Workspace $Root
    $lock = [IO.File]::Open((Join-Path $Root '.session.lock'),'OpenOrCreate','ReadWrite','None')
    if (Test-ProfileBusy (Join-Path $Root 'private\profile')) { throw 'Profile busy.' }
    $tmp = Join-Path $Root 'private\tmp'
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $env:TEMP = $tmp; $env:TMP = $tmp
    $phase = 'unlock'
    $password = Read-Host 'Vault passphrase (hidden)' -AsSecureString
    $path = Join-Path $Root 'private\workspace.vault'
    $before = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $document = Read-Vault $path $password
    $phase = 'reference-input'
    Write-Host 'Use the full subscription URL and actual bound device UUID from the Inci instance that updates successfully NOW. Do not generate a UUID or use an unrelated Windows device ID.'
    $url = Read-ComparisonSecret 'Working Inci full HTTPS subscription URL (hidden)'
    if (-not [Uri]::TryCreate($url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Fragment) { throw 'Unsupported URL.' }
    $hwid = Convert-DeviceHwid (Read-ComparisonSecret 'Working Inci existing HWID UUID (hidden)')
    $urlSame = [string]::Equals(([Uri]$document.subscription.url).AbsoluteUri,$uri.AbsoluteUri,[StringComparison]::Ordinal)
    $hwidSame = [string]::Equals((Convert-DeviceHwid $document.subscription.hwid),$hwid,[StringComparison]::Ordinal)
    if ($urlSame) { Write-Host 'URL: MATCH (canonical request URI)' } else { Write-Host 'URL: DIFFERENT' }
    if ($hwidSame) { Write-Host 'HWID: MATCH' } else { Write-Host 'HWID: DIFFERENT' }
    Write-Warning 'Live GET uses v2rayNG User-Agent and x-hwid through current Windows connection/system proxy, not Inci network stack. Values and response are never saved. Vault will NOT be modified.'
    # Always test the freshly supplied reference. When metadata match, do not issue a duplicate request.
    $phase = 'reference-fetch'
    $body = Get-SubscriptionText -Uri $uri -DeviceHwid $hwid
    Write-Host 'REFERENCE RESPONSE (fresh Inci metadata; Windows/v2rayNG request):'
    $phase = 'reference-diagnose'
    Get-RefreshResponseDiagnostics $body
    $body = $null
    if (-not ($urlSame -and $hwidSame)) {
        $phase = 'stored-fetch'
        $body = Get-SubscriptionText -Uri ([Uri]$document.subscription.url) -DeviceHwid $document.subscription.hwid
        Write-Host 'STORED RESPONSE (current vault metadata; same Windows/v2rayNG request):'
        $phase = 'stored-diagnose'
        Get-RefreshResponseDiagnostics $body
    }
    $phase = 'unchanged-check'
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $before) { throw 'Vault changed externally.' }
    Write-Host 'READ-ONLY: vault ciphertext unchanged. No metadata/config/response saved; no Xray/browser started.'
    Write-Host 'LIMIT: this compares metadata and Windows requests, not the full Inci request headers, TLS fingerprint or network route. A matching URL/HWID does not establish identical requests.'
} catch {
    throw ('Live comparison stopped at: ' + $phase + '. Details suppressed; do not share secrets.')
} finally {
    if ($password) { $password.Dispose() }
    $document = $null; $url = $null; $hwid = $null; $uri = $null; $body = $null
    $env:TEMP = $oldTemp; $env:TMP = $oldTmp
    if ($lock) { $lock.Dispose() }
}
