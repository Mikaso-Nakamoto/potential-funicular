#requires -Version 5.1
[CmdletBinding()]
param([string]$Base='Z:\Iran\Browser')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Base=[IO.Path]::GetFullPath($Base).TrimEnd('\')
$source=Join-Path $Base 'VIC-A-New'
$destination=Join-Path $Base 'VIC-A'
$stage=Join-Path $Base ('.vica-organize-'+[Guid]::NewGuid().ToString('N'))
$locks=New-Object 'Collections.Generic.List[IDisposable]'
$owned=$false; $phase='preflight'; $count=0
function Assert-LocalPath([string]$Path) {
    $p=[IO.Path]::GetFullPath($Path)
    if ($p -notmatch '^[A-Za-z]:\\') { throw 'Local absolute drive required.' }
    while ($p) {
        if (Test-Path -LiteralPath $p) {
            if ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Links/junctions prohibited.' }
        }
        $next=[IO.Path]::GetDirectoryName($p)
        if ($next -eq $p) { break }; $p=$next
    }
}
function Copy-VerifiedTree([string]$From,[string]$To,[switch]$PrivateTree) {
    Assert-LocalPath $From; Assert-LocalPath $To
    New-Item -ItemType Directory -Path $To -ErrorAction Stop | Out-Null
    foreach ($entry in @(Get-ChildItem -LiteralPath $From -Force)) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Link in source. No publication.' }
        if ($PrivateTree -and $entry.Name -ceq 'tmp') { continue }
        if ($entry.Name -ceq '.session.lock') { continue }
        $target=Join-Path $To $entry.Name
        if ($entry.PSIsContainer) { Copy-VerifiedTree $entry.FullName $target }
        else {
            $inputFile=$null; $outputFile=$null; $sha=$null
            try {
                $inputFile=[IO.File]::Open($entry.FullName,'Open','Read','Read')
                $outputFile=[IO.File]::Open($target,'CreateNew','ReadWrite','None')
                $inputFile.CopyTo($outputFile,65536); $outputFile.Flush($true)
                $sha=[Security.Cryptography.SHA256]::Create()
                $inputFile.Position=0; $outputFile.Position=0
                $a=[Convert]::ToBase64String($sha.ComputeHash($inputFile))
                $b=[Convert]::ToBase64String($sha.ComputeHash($outputFile))
                if ($a -cne $b -or $inputFile.Length -ne $outputFile.Length) { throw 'Copy verification failed.' }
                $script:count++
            } finally {
                if ($sha) { $sha.Dispose() }; if ($outputFile) { $outputFile.Dispose() }; if ($inputFile) { $inputFile.Dispose() }
            }
        }
    }
}
try {
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Windows PowerShell 5.1 x64 required.' }
    Assert-LocalPath $Base; Assert-LocalPath $source; Assert-LocalPath $destination
    if (Test-Path -LiteralPath $destination) { throw 'Destination already exists. No overwrite/merge.' }
    if (-not (Test-Path -LiteralPath (Join-Path $source 'Runtime\private\workspace.vault') -PathType Leaf)) { throw 'Working password edition not found.' }
    if (@(Get-Process -Name @('librewolf','xray') -ErrorAction SilentlyContinue).Count) { throw 'Close browsers and Xray normally. No process will be killed.' }
    if (@(Get-NetTCPConnection -State Listen -LocalPort 17890 -ErrorAction SilentlyContinue).Count) { throw 'Tunnel port busy.' }
    $legacy=@((Join-Path $Base 'Runtime'),(Join-Path $Base 'Working-Vault-Preview\WorkingRuntime'))
    foreach ($runtime in (@((Join-Path $source 'Runtime'))+$legacy)) {
        if (Test-Path -LiteralPath $runtime -PathType Container) {
            Assert-LocalPath $runtime
            $locks.Add([IO.File]::Open((Join-Path $runtime '.session.lock'),'OpenOrCreate','ReadWrite','None'))
        }
    }
    Write-Host ('New standalone installation: '+$destination)
    Write-Host 'Same encrypted vault, password, recovery words, HWID and current subscription. Originals stay untouched.'
    Write-Host 'Older profiles/downloads will be preserved separately, NOT merged into the active browser profile.'
    Write-Host 'Needs space for a full copy. No downloads, no deletion of old folders.'
    if ((Read-Host 'Type COPY to proceed; Enter cancels') -cne 'COPY') { return }
    $phase='copy'
    New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null; $owned=$true
    $payload=Join-Path $PSScriptRoot 'Application.zip'
    $expected=(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Application.sha256') -Raw).Trim()
    if ((Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash -cne $expected) { throw 'Application archive mismatch.' }
    Expand-Archive -LiteralPath $payload -DestinationPath $stage -ErrorAction Stop
    $runtimeTarget=Join-Path $stage 'Runtime'
    New-Item -ItemType Directory -Path $runtimeTarget | Out-Null
    foreach ($name in @('Xray','LibreWolf')) { Copy-VerifiedTree (Join-Path $source ('Runtime\'+$name)) (Join-Path $runtimeTarget $name) }
    Copy-VerifiedTree (Join-Path $source 'Runtime\private') (Join-Path $runtimeTarget 'private') -PrivateTree
    # The already working package owns its audited native dependency. Never search arbitrary DLLs.
    Copy-VerifiedTree (Join-Path $source 'vault-preview\lib') (Join-Path $stage 'vault-preview\lib')
    $i=0
    foreach ($old in $legacy) {
        $i++
        foreach ($name in @('profile','downloads')) {
            $path=Join-Path $old ('private\'+$name)
            if (Test-Path -LiteralPath $path -PathType Container) {
                $container=Join-Path $stage ('Preserved-Older-Data\source-'+$i)
                New-Item -ItemType Directory -Path $container -Force | Out-Null
                Copy-VerifiedTree $path (Join-Path $container $name)
            }
        }
    }
    $phase='browser-signature'
    $browsers=@(Get-ChildItem -LiteralPath (Join-Path $runtimeTarget 'LibreWolf') -Recurse -File -Filter librewolf.exe)
    if ($browsers.Count -ne 1) { throw 'Expected one browser.' }
    $signature=Get-AuthenticodeSignature -LiteralPath $browsers[0].FullName
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false) -cne 'OSSign (Scheibling Consulting AB)') { throw 'Official browser signature required.' }
    $phase='native-containment-check'
    $ps=Join-Path $PSHOME 'powershell.exe'
    & $ps -NoProfile -File (Join-Path $stage 'vica\Test-ContainedSession.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Containment validation failed.' }
    $phase='password-and-config-check'
    Write-Host 'Enter CURRENT working password below. Same password/words will remain valid.'
    & $ps -NoProfile -File (Join-Path $stage 'vica\Start-VicaSession.ps1') -Root $runtimeTarget -ValidateOnly
    if ($LASTEXITCODE -ne 0) { throw 'Authentication/config validation failed. Nothing published.' }
    $phase='publication'
    [IO.Directory]::Move($stage,$destination); $owned=$false
    Write-Host ('SUCCESS. Verified copied files: '+$count) -ForegroundColor Green
    Write-Host ('Launch: '+(Join-Path $destination 'Start.cmd')) -ForegroundColor Green
    Write-Host 'Password and recovery words UNCHANGED. Test browser/YouTube/subscription before deleting any old folders.'
    Write-Host 'Old vaults/configs outside the current installation were NOT merged. Keep originals until reviewed.'
} catch {
    Write-Warning ('Stopped at: '+$phase+'. No old folders were removed. Check free space, close applications and verify password. Secret error details suppressed.')
} finally {
    foreach ($l in $locks) { $l.Dispose() }
    if ($owned -and (Test-Path -LiteralPath $stage)) {
        # A failed copy can contain plaintext profile/downloads: leave it explicit rather than claim secure erasure.
        Write-Warning ('Incomplete copy retained at '+$stage+'. Do not launch it. Originals remain valid; this partial copy can be deleted after closing all programs.')
    }
    Read-Host 'Enter to close' | Out-Null
}
