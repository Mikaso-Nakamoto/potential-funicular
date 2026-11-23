#requires -Version 5.1
# New refresh core: synthetic Windows tests required before real-vault use.
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Workspace.Common.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'vault-preview\Vault.Common.ps1')
. (Join-Path $PSScriptRoot 'Native.Common.ps1')
function Get-RefreshNodeIdentity($Value) {
    function Sort-JsonValue($Item) {
        if ($null -eq $Item) { return $null }
        if ($Item -is [Collections.IDictionary]) {
            $result = [ordered]@{}
            foreach ($key in @($Item.Keys | Sort-Object)) { $result[$key] = Sort-JsonValue $Item[$key] }
            return $result
        }
        if ($Item -is [pscustomobject]) {
            $result = [ordered]@{}
            foreach ($key in @($Item.PSObject.Properties.Name | Sort-Object)) { $result[$key] = Sort-JsonValue $Item.$key }
            return $result
        }
        if ($Item -is [Collections.IEnumerable] -and $Item -isnot [string]) {
            $result = @(); foreach ($entry in $Item) { $result += ,(Sort-JsonValue $entry) }
            return ,$result
        }
        return $Item
    }
    return (Sort-JsonValue $Value | ConvertTo-Json -Depth 30 -Compress)
}
function Convert-RefreshSubscription([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text) -or $Text.Length -gt 4194304) { throw 'Subscription is empty or oversized.' }
    $Text = $Text.Trim().TrimStart([char]0xFEFF)
    if ($Text -match '<\s*(!doctype|html|head|body)\b') { throw 'HTML subscription is not supported.' }
    if ($Text -notmatch '(?m)^\s*[a-z][a-z0-9+.-]*://') {
        try {
            $encoded = ($Text -replace '\s','').Replace('-','+').Replace('_','/')
            $encoded = $encoded.PadRight($encoded.Length + ((4 - $encoded.Length % 4) % 4),'=')
            $utf8 = New-Object Text.UTF8Encoding($false,$true)
            $Text = $utf8.GetString([Convert]::FromBase64String($encoded)).Trim().TrimStart([char]0xFEFF)
        } catch { throw 'Subscription is not a supported list or Base64 UTF-8 list.' }
    }
    $lines = @($Text -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($lines.Count -gt 4096) { throw 'Too many subscription entries.' }
    $nodes = @(); $skipped = 0
    foreach ($line in $lines) {
        try { $nodes += ,(Convert-Vless $line) } catch { $skipped++ }
    }
    if ($nodes.Count -eq 0) { throw 'No supported nodes. Vault unchanged.' }
    return @{ nodes = $nodes; skipped = $skipped }
}
function Write-RefreshReplacement([string]$Path, $Document, [Security.SecureString]$Password, [string]$ExpectedHash) {
    # Caller holds the shared session lock. Re-authenticate current file before any write.
    $null = Read-Vault $Path $Password
    Assert-VaultDocument $Document
    $temp = $Path + '.refresh-' + [Guid]::NewGuid().ToString('N') + '.tmp'
    $backup = $Path + '.backup-' + [Guid]::NewGuid().ToString('N')
    $ownedTemp = $false; $plain = $null; $verified = $null
    try {
        if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $ExpectedHash) { throw 'Vault changed before replacement.' }
        $plain = [Text.Encoding]::UTF8.GetBytes(($Document | ConvertTo-Json -Depth 30 -Compress))
        $sealed = [VicAVault.Crypto]::Seal($plain,$Password)
        $verified = [VicAVault.Crypto]::Open($sealed,$Password)
        if ($plain.Length -ne $verified.Length) { throw 'Encrypted read-back mismatch.' }
        $difference = 0
        for ($i=0; $i -lt $plain.Length; $i++) { $difference = $difference -bor ($plain[$i] -bxor $verified[$i]) }
        if ($difference -ne 0) { throw 'Encrypted read-back mismatch.' }
        $stream = [IO.File]::Open($temp,'CreateNew','Write','None'); $ownedTemp = $true
        try { $stream.Write($sealed,0,$sealed.Length); $stream.Flush($true) } finally { $stream.Dispose() }
        $null = Read-Vault $temp $Password
        if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $ExpectedHash) { throw 'Vault changed before publication.' }
        # No delete/move fallback. Filesystem must support File.Replace. Encrypted backup is retained.
        [IO.File]::Replace($temp,$Path,$backup)
        return $backup
    } finally {
        if ($plain) { [Array]::Clear($plain,0,$plain.Length) }
        if ($verified) { [Array]::Clear($verified,0,$verified.Length) }
        if ($ownedTemp -and (Test-Path -LiteralPath $temp)) {
            try { Remove-Item -LiteralPath $temp -Force } catch { Write-Warning 'Encrypted refresh stage retained.' }
        }
    }
}
function Invoke-VaultRefresh([string]$Root, [Security.SecureString]$Password, [scriptblock]$Fetch, [scriptblock]$Choose, [switch]$CheckOnly) {
    $lock = $null; $document = $null; $response = $null; $parsed = $null; $next = $null
    $oldTemp = $env:TEMP; $oldTmp = $env:TMP
    $phase = 'lock'
    try {
        $Root = Get-Workspace $Root
        $lock = [IO.File]::Open((Join-Path $Root '.session.lock'),'OpenOrCreate','ReadWrite','None')
        if (Test-ProfileBusy (Join-Path $Root 'private\profile')) { throw 'Browser profile busy.' }
        # Crypto/import helpers may compile during unlock; keep their TEMP on the Runtime SSD too.
        $phase = 'temporary-directory'
        $tmp = Join-Path $Root 'private\tmp'
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $env:TEMP = $tmp; $env:TMP = $tmp
        $phase = 'unlock'
        $path = Join-Path $Root 'private\workspace.vault'
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        $document = Read-Vault $path $Password
        $phase = 'fetch'
        if ($Fetch) { $response = & $Fetch ([Uri]$document.subscription.url) ([string]$document.subscription.hwid) }
        else { $response = Get-VicaTunnelSubscription $Root $document }
        $phase = 'parse'
        $parsed = Convert-RefreshSubscription $response
        $nodes = @($parsed.nodes)
        $previous = Get-RefreshNodeIdentity $document.activeConfig.outbounds[0]
        $matches = @()
        for ($i=0; $i -lt $nodes.Count; $i++) {
            if ((Get-RefreshNodeIdentity $nodes[$i]) -ceq $previous) { $matches += $i }
        }
        $phase = 'selection'
        $selected = -1
        if ($Choose) { $selected = & $Choose $nodes $matches }
        elseif ($matches.Count -eq 1) { $selected = $matches[0] }
        else {
            Write-Host ('Supported nodes: ' + $nodes.Count + '; skipped: ' + $parsed.skipped)
            for ($i=0; $i -lt $nodes.Count; $i++) { Write-Host ('Node ' + ($i+1)) }
            $number = 0
            if (-not [int]::TryParse((Read-Host 'Node number'),[ref]$number)) { throw 'Invalid selection.' }
            $selected = $number - 1
        }
        if ($selected -isnot [int] -or $selected -lt 0 -or $selected -ge $nodes.Count) { throw 'Invalid selection.' }
        $next = $document | ConvertTo-Json -Depth 30 -Compress | ConvertFrom-Json
        $next.activeConfig.outbounds = @($nodes[$selected])
        $next = $next | ConvertTo-Json -Depth 30 -Compress | ConvertFrom-Json
        Assert-VaultDocument $next
        $phase = 'native-validation'
        Test-XrayObjectInMemory (Join-Path $Root 'Xray\xray.exe') $next.activeConfig
        if ($CheckOnly) {
            if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $hash) { throw 'Vault changed externally.' }
            return @{ supported = $nodes.Count; skipped = $parsed.skipped; checkedOnly = $true }
        }
        $phase = 'publication-confirmation'
        Write-Warning 'Working encrypted vault will be replaced. Encrypted previous version will be retained. Native validation is not a connectivity test.'
        if ((Read-Host 'Type UPDATE to publish; anything else cancels') -cne 'UPDATE') { throw 'Cancelled.' }
        $phase = 'encrypted-replacement'
        $backup = Write-RefreshReplacement $path $next $Password $hash
        return @{ backup = $backup; supported = $nodes.Count; skipped = $parsed.skipped; preserved = ($matches.Count -eq 1 -and $selected -eq $matches[0]) }
    } catch {
        # Never forward fetch/parser/native exception text: it may contain URL, node or response data.
        throw ('Vault refresh stopped at: ' + $phase + '. No plaintext fallback. Do not share secrets; inspect encrypted vault/backup if publication failed.')
    } finally {
        $document = $null; $response = $null; $parsed = $null; $next = $null
        $env:TEMP = $oldTemp; $env:TMP = $oldTmp
        if ($lock) { $lock.Dispose() }
    }
}
