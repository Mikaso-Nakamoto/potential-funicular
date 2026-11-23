#requires -Version 5.1
# PUBLIC SYNTHETIC DATA ONLY. Does not read Runtime, subscription, UUID or browser profile.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Vault.Common.ps1')
Initialize-VaultCrypto
$fixture = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'tests\synthetic-vector.json')) | ConvertFrom-Json
$password = ConvertTo-SecureString -String $fixture.syntheticPassword -AsPlainText -Force
$wrong = ConvertTo-SecureString -String 'incorrect synthetic password' -AsPlainText -Force
$plain = $null; $opened = $null
function Expect-Rejection([byte[]]$Bytes, [Security.SecureString]$Pass) {
    $rejected = $false
    try { $null = [VicAVault.Crypto]::Open($Bytes, $Pass) } catch { $rejected = $true }
    if (-not $rejected) { throw 'Unauthenticated ciphertext was accepted.' }
}
try {
    $envelope = [Convert]::FromBase64String($fixture.envelopeBase64)
    $opened = [VicAVault.Crypto]::Open($envelope, $password)
    if ([Text.Encoding]::UTF8.GetString($opened) -cne $fixture.syntheticPlaintext) { throw 'Cross-implementation vector mismatch.' }
    $plain = [Text.Encoding]::UTF8.GetBytes($fixture.syntheticPlaintext)
    $sealed1 = [VicAVault.Crypto]::Seal($plain, $password)
    $sealed2 = [VicAVault.Crypto]::Seal($plain, $password)
    if ([Convert]::ToBase64String($sealed1) -eq [Convert]::ToBase64String($sealed2)) { throw 'Fresh salt/nonce test failed.' }
    $roundTrip = [VicAVault.Crypto]::Open($sealed1, $password)
    if ([Text.Encoding]::UTF8.GetString($roundTrip) -cne $fixture.syntheticPlaintext) { throw 'Round-trip mismatch.' }
    [Array]::Clear($roundTrip, 0, $roundTrip.Length)
    Expect-Rejection $sealed1 $wrong
    foreach ($offset in @(0,8,24,36,($sealed1.Length - 1))) {
        $altered = [byte[]]$sealed1.Clone()
        $altered[$offset] = $altered[$offset] -bxor 1
        Expect-Rejection $altered $password
    }
    foreach ($length in @(0,7,35,51)) {
        $short = New-Object byte[] $length
        if ($length -gt 0) { [Array]::Copy($sealed1, $short, $length) }
        Expect-Rejection $short $password
    }
    foreach ($weakText in @('aaaaaaaaaaaaaaaa','abcdabcdabcdabcd','password123456789!')) {
        $weak = ConvertTo-SecureString $weakText -AsPlainText -Force
        try {
            $rejected = $false
            try { [VicAVault.Crypto]::ValidateNewPassword($weak) } catch { $rejected = $true }
            if (-not $rejected) { throw 'Weak password was accepted.' }
        } finally { $weak.Dispose() }
    }
    $nfcText = 'Synthetic ' + [char]0x00c4 + ' passphrase for testing!'
    $nfc = ConvertTo-SecureString $nfcText -AsPlainText -Force
    $nfd = ConvertTo-SecureString ($nfcText.Normalize([Text.NormalizationForm]::FormD)) -AsPlainText -Force
    try {
        $unicodeEnvelope = [VicAVault.Crypto]::Seal($plain, $nfc)
        $unicodePlain = [VicAVault.Crypto]::Open($unicodeEnvelope, $nfd)
        if ([Text.Encoding]::UTF8.GetString($unicodePlain) -cne $fixture.syntheticPlaintext) { throw 'NFC interoperability failed.' }
        [Array]::Clear($unicodePlain, 0, $unicodePlain.Length)
    } finally { $nfc.Dispose(); $nfd.Dispose() }
    $legacy = [byte[]]$sealed1.Clone()
    $legacy[7] = [byte][char]'1'
    Expect-Rejection $legacy $password
    Write-Host 'PASS: libsodium runtime 1.0.22 loaded; interoperability vector, round-trip, randomness, wrong password, tampering and truncation tested.' -ForegroundColor Green
    Write-Host 'No user data was read or changed. This is NOT an audit of host security or memory erasure.'
} finally {
    if ($plain) { [Array]::Clear($plain, 0, $plain.Length) }
    if ($opened) { [Array]::Clear($opened, 0, $opened.Length) }
    $password.Dispose(); $wrong.Dispose()
}
