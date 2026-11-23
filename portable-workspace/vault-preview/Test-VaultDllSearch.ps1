#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ToolDirectory)
# Run only against the owned full-copy baseline made by Run-VaultTests.
$ErrorActionPreference = 'Stop'
$names = @('vcruntime140.dll','vcruntime140_1.dll')
$preloaded = @((Get-Process -Id $PID).Modules | Where-Object { $_.ModuleName.ToLowerInvariant() -in $names })
$paths = @()
try {
    foreach ($name in $names) {
        $path = Join-Path $ToolDirectory ('lib\' + $name)
        # Non-executable invalid-image canary. Never load or compile attacker native code.
        $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $paths += $path
        try { $bytes = [Text.Encoding]::ASCII.GetBytes('VIC-A INVALID IMAGE CANARY'); $stream.Write($bytes, 0, $bytes.Length) }
        finally { $stream.Dispose() }
    }
    . (Join-Path $ToolDirectory 'Vault.Common.ps1')
    Initialize-VaultCrypto
    # Check exact runtime module locations, not just names returned by the import gate.
    $system = [Environment]::GetFolderPath('System')
    $loaded = @((Get-Process -Id $PID).Modules | Where-Object { $_.ModuleName.ToLowerInvariant() -in $names })
    if ($loaded.Count -lt 1) { throw 'Runtime location could not be confirmed.' }
    foreach ($module in $loaded) {
        $expected = Join-Path $system $module.ModuleName
        if (-not ([StringComparer]::OrdinalIgnoreCase).Equals([IO.Path]::GetFullPath($module.FileName), [IO.Path]::GetFullPath($expected))) {
            throw 'VC runtime was loaded from outside System32.'
        }
        Write-Host ('MODULE PASS: System32\' + $module.ModuleName)
    }
    if ($preloaded.Count -gt 0) {
        Write-Host 'LIMITATION: VC runtime already loaded before initialization; first-load shadowing is NOT established by this run.'
    } else {
        Write-Host 'PASS: crypto initialized despite invalid neighbouring runtime images; VC runtime was not preloaded before this test.'
        Write-Host 'This is a process-local regression test, not proof against a hostile host, injection or all loader states.'
    }
} finally {
    foreach ($path in $paths) { Remove-Item -LiteralPath $path -Force }
}
