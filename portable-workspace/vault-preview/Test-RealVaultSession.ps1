#requires -Version 5.1
[CmdletBinding()]
param([string]$InstalledRoot = 'Z:\Iran\Browser\Runtime', [switch]$ConfirmOfficialInstalledBinaries)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Use 64-bit Windows PowerShell 5.1.' }
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Workspace.Common.ps1')
. (Join-Path $PSScriptRoot 'Vault.Common.ps1')
$launcher = Join-Path (Split-Path -Parent $PSScriptRoot) 'Start-VaultWorkspace.ps1'
$stage = Join-Path $PSScriptRoot ('.real-session-' + [Guid]::NewGuid().ToString('N'))
$report = Join-Path $PSScriptRoot 'real-vault-session-report.txt'
$log = New-Object 'Collections.Generic.List[string]'
$owned = $false; $generated = $null; $password = $null
$oldTemp = $env:TEMP; $oldTmp = $env:TMP
$evidence = @{ xrayId = 0; browser = $null; greeted = $false }
function Note([string]$Text) { Write-Host $Text; $log.Add($Text) }
function Assert-BrowserSignature([string]$Path) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid') { throw 'LibreWolf Authenticode must be Valid. No bypass.' }
    $signer = $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false)
    if ($signer -cne 'OSSign (Scheibling Consulting AB)') { throw 'Unexpected LibreWolf publisher. No bypass.' }
}
function Assert-NoReparse([string]$Path) {
    foreach ($item in @((Get-Item -LiteralPath $Path -Force)) + @(Get-ChildItem -LiteralPath $Path -Recurse -Force)) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse points are not allowed in binary source trees.' }
    }
}
function Invoke-RealSession {
    # Only the password prompt is replaced. Browser creation is observed, then delegated to the real cmdlet.
    $promptPassword = $password
    $mock = { param([string]$Prompt,[switch]$AsSecureString)
        if (-not $AsSecureString) { throw 'Unexpected plaintext prompt.' }
        return $promptPassword.Copy()
    }.GetNewClosure()
    Set-Item -Path Function:Read-Host -Value $mock
    function Start-Process {
        param([string]$FilePath,[string[]]$ArgumentList,[string]$WorkingDirectory,[switch]$PassThru)
        if ($FilePath -ne $testBrowser) { throw 'Unexpected browser launch path.' }
        $listeners = @(Get-NetTCPConnection -State Listen -LocalPort 17890 -ErrorAction Stop | Where-Object { $_.LocalAddress -eq '127.0.0.1' })
        if ($listeners.Count -ne 1) { throw 'Expected one loopback SOCKS listener.' }
        $evidence.xrayId = [int]$listeners[0].OwningProcess
        if ((Get-Process -Id $evidence.xrayId -ErrorAction Stop).Path -ne $testXray) { throw 'SOCKS owner is not the staged Xray.' }
        $held = $false
        try { $h = [IO.File]::Open((Join-Path $stage '.session.lock'),'Open','ReadWrite','None'); $h.Dispose() }
        catch [IO.IOException] { $held = $true }
        if (-not $held) { throw 'Session lock was not held before browser creation.' }
        $client = New-Object Net.Sockets.TcpClient
        try {
            $client.ReceiveTimeout = 5000; $client.SendTimeout = 5000
            $connect = $client.ConnectAsync('127.0.0.1',17890)
            if (-not $connect.Wait(5000)) { throw 'SOCKS connect timeout.' }
            $stream = $client.GetStream()
            $hello = [byte[]]@(5,1,0); $stream.Write($hello,0,3)
            if ($stream.ReadByte() -ne 5 -or $stream.ReadByte() -ne 0) { throw 'Unexpected SOCKS5 greeting response.' }
            $evidence.greeted = $true
        } finally { $client.Close() }
        # Never sends CONNECT or an external destination to SOCKS.
        $process = Microsoft.PowerShell.Management\Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory -PassThru
        $evidence.browser = $process
        return $process
    }
    & $launcher -Root $stage
}
try {
    Note ('Real binary vault session; PS ' + $PSVersionTable.PSVersion + '; CLR ' + [Environment]::Version)
    if (-not $ConfirmOfficialInstalledBinaries) { throw 'Explicit confirmation of official installed binary sources is required.' }
    if (@(Get-CimInstance Win32_Process -Filter "Name = 'librewolf.exe'" -ErrorAction Stop).Count -gt 0) { throw 'Close all LibreWolf instances first.' }
    if (@(Get-NetTCPConnection -State Listen -LocalPort 17890 -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Port 17890 is occupied. No process will be stopped.' }
    foreach ($name in @('Xray','LibreWolf')) { Assert-NoReparse (Join-Path $InstalledRoot $name) }
    $sourceXray = Join-Path $InstalledRoot 'Xray\xray.exe'
    $expectedXray = '1ca7a2cf61ba2c5d20b21a80d405b57933939751081cb289f07bd8ddf7cc3185'
    if ((Get-FileHash -LiteralPath $sourceXray -Algorithm SHA256).Hash -ne $expectedXray) { throw 'Installed Xray differs from the previously tested binary. Review required; do not bypass.' }
    $browsers = @(Get-ChildItem -LiteralPath (Join-Path $InstalledRoot 'LibreWolf') -Recurse -File -Filter librewolf.exe)
    if ($browsers.Count -ne 1) { throw 'Expected one installed LibreWolf binary.' }
    Assert-BrowserSignature $browsers[0].FullName
    New-Item -ItemType Directory -Path $stage | Out-Null
    $owned = $true
    foreach ($name in @('Xray','LibreWolf')) { Copy-Item -LiteralPath (Join-Path $InstalledRoot $name) -Destination (Join-Path $stage $name) -Recurse }
    $testXray = Join-Path $stage 'Xray\xray.exe'
    $testBrowser = @(Get-ChildItem -LiteralPath (Join-Path $stage 'LibreWolf') -Recurse -File -Filter librewolf.exe)[0].FullName
    if ((Get-FileHash -LiteralPath $testXray -Algorithm SHA256).Hash -ne $expectedXray) { throw 'Staged Xray hash mismatch.' }
    Assert-BrowserSignature $testBrowser
    foreach ($path in @($PSCommandPath,$launcher,(Join-Path $PSScriptRoot 'VaultCrypto.cs'),(Join-Path $PSScriptRoot 'Vault.Common.ps1'),(Join-Path $PSScriptRoot 'XrayPipe.cs'),(Join-Path $PSScriptRoot 'XrayPipe.Common.ps1'),$testXray,$testBrowser)) {
        Note ('SHA256 ' + (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash + '  ' + [IO.Path]::GetFileName($path))
    }
    $private = Join-Path $stage 'private'
    $tmp = Join-Path $private 'tmp'
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $env:TEMP = $tmp; $env:TMP = $tmp
    Initialize-VaultCrypto
    $generated = New-VaultPassphrase; $password = $generated.CopyPassword()
    $outbound = Convert-Vless 'vless://12345678-1234-4234-8234-123456789abc@example.invalid:443?security=tls&type=tcp&sni=example.invalid&fp=chrome'
    $document = @{ version = 1; subscription = @{ url = 'https://example.invalid/synthetic'; hwid = '23456789-2345-4345-8345-23456789abcd' }; activeConfig = @{
        log = @{ loglevel = 'none' }
        inbounds = @(@{ listen = '127.0.0.1'; port = 17890; protocol = 'socks'; settings = @{ auth = 'noauth'; udp = $false } })
        outbounds = @($outbound)
    } }
    $vault = Join-Path $private 'workspace.vault'
    Write-NewVault $vault $document $generated $password
    $vaultHash = (Get-FileHash -LiteralPath $vault -Algorithm SHA256).Hash
    $document = $null
    Note 'ACTION: a real LibreWolf window will open at about:blank. Do not browse, sign in or download. Wait briefly, then close this browser normally. Keep PowerShell open.'
    Invoke-RealSession
    if (-not $evidence.greeted -or -not $evidence.browser) { throw 'Real browser session was not reached.' }
    if (-not $evidence.browser.HasExited) { throw 'Browser starter is still alive.' }
    if (Get-Process -Id $evidence.xrayId -ErrorAction SilentlyContinue) { throw 'Xray PID is still present after session.' }
    $remaining = @(Get-CimInstance Win32_Process -Filter "Name = 'librewolf.exe'" -ErrorAction Stop | Where-Object { -not $_.ExecutablePath -or $_.ExecutablePath -eq $testBrowser })
    if ($remaining.Count -gt 0) { throw 'Browser process absence not confirmed.' }
    if (@(Get-NetTCPConnection -State Listen -LocalPort 17890 -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Port still occupied after session.' }
    $h = [IO.File]::Open((Join-Path $stage '.session.lock'),'Open','ReadWrite','None'); $h.Dispose()
    if ((Get-FileHash -LiteralPath $vault -Algorithm SHA256).Hash -ne $vaultHash) { throw 'Synthetic vault changed.' }
    Note 'PASS: real Xray native validation, staged PID-owned SOCKS5 greeting, actual browser process creation and normal session return; both process exits, port and lock release, vault unchanged.'
    Note 'LIMIT: no SOCKS CONNECT, remote connectivity, real subscription, forced termination, hostile descendants or migration tested. Browser may attempt background traffic; no claim of zero network traffic.'
    Note 'RESULT: PASS for this manual real-binary lifecycle scenario only.'
} catch {
    Note ('RESULT: FAIL: ' + $_.Exception.Message)
    throw
} finally {
    if ($generated) { $generated.Dispose() }; if ($password) { $password.Dispose() }
    $env:TEMP = $oldTemp; $env:TMP = $oldTmp
    # Never delete a stage while process inspection is unavailable or an owned process may remain.
    if ($owned) {
        try {
            $live = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object { ($_.ExecutablePath -and $_.ExecutablePath.StartsWith($stage + '\',[StringComparison]::OrdinalIgnoreCase)) -or (-not $_.ExecutablePath -and $_.Name -in @('xray.exe','librewolf.exe')) })
            $gate = $null
            try {
                $gate = [IO.File]::Open((Join-Path $stage '.session.lock'),'OpenOrCreate','ReadWrite','None')
                if ($live.Count -ne 0) { throw 'Staged processes remain.' }
            } finally { if ($gate) { $gate.Dispose() } }
            Remove-Item -LiteralPath $stage -Recurse -Force
        } catch { Note ('Stage retained; no forced process termination. Path: ' + $stage) }
    }
    [IO.File]::WriteAllLines($report,$log.ToArray(),(New-Object Text.UTF8Encoding($true)))
}
