#requires -Version 5.1
function Start-OwnedWorkspaceXray([string]$Exe,[string]$Config,[string]$Directory,[switch]$ValidateOnly) {
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) { throw 'Owned launcher requires 64-bit Windows PowerShell.' }
    $source = Join-Path $PSScriptRoot 'WorkspaceJob.cs'
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne '0a349afc3586cd44bc6d1b1b1e206c52db8f4943d1946680a11df2339ddc425b') { throw 'Job helper integrity check failed.' }
    if (-not ('VicaWorkspace.OwnedXray' -as [type])) { Add-Type -TypeDefinition ([IO.File]::ReadAllText($source)) -ErrorAction Stop }
    return [VicaWorkspace.OwnedXray]::Start($Exe,$Config,$Directory,[bool]$ValidateOnly)
}
function Stop-OwnedWorkspaceXray($Owner) {
    if ($null -eq $Owner) { return }
    while (-not $Owner.CleanupConfirmed) {
        try { $Owner.Dispose() } catch { Write-Warning 'Owned Xray cleanup failed; retaining session lock.' }
        if (-not $Owner.CleanupConfirmed) {
            Write-Warning 'Owned Xray exit not confirmed; session lock remains held. Do not force-close this window.'
            Start-Sleep -Seconds 1
        }
    }
}

function Test-OwnedWorkspaceConfig([string]$Exe,[string]$Config) {
    Assert-ConfigPolicy $Config
    $validation = $null
    try {
        $validation = Start-OwnedWorkspaceXray $Exe $Config (Split-Path -Parent $Exe) -ValidateOnly
        $timer = [Diagnostics.Stopwatch]::StartNew()
        while (-not $validation.HasExited -and $timer.Elapsed.TotalSeconds -lt 30) { Start-Sleep -Milliseconds 100 }
        if (-not $validation.HasExited -or $validation.ExitCode -ne 0) { throw 'Owned native config validation failed or timed out. Diagnostics suppressed.' }
    } finally { Stop-OwnedWorkspaceXray $validation }
}
