#requires -Version 5.1
function Assert-VicaPlatform {
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Use 64-bit Windows PowerShell 5.1.' }
}
function Initialize-VicaDependency([string]$PackageRoot,[string]$ExistingSupport) {
    # Reuse the dependency already installed from the official source; no downloads or Runtime writes.
    $destination = Join-Path $PackageRoot 'vault-preview\lib'
    if (Test-Path -LiteralPath $destination) {
        if (-not (Test-Path -LiteralPath (Join-Path $destination 'vica-sodium.dll')) -or -not (Test-Path -LiteralPath (Join-Path $destination 'dependency.json'))) { throw 'Incomplete package dependency directory. Do not overwrite it blindly.' }
        return
    }
    $source = Join-Path $ExistingSupport 'vault-preview\lib'
    $manifestPath = Join-Path $source 'dependency.json'
    if ((Get-Item -LiteralPath $manifestPath).Length -gt 4096) { throw 'Invalid installed manifest.' }
    $manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    if ($manifest.version -ne '1.0.22' -or $manifest.build -ne 'msvc-v143-x64-release' -or $manifest.archiveSha256 -ne '3e03a726fac4bc09cb61d8f29d658ef7a5eca0811de59082130414f7ca2e4279') { throw 'Unexpected installed dependency provenance.' }
    $dll = Join-Path $source 'vica-sodium.dll'
    if ((Get-Item -LiteralPath $dll).Length -gt 16777216 -or (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash -ne $manifest.dllSha256) { throw 'Installed dependency hash mismatch.' }
    $stage = Join-Path (Split-Path -Parent $destination) ('.lib-' + [Guid]::NewGuid().ToString('N'))
    $owned = $false
    try {
        New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null; $owned = $true
        Copy-Item -LiteralPath $dll -Destination (Join-Path $stage 'vica-sodium.dll') -ErrorAction Stop
        Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $stage 'dependency.json') -ErrorAction Stop
        if ((Get-FileHash -LiteralPath (Join-Path $stage 'vica-sodium.dll') -Algorithm SHA256).Hash -ne $manifest.dllSha256 -or
            (Get-FileHash -LiteralPath (Join-Path $stage 'dependency.json') -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash) { throw 'Dependency changed during copy.' }
        [IO.Directory]::Move($stage,$destination)
    } finally { if ($owned -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Recurse -Force } }
    # Vault.Common performs its source checks, DLL hash and signature-verified System32 import audit again at unlock.
}
