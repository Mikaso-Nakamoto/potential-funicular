#requires -Version 5.1
$previewDirectory = $PSScriptRoot
. (Join-Path $PSScriptRoot 'vault-preview\Vault.Common.ps1')
function Initialize-PasswordPreview {
    Assert-VaultSupportIntegrity
    if ('VicaPasswordPreview.Envelope' -as [type]) { return }
    if ('VicAVault.Crypto' -as [type]) { throw 'Start this test in a fresh PowerShell process.' }
    $dll = [IO.Path]::GetFullPath((Join-Path $previewDirectory 'vault-preview\lib\vica-sodium.dll'))
    $manifestPath = Join-Path $previewDirectory 'vault-preview\lib\dependency.json'
    if ((Get-Item -LiteralPath $manifestPath).Length -gt 4096) { throw 'Invalid crypto manifest.' }
    $manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    if ($manifest.version -ne '1.0.22' -or $manifest.build -ne 'msvc-v143-x64-release' -or $manifest.archiveSha256 -ne '3e03a726fac4bc09cb61d8f29d658ef7a5eca0811de59082130414f7ca2e4279' -or
        (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash -ne $manifest.dllSha256) { throw 'Crypto dependency integrity mismatch.' }
    $base = Join-Path $previewDirectory 'vault-preview\VaultCrypto.cs'
    if ((Get-FileHash -LiteralPath $base -Algorithm SHA256).Hash -ne '9de76c76388574a64b031e4684c33e42864fd09d098a50dc7dc50698414476cb') { throw 'Base crypto source mismatch.' }
    $extra = Join-Path $previewDirectory 'PasswordEnvelope.cs'
    if ((Get-FileHash -LiteralPath $extra -Algorithm SHA256).Hash -ne '3bb61ac3a16dc32378e4b77e33e807e9caf11c68bdc88aafd5c8be631043545d') { throw 'Password envelope source mismatch.' }
    $selfTests = Join-Path $previewDirectory 'PasswordSelfTests.cs'
    if ((Get-FileHash -LiteralPath $selfTests -Algorithm SHA256).Hash -ne 'de7b49f1453892e6f91a723922630772a3895c84742dfb90356ba0abf4fa0df2') { throw 'Self-check source mismatch.' }
    & (Join-Path $previewDirectory 'vault-preview\Test-SodiumImports.ps1') -Path $dll
    $source = [IO.File]::ReadAllText($base).Replace('__SODIUM_DLL__',$dll.Replace('"','""')) + "`n" + [IO.File]::ReadAllText($extra) + "`n" + [IO.File]::ReadAllText($selfTests)
    Add-Type -TypeDefinition $source -ErrorAction Stop
    [VicAVault.Crypto]::CheckSupport()
}
function Read-TestEnvelope([string]$Path) {
    $stream = [IO.File]::Open($Path,'Open','Read','Read')
    try {
        if ($stream.Length -lt 380 -or $stream.Length -gt 1048956) { throw 'Invalid test envelope size.' }
        $bytes = New-Object byte[] ([int]$stream.Length); $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $stream.Read($bytes,$offset,$bytes.Length-$offset)
            if ($read -eq 0) { throw 'Truncated test envelope.' }; $offset += $read
        }
        if ($stream.ReadByte() -ne -1) { throw 'Test envelope changed during read.' }
        return ,$bytes
    } finally { $stream.Dispose() }
}
function Get-TestCipherHash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','') }
    finally { $sha.Dispose() }
}
function Assert-TestPayload([byte[]]$Envelope,[Security.SecureString]$Credential,[bool]$Recovery) {
    $plain = $null
    try {
        $plain = [VicaPasswordPreview.Envelope]::Open($Envelope,$Credential,$Recovery)
        if ([Text.Encoding]::UTF8.GetString($plain) -cne 'VIC-A SYNTHETIC PASSWORD TEST ONLY') { throw 'Unexpected test payload.' }
    } finally { if ($plain) { [Array]::Clear($plain,0,$plain.Length) } }
}
function Write-TestEnvelope([string]$Path,[byte[]]$Envelope,[Security.SecureString]$Verify,[string]$ExpectedHash = '',[Security.SecureString]$RecoveryVerify = $null) {
    $stage = $Path + '.stage-' + [Guid]::NewGuid().ToString('N'); $owned = $false
    try {
        $stream = [IO.File]::Open($stage,'CreateNew','Write','None'); $owned = $true
        try { $stream.Write($Envelope,0,$Envelope.Length); $stream.Flush($true) } finally { $stream.Dispose() }
        $disk = Read-TestEnvelope $stage
        Assert-TestPayload $disk $Verify $false
        if ($RecoveryVerify) { Assert-TestPayload $disk $RecoveryVerify $true }
        if ($ExpectedHash) {
            if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $ExpectedHash) { throw 'Test envelope changed externally.' }
            [IO.File]::Replace($stage,$Path,($Path + '.backup-' + [Guid]::NewGuid().ToString('N')))
        } else { [IO.File]::Move($stage,$Path) }
    } finally { if ($owned -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Force } }
}
