#requires -Version 5.1
# Synthetic-only integration; all launcher calls use ValidateOnly. Never reads an installed Runtime.
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Use 64-bit Windows PowerShell 5.1.' }
. (Join-Path $PSScriptRoot 'Vault.Common.ps1')
. (Join-Path $PSScriptRoot 'XrayPipe.Common.ps1')
$launcher = Join-Path (Split-Path -Parent $PSScriptRoot) 'Start-VaultWorkspace.ps1'
$stage = Join-Path $PSScriptRoot ('.launch-tests-' + [Guid]::NewGuid().ToString('N'))
$owned = $false; $generated = $null; $password = $null; $wrong = $null
$oldTemp = $env:TEMP; $oldTmp = $env:TMP
$log = New-Object 'Collections.Generic.List[string]'
$report = Join-Path $PSScriptRoot 'vault-launch-test-report.txt'
function Note([string]$Text) { Write-Host $Text; $log.Add($Text) }
function Invoke-Preview([Security.SecureString]$PromptPassword) {
    # Trusted test harness mocks only interactive input. No password argument/environment/file is used by the launcher.
    $mock = { param([string]$Prompt, [switch]$AsSecureString)
        if (-not $AsSecureString) { throw 'Unexpected plaintext prompt.' }
        return $PromptPassword.Copy()
    }.GetNewClosure()
    Set-Item -Path Function:Read-Host -Value $mock
    try { & $launcher -Root $testRoot -ValidateOnly }
    finally { Remove-Item -Path Function:Read-Host -ErrorAction SilentlyContinue }
}
function Assert-LockReleased {
    $handle = [IO.File]::Open((Join-Path $testRoot '.session.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    $handle.Dispose()
}
function Must-RejectWithoutXray([string]$Name, [scriptblock]$Action) {
    if (Test-Path -LiteralPath $pidMarker) { Remove-Item -LiteralPath $pidMarker }
    $rejected = $false
    try { $null = & $Action } catch { $rejected = $true }
    if (-not $rejected) { throw ('Expected rejection: ' + $Name) }
    if (Test-Path -LiteralPath $pidMarker) { throw ('Unexpected Xray process started: ' + $Name) }
    Note ('PASS: ' + $Name + '; no Xray child started')
}
try {
    New-Item -ItemType Directory -Path $stage | Out-Null
    $owned = $true; $env:TEMP = $stage; $env:TMP = $stage
    Note ('Vault-only launcher integration; PS ' + $PSVersionTable.PSVersion + '; CLR ' + [Environment]::Version)
    foreach ($name in @('VaultCrypto.cs','Vault.Common.ps1','XrayPipe.cs','XrayPipe.Common.ps1','Test-VaultLaunch.ps1','Test-SodiumImports.ps1','SodiumPe.cs','words\eff-large.txt','lib\dependency.json','lib\vica-sodium.dll','tests\XrayPipeFixture.cs')) {
        Note ('SHA256 ' + (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name) -Algorithm SHA256).Hash + '  ' + $name)
    }
    Note ('SHA256 ' + (Get-FileHash -LiteralPath $launcher -Algorithm SHA256).Hash + '  ../Start-VaultWorkspace.ps1')
    Note ('SHA256 ' + (Get-FileHash -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'Workspace.Common.ps1') -Algorithm SHA256).Hash + '  ../Workspace.Common.ps1')
    Initialize-VaultCrypto
    Initialize-XrayPipe
    $testRoot = Join-Path $stage 'SyntheticRuntime'
    $private = Join-Path $testRoot 'private'
    $xrayDir = Join-Path $testRoot 'Xray'
    New-Item -ItemType Directory -Path $private,$xrayDir | Out-Null
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'tests\XrayPipeFixture.cs'))) -OutputAssembly (Join-Path $xrayDir 'xray.exe') -OutputType ConsoleApplication -ErrorAction Stop
    [IO.File]::WriteAllText((Join-Path $xrayDir 'mode.txt'), 'ok')
    $pidMarker = Join-Path $xrayDir 'pid.txt'
    $legacy = Join-Path $private 'xray.json'
    [IO.File]::WriteAllText($legacy, 'SYNTHETIC LEGACY DECOY: deliberately not JSON')
    $legacyHash = (Get-FileHash -LiteralPath $legacy -Algorithm SHA256).Hash
    $outbound = Convert-Vless 'vless://12345678-1234-4234-8234-123456789abc@example.invalid:443?security=tls&type=tcp&sni=example.invalid&fp=chrome'
    $document = @{
        version = 1
        subscription = @{ url = 'https://example.invalid/synthetic'; hwid = '23456789-2345-4345-8345-23456789abcd' }
        activeConfig = @{
            log = @{ loglevel = 'none' }
            inbounds = @(@{ listen = '127.0.0.1'; port = 17890; protocol = 'socks'; settings = @{ auth = 'noauth'; udp = $false } })
            outbounds = @($outbound)
        }
    }
    $generated = New-VaultPassphrase
    $password = $generated.CopyPassword()
    $wrong = ConvertTo-SecureString 'Known wrong synthetic phrase for testing!' -AsPlainText -Force
    $vault = Join-Path $private 'workspace.vault'
    Write-NewVault $vault $document $generated $password
    $original = [IO.File]::ReadAllBytes($vault)
    Invoke-Preview $password
    if (-not (Test-Path -LiteralPath $pidMarker)) { throw 'Successful validation never invoked the fixture.' }
    if (Test-Path -LiteralPath (Join-Path $private 'profile')) { throw 'ValidateOnly created a browser profile.' }
    Assert-LockReleased
    Note 'PASS: actual vault-only launcher validates encrypted config through stdin; legacy decoy ignored; no profile/browser required'
    Must-RejectWithoutXray 'wrong password, despite existing plaintext decoy' { Invoke-Preview $wrong }
    Assert-LockReleased
    $hidden = Join-Path $private 'vault-disabled-for-test'
    [IO.File]::Move($vault,$hidden)
    try { Must-RejectWithoutXray 'missing vault, no plaintext fallback' { Invoke-Preview $password } }
    finally { [IO.File]::Move($hidden,$vault) }
    Assert-LockReleased
    $changed = [byte[]]$original.Clone(); $changed[$changed.Length - 1] = $changed[$changed.Length - 1] -bxor 1
    [IO.File]::WriteAllBytes($vault,$changed)
    try { Must-RejectWithoutXray 'tampered vault' { Invoke-Preview $password } }
    finally { [IO.File]::WriteAllBytes($vault,$original) }
    Assert-LockReleased
    $invalid = $document | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $invalid.activeConfig.inbounds[0].listen = '0.0.0.0'
    $plain = [Text.Encoding]::UTF8.GetBytes(($invalid | ConvertTo-Json -Depth 30 -Compress))
    try { $badCipher = [VicAVault.Crypto]::Seal($plain,$password) }
    finally { [Array]::Clear($plain,0,$plain.Length) }
    [IO.File]::WriteAllBytes($vault,$badCipher)
    try { Must-RejectWithoutXray 'authenticated vault with forbidden config' { Invoke-Preview $password } }
    finally { [IO.File]::WriteAllBytes($vault,$original) }
    Assert-LockReleased
    $held = [IO.File]::Open((Join-Path $testRoot '.session.lock'),'OpenOrCreate','ReadWrite','None')
    try { Must-RejectWithoutXray 'concurrent session lock' { Invoke-Preview $password } }
    finally { $held.Dispose() }
    Assert-LockReleased
    $held = [IO.File]::Open($vault,'Open','ReadWrite','None')
    try { Must-RejectWithoutXray 'locked vault file' { Invoke-Preview $password } }
    finally { $held.Dispose() }
    Assert-LockReleased
    [IO.File]::WriteAllText((Join-Path $xrayDir 'mode.txt'),'reject')
    $rejected = $false
    try { Invoke-Preview $password } catch { $rejected = $true }
    if (-not $rejected -or -not (Test-Path -LiteralPath $pidMarker)) { throw 'Xray rejection scenario did not execute correctly.' }
    Assert-LockReleased
    Note 'PASS: Xray validation rejection stops the vault launcher before live session/browser'
    if ((Get-FileHash -LiteralPath $legacy -Algorithm SHA256).Hash -cne $legacyHash) { throw 'Legacy decoy was changed.' }
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($vault)) -cne [Convert]::ToBase64String($original)) { throw 'Original synthetic vault changed.' }
    Note 'PASS: original vault and legacy decoy preserved; locks released on validation exits'
    Note 'RESULT: PASS for implemented integration checks only. NOT TESTED: real browser, real SOCKS session, real subscription, migration, updater or hostile process trees.'
} catch {
    Note ('RESULT: FAIL: ' + $_.Exception.Message)
    throw
} finally {
    if ($generated) { $generated.Dispose() }
    if ($password) { $password.Dispose() }
    if ($wrong) { $wrong.Dispose() }
    $env:TEMP = $oldTemp; $env:TMP = $oldTmp
    [IO.File]::WriteAllLines($report,$log.ToArray(),(New-Object Text.UTF8Encoding($true)))
    if ($owned) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
