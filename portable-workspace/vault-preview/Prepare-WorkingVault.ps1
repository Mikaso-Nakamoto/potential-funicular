#requires -Version 5.1
[CmdletBinding()]
param([string]$InstalledRoot = 'Z:\Iran\Browser\Runtime', [switch]$ConfirmOfficialInstalledBinaries)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Use 64-bit Windows PowerShell 5.1.' }
. (Join-Path $PSScriptRoot 'Vault.Common.ps1')
. (Join-Path $PSScriptRoot 'XrayPipe.Common.ps1')
$destination = Join-Path (Split-Path -Parent $PSScriptRoot) 'WorkingRuntime'
$stage = Join-Path (Split-Path -Parent $PSScriptRoot) ('.working-vault-' + [Guid]::NewGuid().ToString('N'))
$lock = $null; $generated = $null; $confirmation = $null; $display = $null
$config = $null; $document = $null; $url = $null; $hwid = $null
$owned = $false; $published = $false; $phase = 'preflight'
$oldTemp = $env:TEMP; $oldTmp = $env:TMP
function Read-HiddenText([string]$Prompt) {
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
function Assert-NoReparse([string]$Path) {
    foreach ($item in @((Get-Item -LiteralPath $Path -Force)) + @(Get-ChildItem -LiteralPath $Path -Recurse -Force)) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse points in source trees are not supported.' }
    }
}
function Assert-Browser([string]$Path) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid') { throw 'LibreWolf Authenticode must be Valid. No bypass.' }
    if ($signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false) -cne 'OSSign (Scheibling Consulting AB)') { throw 'Unexpected LibreWolf publisher. No bypass.' }
}
try {
    if (-not $ConfirmOfficialInstalledBinaries) { throw 'Confirm official installed binary sources first.' }
    if (Test-Path -LiteralPath $destination) { throw 'WorkingRuntime already exists. Nothing will be overwritten.' }
    if (@(Get-CimInstance Win32_Process -Filter "Name = 'librewolf.exe'" -ErrorAction Stop).Count -gt 0) { throw 'Close all LibreWolf instances first.' }
    if (@(Get-NetTCPConnection -State Listen -LocalPort 17890 -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Port 17890 is occupied. Nothing will be stopped.' }
    $InstalledRoot = Get-Workspace $InstalledRoot
    $lock = [IO.File]::Open((Join-Path $InstalledRoot '.session.lock'),'OpenOrCreate','ReadWrite','None')
    if (Test-ProfileBusy (Join-Path $InstalledRoot 'private\profile')) { throw 'Source profile is busy.' }
    foreach ($name in @('Xray','LibreWolf')) { Assert-NoReparse (Join-Path $InstalledRoot $name) }
    $sourceConfig = Join-Path $InstalledRoot 'private\xray.json'
    if ((Get-Item -LiteralPath $sourceConfig -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Config must not be a reparse point.' }
    # Read one bounded, stable snapshot; never copy plaintext config into the destination.
    $phase = 'source config read and policy'
    $stream = [IO.File]::Open($sourceConfig,'Open','Read','Read')
    try {
        if ($stream.Length -le 0 -or $stream.Length -gt 1048576) { throw 'Config size is outside the supported limit.' }
        $reader = New-Object IO.StreamReader($stream,(New-Object Text.UTF8Encoding($false,$true)),$true)
        try { $config = $reader.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop }
        catch { throw 'Source config could not be parsed. Values are not displayed.' }
        finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
    Assert-ConfigObjectPolicy $config
    $expectedXray = '1ca7a2cf61ba2c5d20b21a80d405b57933939751081cb289f07bd8ddf7cc3185'
    if ((Get-FileHash -LiteralPath (Join-Path $InstalledRoot 'Xray\xray.exe') -Algorithm SHA256).Hash -ne $expectedXray) { throw 'Xray differs from the previously tested binary. Review required.' }
    $browsers = @(Get-ChildItem -LiteralPath (Join-Path $InstalledRoot 'LibreWolf') -Recurse -File -Filter librewolf.exe)
    if ($browsers.Count -ne 1) { throw 'Expected one LibreWolf executable.' }
    Assert-Browser $browsers[0].FullName
    $phase = 'binary copy and verification'
    New-Item -ItemType Directory -Path $stage | Out-Null
    $owned = $true
    foreach ($name in @('Xray','LibreWolf')) { Copy-Item -LiteralPath (Join-Path $InstalledRoot $name) -Destination (Join-Path $stage $name) -Recurse }
    $exe = Join-Path $stage 'Xray\xray.exe'
    if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne $expectedXray) { throw 'Staged Xray hash mismatch.' }
    $copiedBrowser = @(Get-ChildItem -LiteralPath (Join-Path $stage 'LibreWolf') -Recurse -File -Filter librewolf.exe)
    if ($copiedBrowser.Count -ne 1) { throw 'Expected one staged LibreWolf executable.' }
    Assert-Browser $copiedBrowser[0].FullName
    $tmp = Join-Path $stage 'private\tmp'
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $env:TEMP = $tmp; $env:TMP = $tmp
    # Native -test only: no listener/browser/remote connection is launched here.
    $phase = 'native config validation'
    Test-XrayObjectInMemory $exe $config
    Initialize-VaultCrypto
    Write-Warning 'Encrypted COPY only. Old plaintext config and legacy launcher remain usable. No whole-installation password protection.'
    $phase = 'subscription metadata input'
    $url = Read-HiddenText 'Complete existing HTTPS subscription URL (hidden)'
    $hwid = Convert-DeviceHwid (Read-HiddenText 'Existing successful device HWID UUID (hidden; do not generate a new one)')
    $document = @{ version = 1; createdAtUtc = [DateTime]::UtcNow.ToString('o'); subscription = @{ url = $url; hwid = $hwid }; activeConfig = $config }
    $document = $document | ConvertTo-Json -Depth 30 -Compress | ConvertFrom-Json
    Assert-VaultDocument $document
    Write-Warning 'Six random words will be visible in console scrollback. No transcript/screen recording. Store securely; no password recovery.'
    $generated = New-VaultPassphrase
    $display = $generated.CopyPassword(); $ptr = [IntPtr]::Zero
    try {
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($display)
        Write-Host ('Store securely: ' + [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)) -ForegroundColor Yellow
    } finally {
        if ($ptr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
        $display.Dispose(); $display = $null
    }
    $phase = 'passphrase confirmation and encrypted write'
    $confirmation = Read-Host 'Re-enter the six generated words with single spaces' -AsSecureString
    Write-NewVault (Join-Path $stage 'private\workspace.vault') $document $generated $confirmation
    # Publish the complete directory once; never merge into or overwrite an existing destination.
    $phase = 'directory publication'
    [IO.Directory]::Move($stage,$destination)
    $published = $true
    Write-Host 'PASS: encrypted working COPY created and read-back verified; native Xray -test accepted config. Original config/profile untouched. No browser/tunnel launched.' -ForegroundColor Green
    Write-Host ('Destination: ' + $destination)
    Write-Host 'Next: run Start-VaultWorkspace.ps1 with -Root pointing to WorkingRuntime and -ValidateOnly in a NEW PowerShell.'
} catch {
    # Suppress nested exceptions that could include a source config value or URL.
    throw ('Working vault preparation stopped at: ' + $phase + '. No plaintext fallback or destination overwrite. Check prerequisites/input/free space. Do not share secrets.')
} finally {
    $config = $null; $document = $null; $url = $null; $hwid = $null
    if ($display) { $display.Dispose() }; if ($confirmation) { $confirmation.Dispose() }; if ($generated) { $generated.Dispose() }
    $env:TEMP = $oldTemp; $env:TMP = $oldTmp
    if ($lock) { $lock.Dispose() }
    # Retain failed stage rather than deleting files if native validation cleanup is uncertain.
    if ($owned -and -not $published) { Write-Warning ('Unpublished owned stage retained: ' + $stage + '. It may contain an encrypted vault; no plaintext config was written. Do not delete until no process uses it.') }
}
