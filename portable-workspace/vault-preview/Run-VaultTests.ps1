#requires -Version 5.1
# Offline test runner after dependency installation. No Runtime/subscription/browser access.
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $PSVersionTable.PSVersion.Major -ne 5) {
    throw 'Use 64-bit Windows PowerShell 5.1, not PowerShell 7 or 32-bit PowerShell.'
}
$tool = $PSScriptRoot
$exe = Join-Path $PSHOME 'powershell.exe'
$report = Join-Path $tool 'vault-test-report.txt'
$lines = New-Object 'Collections.Generic.List[string]'
$stage = Join-Path $tool ('.vault-negative-' + [Guid]::NewGuid().ToString('N'))
$owned = $false
function Run-TestProcess([string]$Name, [string]$Script, [string]$Extra = '') {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "' + $Script + '" ' + $Extra
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    # Compiler/test temporary files stay in the owned test directory on this drive.
    $psi.EnvironmentVariables['TEMP'] = $stage
    $psi.EnvironmentVariables['TMP'] = $stage
    $process = $null
    try {
        $process = [Diagnostics.Process]::Start($psi)
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(120000)) {
            $process.Kill(); $process.WaitForExit()
            throw ('Timeout: ' + $Name)
        }
        $output = $stdout.GetAwaiter().GetResult()
        $errorOutput = $stderr.GetAwaiter().GetResult()
        # All child input is public synthetic data; no user config is passed.
        Write-Host $output
        $lines.Add(('=== ' + $Name + ' ==='))
        $lines.Add($output)
        if ($process.ExitCode -ne 0) {
            $lines.Add($errorOutput)
            throw ('Test failed: ' + $Name + '. See vault-test-report.txt.')
        }
    } finally { if ($process) { $process.Dispose() } }
}
try {
    New-Item -ItemType Directory -Path $stage | Out-Null
    $owned = $true
    Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $tool) 'Workspace.Common.ps1') -Destination $stage
    $lines.Add('VIC-A isolated vault tests R3 (generated-only creation, System32 dependencies); only synthetic data. No Runtime access.')
    $lines.Add(('CLR: ' + [Environment]::Version.ToString() + '; OS: ' + [Environment]::OSVersion.VersionString))
    $lines.Add(('Windows PowerShell: ' + $PSVersionTable.PSVersion.ToString() + '; x64: ' + [Environment]::Is64BitProcess))
    # Bind the result to exact inputs, not just a screenshot or mutable release label.
    $hashFiles = @(Get-ChildItem -LiteralPath $tool -File | Where-Object { $_.Extension -in @('.ps1','.cs') })
    foreach ($dir in @('lib','words','tests')) { $hashFiles += @(Get-ChildItem -LiteralPath (Join-Path $tool $dir) -File) }
    foreach ($file in ($hashFiles | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($tool.Length).TrimStart('\','/')
        $lines.Add(('SHA256 ' + (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash + '  ' + $relative))
    }
    $lines.Add(('SHA256 ' + (Get-FileHash -LiteralPath (Join-Path (Split-Path -Parent $tool) 'Workspace.Common.ps1') -Algorithm SHA256).Hash + '  ../Workspace.Common.ps1'))
    Run-TestProcess 'Synthetic PE inspector' (Join-Path $tool 'Test-SodiumPe.ps1')
    Run-TestProcess 'PE dependency inspection' (Join-Path $tool 'Test-SodiumImports.ps1') ('-Path "' + (Join-Path $tool 'lib\vica-sodium.dll') + '"')
    Run-TestProcess 'Generated passphrase sampling' (Join-Path $tool 'Test-VaultGenerator.ps1')
    Run-TestProcess 'Crypto and normalization' (Join-Path $tool 'Test-Vault.ps1')
    Run-TestProcess 'Vault file I/O and policy' (Join-Path $tool 'Test-VaultIO.ps1')
    foreach ($case in @('baseline','dll','manifest','source','gate','pe')) {
        $copy = Join-Path $stage $case
        # Full source/fixture/dependency copy. Never copy reports or nested scratch directories.
        New-Item -ItemType Directory -Path $copy | Out-Null
        foreach ($file in Get-ChildItem -LiteralPath $tool -File) {
            if ($file.Extension -in @('.ps1','.cs','.md','.py')) { Copy-Item -LiteralPath $file.FullName -Destination $copy }
        }
        foreach ($directory in @('lib','words','tests')) {
            Copy-Item -LiteralPath (Join-Path $tool $directory) -Destination (Join-Path $copy $directory) -Recurse
        }
        switch ($case) {
            'dll' { [IO.File]::WriteAllBytes((Join-Path $copy 'lib\vica-sodium.dll'), (New-Object byte[] 256)) }
            'manifest' {
                $path = Join-Path $copy 'lib\dependency.json'
                $manifest = [IO.File]::ReadAllText($path) | ConvertFrom-Json
                $manifest.archiveSha256 = 'incorrect-synthetic-value'
                [IO.File]::WriteAllText($path, ($manifest | ConvertTo-Json))
            }
            'gate' { [IO.File]::AppendAllText((Join-Path $copy 'Test-SodiumImports.ps1'), ([Environment]::NewLine + '# synthetic mutation' + [Environment]::NewLine)) }
            'pe' { [IO.File]::AppendAllText((Join-Path $copy 'SodiumPe.cs'), ([Environment]::NewLine + '// synthetic mutation' + [Environment]::NewLine)) }
            'source' { [IO.File]::AppendAllText((Join-Path $copy 'VaultCrypto.cs'), ([Environment]::NewLine + '// synthetic mutation' + [Environment]::NewLine)) }
        }
        if ($case -eq 'baseline') {
            Run-TestProcess 'Full-copy baseline crypto' (Join-Path $copy 'Test-Vault.ps1')
            Run-TestProcess 'Full-copy baseline I/O' (Join-Path $copy 'Test-VaultIO.ps1')
            Run-TestProcess 'Neighbour dependency canary' (Join-Path $tool 'Test-VaultDllSearch.ps1') ('-ToolDirectory "' + $copy + '"')
            continue
        }
        Run-TestProcess ('Integrity rejection: ' + $case) (Join-Path $tool 'Test-VaultLoadFailure.ps1') ('-ToolDirectory "' + $copy + '" -Case ' + $case)
    }
    $lines.Add('RESULT: PASS for the implemented tests only.')
    $lines.Add('NOT TESTED: missing AES hardware, hostile ZIP archives, disk-full, power failure, physical unplug, full migration or Xray integration.')
    Write-Host 'PASS: implemented tests completed. Send vault-test-report.txt; do not migrate yet.' -ForegroundColor Green
} catch {
    $lines.Add(('RESULT: FAIL. ' + $_.Exception.Message))
    Write-Host 'FAIL: stop here. Send vault-test-report.txt. Do not change Runtime.' -ForegroundColor Red
    throw
} finally {
    [IO.File]::WriteAllLines($report, $lines.ToArray(), (New-Object Text.UTF8Encoding($true)))
    if ($owned) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
