#requires -Version 5.1
# Random values generated here are ephemeral test data, never reported or used for a real vault.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Vault.Common.ps1')
Initialize-VaultCrypto
$list = [IO.File]::ReadAllLines((Join-Path $PSScriptRoot 'words\eff-large.txt'))
$words = @{}
foreach ($line in $list) { $words[$line.Split("`t")[1]] = $true }
$seen = @{}
for ($i = 0; $i -lt 32; $i++) {
    $generated = New-VaultPassphrase
    $password = $generated.CopyPassword()
    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
        $text = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        $parts = $text.Split(' ')
        if ($parts.Count -ne 6) { throw 'Generator did not return six words.' }
        foreach ($word in $parts) { if (-not $words.ContainsKey($word)) { throw 'Generated word absent from pinned list.' } }
        # Do not log phrases. Sample uniqueness is only a regression smoke test, not proof of entropy.
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $digest = [Convert]::ToBase64String($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))) } finally { $sha.Dispose() }
        if ($seen.ContainsKey($digest)) { throw 'Repeated generated test phrase.' }
        $seen[$digest] = $true
    } finally {
        $text = $null
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
        $password.Dispose(); $generated.Dispose()
    }
}
Write-Host 'PASS: 32 ephemeral six-word samples use the pinned 7776-word list; no full-sample repeats. Not a statistical entropy proof.'
