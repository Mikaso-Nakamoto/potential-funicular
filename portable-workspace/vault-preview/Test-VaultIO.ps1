#requires -Version 5.1
# Uses only a newly owned scratch directory beside this script. No Runtime access/network.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Workspace.Common.ps1')
. (Join-Path $PSScriptRoot 'Vault.Common.ps1')
Initialize-VaultCrypto
$stage = Join-Path $PSScriptRoot ('.vault-io-' + [Guid]::NewGuid().ToString('N'))
$password = ConvertTo-SecureString 'Synthetic vault testing phrase 8274!' -AsPlainText -Force
$wrong = ConvertTo-SecureString 'Different synthetic testing phrase 9275!' -AsPlainText -Force
$owned = $false
function Expect-Failure([string]$Name, [scriptblock]$Action) {
    $failed = $false
    try { $null = & $Action } catch { $failed = $true }
    if (-not $failed) { throw ('Expected rejection: ' + $Name) }
    Write-Host ('PASS: ' + $Name)
}
try {
    New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null
    $owned = $true
    $outbound = Convert-Vless 'vless://12345678-1234-4234-8234-123456789abc@example.invalid:443?security=tls&type=tcp&sni=example.invalid&fp=chrome'
    $document = @{
        version = 1
        subscription = @{ url = 'https://example.invalid/synthetic-only'; hwid = '23456789-2345-4345-8345-23456789abcd' }
        activeConfig = @{
            log = @{ loglevel = 'none' }
            inbounds = @(@{ listen = '127.0.0.1'; port = 17890; protocol = 'socks'; settings = @{ auth = 'noauth'; udp = $false } })
            outbounds = @($outbound)
        }
    }
    $path = Join-Path $stage 'synthetic.vault'
    Write-NewVault $path $document $password $password
    $read = Read-Vault $path $password
    if ($read.subscription.url -cne 'https://example.invalid/synthetic-only') { throw 'Read-back payload mismatch.' }
    Write-Host 'PASS: create, flush, read-back, schema and configuration policy'
    $before = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    Expect-Failure 'existing vault cannot be overwritten' { Write-NewVault $path $document $password $password }
    Expect-Failure 'wrong password' { Read-Vault $path $wrong }
    $held = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try { Expect-Failure 'locked file' { Read-Vault $path $password } } finally { $held.Dispose() }
    $mismatch = Join-Path $stage 'mismatch.vault'
    Expect-Failure 'confirmation mismatch' { Write-NewVault $mismatch $document $password $wrong }
    if (Test-Path -LiteralPath $mismatch) { throw 'Failed confirmation published a vault.' }
    Expect-Failure 'write to missing parent fails' { Write-NewVault (Join-Path $stage 'missing\new.vault') $document $password $password }
    $invalid = $document | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $invalid.activeConfig.inbounds[0].listen = '0.0.0.0'
    Expect-Failure 'unsafe configuration rejected before writing' { Write-NewVault (Join-Path $stage 'bad.vault') $invalid $password $password }
    # A valid AEAD tag does not replace schema/policy validation.
    $badPlain = [Text.Encoding]::UTF8.GetBytes(($invalid | ConvertTo-Json -Depth 30 -Compress))
    try { $badCipher = [VicAVault.Crypto]::Seal($badPlain, $password) }
    finally { [Array]::Clear($badPlain, 0, $badPlain.Length) }
    $badPath = Join-Path $stage 'authenticated-invalid.vault'
    [IO.File]::WriteAllBytes($badPath, $badCipher)
    Expect-Failure 'authenticated unsafe configuration rejected on read' { Read-Vault $badPath $password }
    $oversize = Join-Path $stage 'oversize.vault'
    $stream = [IO.File]::Open($oversize, [IO.FileMode]::CreateNew)
    try { $stream.SetLength(8388661) } finally { $stream.Dispose() }
    Expect-Failure 'oversize stream rejected' { Read-BoundedVaultBytes $oversize }
    $short = Join-Path $stage 'short.vault'
    [IO.File]::WriteAllBytes($short, (New-Object byte[] 51))
    Expect-Failure 'short stream rejected' { Read-BoundedVaultBytes $short }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $before) { throw 'Baseline vault changed after negative tests.' }
    if (@(Get-ChildItem -LiteralPath $stage -Filter '*.tmp').Count -ne 0) { throw 'Staging files remain after expected failures.' }
    Write-Host 'PASS: baseline preserved and no encrypted staging files remain'
    Write-Host 'Not tested: disk-full, power loss, physical unplug, malicious filesystem races.'
} finally {
    $password.Dispose(); $wrong.Dispose()
    if ($owned) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
