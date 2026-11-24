#requires -Version 5.1
$v03Package = Split-Path -Parent $PSScriptRoot
. (Join-Path $v03Package 'Password.Common.ps1')
function Read-V03Bytes([string]$Path) { return ,(Read-TestEnvelope $Path) }
function Read-Vault([string]$Path,[Security.SecureString]$Password) {
    Initialize-PasswordPreview
    $plain = $null
    try {
        $plain = [VicaPasswordPreview.Envelope]::Open((Read-V03Bytes $Path),$Password,$false)
        $utf8 = New-Object Text.UTF8Encoding($false,$true)
        $doc = $utf8.GetString($plain) | ConvertFrom-Json
        Assert-VaultDocument $doc
        return $doc
    } catch { throw 'Password vault could not be opened. No V02/plaintext fallback.' }
    finally { if ($plain) { [Array]::Clear($plain,0,$plain.Length) } }
}
function Write-V03Stage([string]$Path,[byte[]]$Bytes,[Security.SecureString]$Password,[Security.SecureString]$Recovery = $null) {
    $stream = [IO.File]::Open($Path,'CreateNew','Write','None')
    try { $stream.Write($Bytes,0,$Bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    $disk = Read-V03Bytes $Path
    $plain = $null
    try {
        $null = Read-Vault $Path $Password
        if ($Recovery) {
            $plain = [VicaPasswordPreview.Envelope]::Open($disk,$Recovery,$true)
            Assert-VaultDocument ((New-Object Text.UTF8Encoding($false,$true)).GetString($plain) | ConvertFrom-Json)
        }
    } finally { if ($plain) { [Array]::Clear($plain,0,$plain.Length) } }
}
function Write-RefreshReplacement([string]$Path,$Document,[Security.SecureString]$Password,[string]$ExpectedHash) {
    $null = Read-Vault $Path $Password
    Assert-VaultDocument $Document
    $plain = $null; $owned = $false
    $stage = $Path + '.refresh-' + [Guid]::NewGuid().ToString('N')
    try {
        $original = Read-V03Bytes $Path
        if ((Get-TestCipherHash $original) -cne $ExpectedHash) { throw 'Vault changed.' }
        $plain = [Text.Encoding]::UTF8.GetBytes(($Document | ConvertTo-Json -Depth 30 -Compress))
        $bytes = [VicaPasswordPreview.Envelope]::UpdatePayload($original,$Password,$plain)
        $owned = $true
        Write-V03Stage $stage $bytes $Password
        if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -cne $ExpectedHash) { throw 'Vault changed.' }
        $backup = $Path + '.backup-' + [Guid]::NewGuid().ToString('N')
        [IO.File]::Replace($stage,$Path,$backup)
        return $backup
    } finally {
        if ($plain) { [Array]::Clear($plain,0,$plain.Length) }
        if ($owned -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Force }
    }
}
