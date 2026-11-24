#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Bootstrap.Common.ps1')
Assert-VicaPlatform
. (Join-Path $PSScriptRoot 'Password.Common.ps1')
$directory = Join-Path $PSScriptRoot 'test-data'
$marker = Join-Path $directory 'TEST-ONLY.marker'
$lock = $null; $phase = 'preflight'
$oldTemp = $env:TEMP; $oldTmp = $env:TMP
function Show-Recovery([Security.SecureString]$Phrase) {
    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Phrase)
        Write-Warning 'TEN RECOVERY WORDS will be visible in console scrollback. Store offline; no screenshots/transcripts. Never send them in chat.'
        Write-Host ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)) -ForegroundColor Yellow
    } finally { if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) } }
}
try {
    if (Test-Path -LiteralPath $directory) {
        if ((Get-Item -LiteralPath $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Test directory must not be a link.' }
        if (-not (Test-Path -LiteralPath $marker) -or (Get-Item -LiteralPath $marker).Length -gt 64 -or [IO.File]::ReadAllText($marker) -cne 'VIC-A SYNTHETIC PASSWORD TEST ONLY') { throw 'Unknown test directory. Nothing will be overwritten.' }
    } else {
        New-Item -ItemType Directory -Path $directory -ErrorAction Stop | Out-Null
        [IO.File]::WriteAllText($marker,'VIC-A SYNTHETIC PASSWORD TEST ONLY')
    }
    $lock = [IO.File]::Open((Join-Path $directory '.test.lock'),'OpenOrCreate','ReadWrite','None')
    $temp = Join-Path $directory 'tmp'
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    if ((Get-Item -LiteralPath $temp -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Test temp must not be a link.' }
    $env:TEMP = $temp; $env:TMP = $temp
    $phase = 'dependency'
    Initialize-VicaDependency $PSScriptRoot (Join-Path (Split-Path -Parent $PSScriptRoot) 'VIC-A-Updated')
    Initialize-PasswordPreview
    $wordsPath = Join-Path $PSScriptRoot 'vault-preview\words\eff-large.txt'
    if ((Get-Item -LiteralPath $wordsPath).Length -ne 108800) { throw 'Word list size mismatch.' }
    $words = [IO.File]::ReadAllBytes($wordsPath)
    $phase = 'synthetic-self-check'
    $checks = [VicaPasswordPreview.SelfTests]::Run($words)
    Write-Host ('PASS: ' + $checks + ' automatic synthetic crypto checks. No user data used.') -ForegroundColor Green
    # A new synthetic run never reuses previously displayed recovery words or overwrites old tests.
    $path = Join-Path $directory ('verified-' + [Guid]::NewGuid().ToString('N') + '.vault')
    Write-Host 'ISOLATED TEST: synthetic data only. No production data imported or changed.' -ForegroundColor Cyan
    Write-Host '1/4: Set a password: 8-256 characters, at least 6 different; no obvious/repeated pattern, all-digit password or edge whitespace.'
    while ($true) {
        $phase = 'password-policy-and-creation'
        $password = Read-Host 'New TEST password (hidden)' -AsSecureString
        try {
            # Confirmation is the independent unlock step below, not a second setup prompt.
            $created = [VicaPasswordPreview.Envelope]::Create([Text.Encoding]::UTF8.GetBytes('VIC-A SYNTHETIC PASSWORD TEST ONLY'),$password,$password,$words)
            break
        } catch {
            Write-Host 'Password not accepted or crypto creation failed. Minimum 8 characters, 6 different; no obvious/repeated pattern or edge spaces.' -ForegroundColor Red
            $password.Dispose(); $password = $null
            if ((Read-Host 'Enter = retry; EXIT = stop') -ceq 'EXIT') { return }
        }
    }
    $phase = 'show-new-recovery'
    $phrase = $created.Recovery.CopyPassword()
    Write-Host '2/4: Save these TEN words offline. Do not send them or a screenshot in chat.'
    Show-Recovery $phrase
    while ($true) {
        $phase = 'password-unlock-check'
        $credentialPassword = Read-Host '3/4: Enter the password you just set (hidden)' -AsSecureString
        try {
            Assert-TestPayload -Envelope $created.Envelope -Credential $credentialPassword -Recovery $false
            Write-Host 'PASSWORD OK: test data decrypted successfully.' -ForegroundColor Green
            break
        } catch {
            Write-Host 'PASSWORD CHECK FAILED: test data did not open. Nothing published.' -ForegroundColor Red
            $credentialPassword.Dispose(); $credentialPassword = $null
            if ((Read-Host 'Enter = retry SAME password; EXIT = stop') -ceq 'EXIT') { return }
        }
    }
    while ($true) {
        $phase = 'recovery-unlock-check'
        $credentialRecovery = Read-Host '4/4: Enter all TEN words, one ordinary space between words (hidden)' -AsSecureString
        try {
            Assert-TestPayload -Envelope $created.Envelope -Credential $credentialRecovery -Recovery $true
            Write-Host 'RECOVERY OK: test data decrypted independently with the ten words.' -ForegroundColor Green
            break
        } catch {
            Write-Host 'RECOVERY CHECK FAILED: check words, order and single spaces. SAME phrase remains valid; nothing published.' -ForegroundColor Red
            $credentialRecovery.Dispose(); $credentialRecovery = $null
            if ((Read-Host 'Enter = retry SAME phrase; EXIT = stop') -ceq 'EXIT') { return }
        }
    }
    $phase = 'disk-stage-readback-and-publication'
    Write-TestEnvelope -Path $path -Envelope $created.Envelope -Verify $credentialPassword -RecoveryVerify $credentialRecovery
    Write-Host 'ALL CHECKS PASSED: password and recovery both work, including encrypted disk readback.' -ForegroundColor Green
    Write-Host ('Synthetic encrypted test saved: ' + $path)
    Write-Host 'No production import or cleanup performed. Do not send credentials or recovery words.'
} catch {
    throw ('Password test stopped at: ' + $phase + '. No production data involved. Do not send credentials.')
} finally {
    foreach ($name in @('password','created','phrase','credentialPassword','credentialRecovery')) {
        $variable = Get-Variable -Name $name -ErrorAction SilentlyContinue
        if ($null -ne $variable -and $null -ne $variable.Value) { $variable.Value.Dispose() }
    }
    $env:TEMP = $oldTemp; $env:TMP = $oldTmp
    if ($lock) { $lock.Dispose() }
}
