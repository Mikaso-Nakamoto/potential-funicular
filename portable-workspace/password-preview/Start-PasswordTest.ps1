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
    $path = Join-Path $directory 'test.vault'
    if (Test-Path -LiteralPath $path) {
        if ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Test vault must not be a link.' }
    }
    Write-Host 'ISOLATED TEST: synthetic data only. No Runtime, subscription, browser profile or existing vault is read/imported/modified.' -ForegroundColor Cyan
    Write-Host 'A password protects against offline guessing only as well as its strength permits. Recovery words do not compensate for a weak password.'
    while ($true) {
        $password = $null; $confirmation = $null; $phrase = $null; $phraseConfirm = $null; $credential = $null; $created = $null
        $bytes = $null; $next = $null
        try {
            if (-not (Test-Path -LiteralPath $path)) {
                $phase = 'create-test'
                Write-Host 'Set a NEW TEST password once: 16-256 characters, 6 different or more, no all-digit/obvious/repeated pattern or leading/trailing whitespace. Several unrelated words are allowed. NFC normalized; keyboard layout is NOT corrected.'
                $password = Read-Host 'New TEST password (hidden)' -AsSecureString
                $confirmation = Read-Host 'Repeat TEST password (hidden)' -AsSecureString
                $created = [VicaPasswordPreview.Envelope]::Create([Text.Encoding]::UTF8.GetBytes('VIC-A SYNTHETIC PASSWORD TEST ONLY'),$password,$confirmation,$words)
                $phrase = $created.Recovery.CopyPassword()
                Show-Recovery $phrase
                $phraseConfirm = Read-Host 'Re-enter all TEN recovery words separated by single spaces (hidden)' -AsSecureString
                Assert-TestPayload $created.Envelope $phraseConfirm $true
                Write-TestEnvelope $path $created.Envelope $password '' $phraseConfirm
                Write-Host 'PASS: test vault published only after password AND recovery phrase opened the staged file. Save the phrase independently of this drive.' -ForegroundColor Green
                continue
            }
            Write-Host ''
            Write-Host 'VIC-A PASSWORD TEST | NO IMPORT / NO CLEANUP'
            Write-Host '1. Open test vault with password'
            Write-Host '2. Open test vault with ten recovery words'
            Write-Host '3. Change password using current password + recovery (fresh key; same words)'
            Write-Host '4. Reset password using recovery words (recovery unchanged)'
            Write-Host '0. Exit'
            $choice = Read-Host '>'
            if ($choice -eq '0') { break }
            if ($choice -notin @('1','2','3','4')) { continue }
            $phase = 'read-test'
            $bytes = Read-TestEnvelope $path
            $before = Get-TestCipherHash $bytes
            $recovery = $choice -in @('2','4')
            $prompt = 'TEST password (hidden)'
            if ($recovery) { $prompt = 'TEN recovery words, single spaces (hidden)' }
            $credential = Read-Host $prompt -AsSecureString
            if ($choice -in @('1','2')) {
                $phase = 'open-test'
                Assert-TestPayload $bytes $credential $recovery
                if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $before) { throw 'Test file changed externally.' }
                Write-Host 'PASS: synthetic test data authenticated and opened; ciphertext unchanged.' -ForegroundColor Green
            } else {
                $phase = 'change-test-password'
                Assert-TestPayload $bytes $credential $recovery
                $password = Read-Host 'NEW TEST password (hidden)' -AsSecureString
                $confirmation = Read-Host 'Repeat NEW TEST password (hidden)' -AsSecureString
                if (-not $recovery) { $phraseConfirm = Read-Host 'TEN recovery words to rotate the key while keeping the same recovery phrase (hidden)' -AsSecureString }
                else { $phraseConfirm = $credential.Copy() }
                $next = [VicaPasswordPreview.Envelope]::ChangePassword($bytes,$credential,$recovery,$password,$confirmation,$phraseConfirm)
                Write-TestEnvelope $path $next $password $before $phraseConfirm
                Write-Host 'PASS: test password AND data key changed; encrypted previous version retained. The TEN recovery words are unchanged. Backups still accept their OLD password.' -ForegroundColor Green
            }
        } catch {
            Write-Warning ('Test operation stopped at: ' + $phase + '. Wrong credential, rejected password policy, integrity failure or I/O. Existing published file is not deliberately replaced on validation failure; if publication was attempted, retain test backups. No production data involved.')
            Write-Host 'For a new password: check confirmation, 16-256 NFC characters, at least 6 different, no obvious/repeated pattern, no edge whitespace.'
            if (-not (Test-Path -LiteralPath $path)) {
                if ((Read-Host 'Enter R to retry creation; anything else exits') -cne 'R') { break }
            }
        } finally {
            foreach ($item in @($password,$confirmation,$phrase,$phraseConfirm,$credential,$created)) { if ($null -ne $item) { $item.Dispose() } }
            $bytes = $null; $next = $null
        }
    }
} catch {
    throw ('Password preview stopped at: ' + $phase + '. No production import/cleanup is implemented. Do not send credentials.')
} finally {
    $env:TEMP = $oldTemp; $env:TMP = $oldTmp
    if ($lock) { $lock.Dispose() }
}
