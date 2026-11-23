#requires -Version 5.1
[CmdletBinding()]
param([string]$Root = '', [switch]$ValidateOnly)
# Resolve the location in the script body, not in a parameter default expression.
$scriptDirectory = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDirectory)) {
    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if ([string]::IsNullOrWhiteSpace($scriptDirectory)) { throw 'Cannot determine script location. Run the saved PS1 file with -File.' }
if ([string]::IsNullOrWhiteSpace($Root)) { throw 'Explicit encrypted Root required.' }
. (Join-Path (Split-Path -Parent $scriptDirectory) 'Workspace.Common.ps1')
. (Join-Path (Split-Path -Parent $scriptDirectory) 'vault-preview\Vault.Common.ps1')
. (Join-Path $scriptDirectory 'Native.Common.ps1')
. (Join-Path $scriptDirectory 'Bootstrap.Common.ps1')
Assert-VicaPlatform
$Root = Get-Workspace $Root
$lock = $null; $xray = $null; $browser = $null
$oldTemp = $env:TEMP; $oldTmp = $env:TMP; $oldKeyLog = $env:SSLKEYLOGFILE
$browserExe = $null; $password = $null; $document = $null; $configObject = $null; $browserLaunchAttempted = $false
$phase = 'preflight'
function Test-SessionBrowser {
    if ($browser -and -not $browser.HasExited) { return $true }
    if (Test-ProfileBusy $profileDir) { return $true }
    # Conservative: retain lock for all processes from this browser installation, including children.
    $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'librewolf.exe'" -ErrorAction Stop)
    foreach ($process in $processes) {
        if (-not $process.ExecutablePath -or $process.ExecutablePath -eq $browserExe) { return $true }
    }
    return $false
}
try {
    $lock = [IO.File]::Open((Join-Path $Root '.session.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    $vault = Join-Path $Root 'private\workspace.vault'
    if (-not (Test-Path -LiteralPath $vault -PathType Leaf)) { throw 'Encrypted vault required. No plaintext fallback; no configuration was launched.' }
    $profileDir = Join-Path $Root 'private\profile'
    if (Test-ProfileBusy $profileDir) { throw 'Close the managed browser before unlocking the vault.' }
    $tmp = Join-Path $Root 'private\tmp'
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $env:TEMP = $tmp; $env:TMP = $tmp
    $phase = 'crypto-unlock'
    Initialize-VaultCrypto
    $password = Read-Host 'Vault passphrase (hidden)' -AsSecureString
    try {
        $document = Read-Vault $vault $password
        $configObject = $document.activeConfig
    } finally {
        if ($password) { $password.Dispose(); $password = $null }
        $document = $null
    }
    $exe = Join-Path $Root 'Xray\xray.exe'
    $phase = 'native-validation'
    Assert-VicaXray $Root
    Test-XrayObjectInMemory $exe $configObject
    if ($ValidateOnly) {
        Write-Host 'PASS: vault authenticated, configuration policy checked, Xray accepted config through stdin. No tunnel or browser launched.' -ForegroundColor Green
        return
    }
    if (@(Get-NetTCPConnection -State Listen -LocalPort 17890 -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Port 17890 is occupied. Nothing was launched.' }
    $binaries = @(Get-ChildItem -LiteralPath (Join-Path $Root 'LibreWolf') -Filter librewolf.exe -Recurse -File)
    if ($binaries.Count -ne 1) { throw 'Expected one LibreWolf binary.' }
    $browserExe = $binaries[0].FullName
    $phase = 'browser-signature'
    $signature = Get-AuthenticodeSignature -LiteralPath $browserExe
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false) -cne 'OSSign (Scheibling Consulting AB)') { throw 'Official LibreWolf publisher required. No bypass.' }
    $profileDir = Join-Path $Root 'private\profile'
    $marker = Join-Path $profileDir '.workspace-profile'
    if ((Test-Path -LiteralPath $profileDir) -and -not (Test-Path -LiteralPath $marker)) { throw 'Unmanaged profile folder; refusing to alter it.' }
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    if (-not (Test-Path -LiteralPath $marker)) { [IO.File]::WriteAllText($marker, 'Managed portable profile') }
    if (Test-ProfileBusy $profileDir) { throw 'Profile is already in use.' }
    $tmp = Join-Path $Root 'private\tmp'
    $downloads = Join-Path $Root 'private\downloads'
    New-Item -ItemType Directory -Path $tmp, $downloads -Force | Out-Null
    $env:TEMP = $tmp; $env:TMP = $tmp
    $prefs = @'
// Managed on each launch. Do not use this profile outside managed workspace launchers.
user_pref("network.proxy.type", 1);
user_pref("network.proxy.socks", "127.0.0.1");
user_pref("network.proxy.socks_port", 17890);
user_pref("network.proxy.socks_version", 5);
user_pref("network.proxy.socks_remote_dns", true);
user_pref("network.proxy.no_proxies_on", "");
user_pref("network.proxy.allow_hijacking_localhost", true);
user_pref("network.proxy.failover_direct", false);
user_pref("network.proxy.autoconfig_url", "");
user_pref("network.proxy.http", "");
user_pref("network.proxy.ssl", "");
user_pref("network.trr.mode", 5);
user_pref("network.dns.disablePrefetch", true);
user_pref("network.prefetch-next", false);
user_pref("network.http.speculative-parallel-limit", 0);
user_pref("network.predictor.enabled", false);
user_pref("network.captive-portal-service.enabled", false);
user_pref("network.connectivity-service.enabled", false);
user_pref("network.http.http3.enable", false);
user_pref("media.peerconnection.enabled", false);
user_pref("browser.cache.disk.enable", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("signon.rememberSignons", false);
user_pref("browser.startup.page", 0);
user_pref("browser.startup.homepage", "about:blank");
'@
    $prefs += "`r`n" + 'user_pref("browser.download.folderList", 2);' + "`r`n"
    $prefs += 'user_pref("browser.download.useDownloadDir", true);' + "`r`n"
    $prefs += 'user_pref("browser.download.dir", ' + (ConvertTo-Json -InputObject $downloads -Compress) + ');' + "`r`n"
    [IO.File]::WriteAllText((Join-Path $profileDir 'user.js'), $prefs, (New-Object Text.UTF8Encoding($false)))
    # Keep ownership before sending credentials, including failures during delivery.
    $phase = 'contained-tunnel'
    $xray = Open-XrayRunSession $exe $configObject
    Send-XrayRunConfig $xray $configObject
    $configObject = $null
    $ready = $false
    for ($i=0; $i -lt 50; $i++) {
        if ($xray.HasFailed -or $xray.HasExited) { throw 'Xray exited before opening SOCKS.' }
        $listeners = @(Get-NetTCPConnection -State Listen -LocalPort 17890 -ErrorAction SilentlyContinue | Where-Object { $_.OwningProcess -eq $xray.Id -and $_.LocalAddress -eq '127.0.0.1' })
        if ($listeners.Count -gt 0) { $ready = $true; break }
        Start-Sleep -Milliseconds 200
    }
    if (-not $ready) { throw 'Could not verify the SOCKS listener owned by this Xray instance.' }
    Write-Host 'SOCKS is listening; remote connectivity is NOT yet verified.'
    Write-Host 'Keep this window open. Close LibreWolf normally to end the session.'
    Write-Host 'Do not sign in until IP/DNS and tunnel-disconnect tests pass.'
    Write-Warning 'Browser profile/downloads and old plaintext copies are NOT encrypted. Jobs are not a system network kill switch.'
    $phase = 'browser-session'
    $browserLaunchAttempted = $true
    # Do not pass optional TLS key logging into the browser either.
    $env:SSLKEYLOGFILE = $null
    $browser = Start-Process -FilePath $binaries[0].FullName -ArgumentList @('-wait-for-browser','-no-remote','-new-instance','-profile', ('"' + $profileDir + '"'), 'about:blank') -WorkingDirectory $profileDir -PassThru
    Start-Sleep -Seconds 3
    $warned = $false
    while (Test-SessionBrowser) {
        if (($xray.HasFailed -or $xray.HasExited) -and -not $warned) {
            Write-Warning 'Xray stopped. Close LibreWolf normally. Session lock is retained until the browser exits.'
            $warned = $true
        }
        Start-Sleep -Seconds 1
    }
} catch {
    throw ('VIC-A launch stopped at: ' + $phase + '. Details suppressed; no plaintext fallback.')
} finally {
    try {
        if ($browserLaunchAttempted) {
            # Also retain the lock if a monitoring error interrupted the normal loop.
            # On inspection failure, fail closed: keep waiting instead of declaring the profile free.
            $waiting = $true
            while ($waiting) {
                try { $waiting = Test-SessionBrowser }
                catch { $waiting = $true; Write-Warning 'Cannot inspect browser processes. Close LibreWolf; lock remains held. Forced shell exit is not managed cleanup.' }
                if ($waiting) { Start-Sleep -Seconds 1 }
            }
        }
        Stop-VicaNative $xray
    } finally {
        $configObject = $null; $document = $null
        if ($password) { $password.Dispose() }
        $env:TEMP = $oldTemp; $env:TMP = $oldTmp; $env:SSLKEYLOGFILE = $oldKeyLog
        if ($lock) { $lock.Dispose() }
    }
}
