#requires -Version 5.1
[CmdletBinding()]
param([string]$SourceRoot = '',[string]$Root = '')
$ErrorActionPreference = 'Stop'
$package = Split-Path -Parent $PSScriptRoot
if (-not $SourceRoot) { $SourceRoot = Join-Path (Split-Path -Parent $package) 'Working-Vault-Preview\WorkingRuntime' }
if (-not $Root) { $Root = Join-Path $package 'Runtime' }
. (Join-Path $package 'Workspace.Common.ps1')
. (Join-Path $PSScriptRoot 'Bootstrap.Common.ps1')
. (Join-Path $PSScriptRoot 'Native.Common.ps1')
. (Join-Path $PSScriptRoot 'VaultV03.Common.ps1')
Assert-VicaPlatform
$SourceRoot = Get-Workspace $SourceRoot
$Root = [IO.Path]::GetFullPath($Root)
$stage = Join-Path $package ('.import-' + [Guid]::NewGuid().ToString('N'))
$lock = $null; $oldPassword = $null; $password = $null; $confirmation = $null; $phrase = $null; $phraseConfirmation = $null; $created = $null
$plain = $null; $payload = $null; $owned = $false; $published = $false; $phase = 'preflight'
$oldTemp = $env:TEMP; $oldTmp = $env:TMP
function Assert-CopyTree([string]$Path) {
    foreach ($item in @((Get-Item -LiteralPath $Path -Force)) + @(Get-ChildItem -LiteralPath $Path -Recurse -Force)) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Source links are not supported.' }
    }
}
try {
    if (Test-Path -LiteralPath $Root) { throw 'Destination exists; no merge/overwrite.' }
    if ($SourceRoot -eq $Root) { throw 'Separate destination required.' }
    $lock = [IO.File]::Open((Join-Path $SourceRoot '.session.lock'),'OpenOrCreate','ReadWrite','None')
    if (Test-ProfileBusy (Join-Path $SourceRoot 'private\profile')) { throw 'Close managed browser.' }
    if (@(Get-NetTCPConnection -State Listen -LocalPort 17890 -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Port occupied; no process will be stopped.' }
    Write-Warning 'Creates a NEW Runtime copy, NEW password, NEW ten words and NEW random key. Original data stays untouched. Requires free disk space for a full binary/profile/download copy.'
    if ((Read-Host 'Type IMPORT to copy the current encrypted working version; anything else cancels') -cne 'IMPORT') { return }
    New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null; $owned = $true
    $temp = Join-Path $stage 'private\tmp'
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    $env:TEMP = $temp; $env:TMP = $temp
    Initialize-PasswordPreview
    $phase = 'unlock-existing-working-vault'
    $sourceVault = Join-Path $SourceRoot 'private\workspace.vault'
    $sourceBytes = Read-BoundedVaultBytes $sourceVault
    $sourceHash = Get-TestCipherHash $sourceBytes
    $oldPassword = Read-Host 'Existing WORKING vault phrase (not the discarded test phrase; hidden)' -AsSecureString
    $plain = [VicAVault.Crypto]::Open($sourceBytes,$oldPassword)
    $document = (New-Object Text.UTF8Encoding($false,$true)).GetString($plain) | ConvertFrom-Json
    Assert-VaultDocument $document
    [Array]::Clear($plain,0,$plain.Length); $plain = $null
    $oldPassword.Dispose(); $oldPassword = $null
    $phase = 'copy-and-validate'
    Assert-VicaXray $SourceRoot
    foreach ($name in @('Xray','LibreWolf')) {
        $source = Join-Path $SourceRoot $name
        Assert-CopyTree $source
        Copy-Item -LiteralPath $source -Destination (Join-Path $stage $name) -Recurse -ErrorAction Stop
    }
    foreach ($name in @('profile','downloads')) {
        $source = Join-Path $SourceRoot ('private\' + $name)
        if (Test-Path -LiteralPath $source) {
            Assert-CopyTree $source
            Copy-Item -LiteralPath $source -Destination (Join-Path $stage ('private\' + $name)) -Recurse -ErrorAction Stop
        }
    }
    Assert-VicaXray $stage
    $browsers = @(Get-ChildItem -LiteralPath (Join-Path $stage 'LibreWolf') -Filter librewolf.exe -Recurse -File)
    if ($browsers.Count -ne 1) { throw 'Expected one browser.' }
    $signature = Get-AuthenticodeSignature -LiteralPath $browsers[0].FullName
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false) -cne 'OSSign (Scheibling Consulting AB)') { throw 'Official browser signature required.' }
    Test-XrayObjectInMemory (Join-Path $stage 'Xray\xray.exe') $document.activeConfig
    $phase = 'new-password'
    Write-Host 'NEW password: 8-256 characters, 6 different minimum, no obvious/repeated pattern, all-digit value or edge spaces.'
    while ($true) {
        $password = Read-Host 'Set NEW password (hidden)' -AsSecureString
        try { [VicaPasswordPreview.Envelope]::ValidatePassword($password,$password); break }
        catch {
            $password.Dispose(); $password = $null
            Write-Warning 'Password policy rejected. Minimum8, 6different, no obvious/repeated pattern or edge spaces.'
            if ((Read-Host 'Enter = retry; EXIT = cancel setup') -ceq 'EXIT') { return }
        }
    }
    $payload = [Text.Encoding]::UTF8.GetBytes(($document | ConvertTo-Json -Depth 30 -Compress))
    $created = [VicaPasswordPreview.Envelope]::Create($payload,$password,$password,[IO.File]::ReadAllBytes((Join-Path $package 'vault-preview\words\eff-large.txt')))
    $phrase = $created.Recovery.CopyPassword()
    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($phrase)
        Write-Warning 'NEW TEN RECOVERY WORDS: store offline. Do not screenshot or send them in chat.'
        Write-Host ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)) -ForegroundColor Yellow
    } finally { if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) } }
    foreach ($mode in @('password','recovery')) {
        $phase = 'confirm-new-' + $mode
        while ($true) {
            $entered = $null; $verified = $null
            try {
                $prompt = 'Enter NEW password again (hidden)'
                if ($mode -eq 'recovery') { $prompt = 'Enter all NEW ten recovery words with single spaces (hidden)' }
                $entered = Read-Host $prompt -AsSecureString
                $verified = [VicaPasswordPreview.Envelope]::Open($created.Envelope,$entered,($mode -eq 'recovery'))
                if ((Get-TestCipherHash $verified) -cne (Get-TestCipherHash $payload)) { throw 'Payload mismatch.' }
                if ($mode -eq 'password') { $confirmation = $entered; $entered = $null; Write-Host 'PASSWORD OK' -ForegroundColor Green }
                else { $phraseConfirmation = $entered; $entered = $null; Write-Host 'RECOVERY OK' -ForegroundColor Green }
                break
            } catch {
                Write-Warning 'Input did not open the new vault. SAME password/phrase remains in use.'
                if ((Read-Host 'Enter = retry this step; EXIT = cancel setup') -ceq 'EXIT') { return }
            } finally {
                if ($verified) { [Array]::Clear($verified,0,$verified.Length) }
                if ($entered) { $entered.Dispose() }
            }
        }
    }
    $phase = 'encrypted-readback'
    Write-V03Stage (Join-Path $stage 'private\workspace.vault') $created.Envelope $confirmation $phraseConfirmation
    if ((Get-FileHash -LiteralPath $sourceVault -Algorithm SHA256).Hash -cne $sourceHash) { throw 'Source changed externally.' }
    $phase = 'publish-new-runtime'
    [IO.Directory]::Move($stage,$Root); $published = $true
    Write-Host 'READY: new password Runtime created and verified. Original Runtime/vault untouched. Test browser/subscription before any manual cleanup.' -ForegroundColor Green
} catch { throw ('Setup stopped at: ' + $phase + '. Original data not intentionally modified. No plaintext fallback; do not share secrets.') }
finally {
    foreach ($item in @($oldPassword,$password,$confirmation,$phrase,$phraseConfirmation,$created)) { if ($null -ne $item) { $item.Dispose() } }
    foreach ($bytes in @($plain,$payload)) { if ($bytes) { [Array]::Clear($bytes,0,$bytes.Length) } }
    $document = $null
    $env:TEMP = $oldTemp; $env:TMP = $oldTmp
    if ($lock) { $lock.Dispose() }
    if ($owned -and -not $published -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
