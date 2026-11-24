#requires -Version 5.1
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Use 64-bit Windows PowerShell 5.1.' }
. (Join-Path $PSScriptRoot 'VaultRefresh.Common.ps1')
$stage = Join-Path $PSScriptRoot ('.refresh-tests-' + [Guid]::NewGuid().ToString('N'))
$report = Join-Path $PSScriptRoot 'vault-refresh-test-report.txt'
$log = New-Object 'Collections.Generic.List[string]'
$generated = $null; $password = $null; $wrong = $null; $owned = $false
$oldTemp = $env:TEMP; $oldTmp = $env:TMP
function Note([string]$Text) { Write-Host $Text; $log.Add($Text) }
function Assert-Unlocked {
    $h = [IO.File]::Open((Join-Path $stage '.session.lock'),'OpenOrCreate','ReadWrite','None'); $h.Dispose()
}
function Must-FailUnchanged([string]$Name,[scriptblock]$Action,[string]$ExpectedPhase = '') {
    $before = (Get-FileHash -LiteralPath $vault -Algorithm SHA256).Hash
    $backups = @(Get-ChildItem -LiteralPath $private -Filter 'workspace.vault.backup-*').Count
    $failed = $false
    try { $null = & $Action } catch {
        $failed = $true
        if ($ExpectedPhase -and $_.Exception.Message -notlike ('Vault refresh stopped at: ' + $ExpectedPhase + '.*')) { throw ('Failure occurred at the wrong phase: ' + $Name) }
        if ($_.Exception.Message -match 'PRIVATE-SENTINEL|example\.invalid|12345678-') { throw 'Secret was reflected in error.' }
    }
    if (-not $failed) { throw ('Expected failure: ' + $Name) }
    if ((Get-FileHash -LiteralPath $vault -Algorithm SHA256).Hash -ne $before) { throw 'Vault changed on failure.' }
    if (@(Get-ChildItem -LiteralPath $private -Filter 'workspace.vault.backup-*').Count -ne $backups) { throw 'Failure published a backup.' }
    if (@(Get-ChildItem -LiteralPath $private -Filter '*.tmp').Count -gt 0) { throw 'Staging file remained.' }
    Note ('PASS: ' + $Name + '; active vault unchanged; no backup published or staging file left')
}
try {
    New-Item -ItemType Directory -Path $stage | Out-Null; $owned = $true
    $private = Join-Path $stage 'private'; $xrayDir = Join-Path $stage 'Xray'
    New-Item -ItemType Directory -Path $private,$xrayDir | Out-Null
    $env:TEMP = $stage; $env:TMP = $stage
    Note ('Encrypted refresh synthetic tests; PS ' + $PSVersionTable.PSVersion + '; CLR ' + [Environment]::Version)
    foreach ($name in @('VaultRefresh.Common.ps1','Test-VaultRefresh.ps1','Vault.Common.ps1','VaultCrypto.cs','XrayPipe.Common.ps1','XrayPipe.cs','tests\XrayPipeFixture.cs','lib\dependency.json','lib\vica-sodium.dll')) {
        Note ('SHA256 ' + (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name) -Algorithm SHA256).Hash + '  ' + $name)
    }
    Initialize-VaultCrypto; Initialize-XrayPipe
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'tests\XrayPipeFixture.cs'))) -OutputAssembly (Join-Path $xrayDir 'xray.exe') -OutputType ConsoleApplication -ErrorAction Stop
    $mode = Join-Path $xrayDir 'mode.txt'; [IO.File]::WriteAllText($mode,'ok')
    $link1 = 'vless://12345678-1234-4234-8234-123456789abc@example.invalid:443?security=tls&type=tcp&sni=example.invalid&fp=chrome'
    $link2 = $link1.Replace('@example.invalid:443','@second.example.invalid:443')
    $node1 = Convert-Vless $link1
    $document = @{ version = 1; createdAtUtc = '2026-11-22T00:00:00Z'; subscription = @{ url = 'https://example.invalid/PRIVATE-SENTINEL'; hwid = '23456789-2345-4345-8345-23456789abcd' }; activeConfig = @{
        log = @{ loglevel = 'none' }; inbounds = @(@{ listen = '127.0.0.1'; port = 17890; protocol = 'socks'; settings = @{ auth = 'noauth'; udp = $false } }); outbounds = @($node1)
    } }
    $generated = New-VaultPassphrase; $password = $generated.CopyPassword()
    $wrong = ConvertTo-SecureString 'Synthetic wrong password, not a generated vault phrase!' -AsPlainText -Force
    $vault = Join-Path $private 'workspace.vault'
    Write-NewVault $vault $document $generated $password
    $originalHash = (Get-FileHash -LiteralPath $vault -Algorithm SHA256).Hash
    $fetchState = @{ calls = 0; body = ($link2 + "`n" + 'ss://PRIVATE-SENTINEL' + "`n" + $link1) }
    $fetch = { param($Uri,$Hwid)
        $fetchState.calls++
        if ($Uri.AbsoluteUri -cne 'https://example.invalid/PRIVATE-SENTINEL' -or $Hwid -cne '23456789-2345-4345-8345-23456789abcd') { throw 'Stored metadata was not preserved.' }
        return $fetchState.body
    }.GetNewClosure()
    Must-FailUnchanged 'wrong password before fetch' { Invoke-VaultRefresh $stage $wrong $fetch }
    if ($fetchState.calls -ne 0) { throw 'Fetch happened before authentication.' }; Assert-Unlocked
    $originalBytes = [IO.File]::ReadAllBytes($vault)
    $corrupt = [byte[]]$originalBytes.Clone(); $corrupt[$corrupt.Length-1] = $corrupt[$corrupt.Length-1] -bxor 1
    [IO.File]::WriteAllBytes($vault,$corrupt)
    try { Must-FailUnchanged 'tampered vault before fetch' { Invoke-VaultRefresh $stage $password $fetch } 'unlock' }
    finally { [IO.File]::WriteAllBytes($vault,$originalBytes) }
    if ($fetchState.calls -ne 0) { throw 'Fetch happened for a tampered vault.' }; Assert-Unlocked
    $held = [IO.File]::Open((Join-Path $stage '.session.lock'),'OpenOrCreate','ReadWrite','None')
    try { Must-FailUnchanged 'concurrent session lock' { Invoke-VaultRefresh $stage $password $fetch } } finally { $held.Dispose() }; Assert-Unlocked
    Must-FailUnchanged 'fetch failure suppresses private exception' { Invoke-VaultRefresh $stage $password { throw 'PRIVATE-SENTINEL https://example.invalid/token' } }; Assert-Unlocked
    foreach ($bad in @('<html>PRIVATE-SENTINEL</html>','!!!PRIVATE-SENTINEL!!!','ss://PRIVATE-SENTINEL')) {
        $badFetch = { return $bad }.GetNewClosure()
        Must-FailUnchanged 'unsupported response' { Invoke-VaultRefresh $stage $password $badFetch }; Assert-Unlocked
    }
    Must-FailUnchanged 'invalid selection' { Invoke-VaultRefresh $stage $password $fetch { return -1 } }; Assert-Unlocked
    [IO.File]::WriteAllText($mode,'reject')
    Must-FailUnchanged 'native validation rejects candidate' { Invoke-VaultRefresh $stage $password $fetch } 'native-validation'; Assert-Unlocked
    [IO.File]::WriteAllText($mode,'ok')
    $held = [IO.File]::Open($vault,'Open','Read','Read')
    try { Must-FailUnchanged 'replacement blocked by open destination' { Invoke-VaultRefresh $stage $password $fetch } 'encrypted-replacement' } finally { $held.Dispose() }; Assert-Unlocked
    $result = Invoke-VaultRefresh $stage $password $fetch
    if ($result.supported -ne 2 -or $result.skipped -ne 1 -or -not $result.preserved) { throw 'Mixed-list or selection preservation failed.' }
    if ((Get-FileHash -LiteralPath $result.backup -Algorithm SHA256).Hash -ne $originalHash) { throw 'Backup is not the exact old ciphertext.' }
    $saved = Read-Vault $vault $password
    if ($saved.subscription.url -cne $document.subscription.url -or $saved.subscription.hwid -cne $document.subscription.hwid -or $saved.createdAtUtc -cne $document.createdAtUtc) { throw 'Metadata changed.' }
    if ((Get-RefreshNodeIdentity $saved.activeConfig.outbounds[0]) -cne (Get-RefreshNodeIdentity $node1)) { throw 'Node identity not preserved after reorder.' }
    Note 'PASS: mixed list; stored URL/HWID forwarded; same node retained after reorder; metadata preserved; encrypted backup equals previous ciphertext'
    $beforeSecond = (Get-FileHash -LiteralPath $vault -Algorithm SHA256).Hash
    $fetchState.body = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($link2))
    $result = Invoke-VaultRefresh $stage $password $fetch { return 0 }
    $saved = Read-Vault $vault $password
    if ((Get-RefreshNodeIdentity $saved.activeConfig.outbounds[0]) -cne (Get-RefreshNodeIdentity (Convert-Vless $link2))) { throw 'Selected new node was not saved.' }
    if ((Get-FileHash -LiteralPath $result.backup -Algorithm SHA256).Hash -ne $beforeSecond) { throw 'Second backup mismatch.' }
    Assert-Unlocked
    if (@(Get-ChildItem -LiteralPath $stage -Recurse -Filter '*.json').Count -ne 0) { throw 'Plaintext JSON file unexpectedly exists.' }
    if (@(Get-ChildItem -LiteralPath $private -Filter '*.tmp').Count -ne 0) { throw 'Encrypted temp remained.' }
    Note 'PASS: Base64 list; explicit new-node selection saved; same password unlocks new vault; lock released; no JSON files or refresh temp left'
    Note 'RESULT: PASS for implemented synthetic refresh checks only. NOT TESTED: provider request, real refresh, disk-full/unplug/power-loss, hostile races, all filesystem types or encrypted full node-list storage.'
} catch { Note ('RESULT: FAIL: ' + $_.Exception.Message); throw }
finally {
    if ($generated) { $generated.Dispose() }; if ($password) { $password.Dispose() }; if ($wrong) { $wrong.Dispose() }
    $env:TEMP = $oldTemp; $env:TMP = $oldTmp
    [IO.File]::WriteAllLines($report,$log.ToArray(),(New-Object Text.UTF8Encoding($true)))
    if ($owned) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
