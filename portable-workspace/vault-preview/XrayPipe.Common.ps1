#requires -Version 5.1
# Isolated next-stage transport. Not wired into the production launcher/updater yet.
$pipeDirectory = $PSScriptRoot
. (Join-Path (Split-Path -Parent $pipeDirectory) 'Workspace.Common.ps1')
function Initialize-XrayPipe {
    if ('VicAXrayPipe.Session' -as [type]) { return }
    $source = [IO.File]::ReadAllBytes((Join-Path $pipeDirectory 'XrayPipe.cs'))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $digest = ([BitConverter]::ToString($sha.ComputeHash($source))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
    if ($digest -cne '6123de3c87c2d636d46691033f86c96b4998d7e062c407ab2383c3b8e6a3acd5') { throw 'Xray pipe source integrity check failed.' }
    Add-Type -TypeDefinition ([Text.Encoding]::UTF8.GetString($source)) -ErrorAction Stop
}
function Test-XrayObjectInMemory([string]$Exe, $Config, [int]$TimeoutMs = 30000) {
    Initialize-XrayPipe
    Assert-ConfigObjectPolicy $Config
    $bytes = $null
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($Config | ConvertTo-Json -Depth 30 -Compress))
        [VicAXrayPipe.Session]::Validate($Exe, (Split-Path -Parent $Exe), $bytes, $TimeoutMs)
    } catch { throw 'In-memory Xray validation failed. No plaintext file or native diagnostics were published.' }
    finally { if ($bytes) { [Array]::Clear($bytes, 0, $bytes.Length) } }
}
function Start-XrayObjectInMemory([string]$Exe, $Config, [int]$InputTimeoutMs = 10000) {
    Initialize-XrayPipe
    Assert-ConfigObjectPolicy $Config
    $bytes = $null
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($Config | ConvertTo-Json -Depth 30 -Compress))
        return [VicAXrayPipe.Session]::Start($Exe, (Split-Path -Parent $Exe), $bytes, $InputTimeoutMs)
    } catch { throw 'In-memory Xray start failed. No plaintext file or native diagnostics were published.' }
    finally { if ($bytes) { [Array]::Clear($bytes, 0, $bytes.Length) } }
}

# Separate ownership acquisition from input delivery so the launcher can retain its lock on failed cleanup.
function Open-XrayRunSession([string]$Exe, $Config) {
    Initialize-XrayPipe
    Assert-ConfigObjectPolicy $Config
    return [VicAXrayPipe.Session]::BeginRun($Exe, (Split-Path -Parent $Exe))
}
function Send-XrayRunConfig($Session, $Config, [int]$InputTimeoutMs = 10000) {
    Assert-ConfigObjectPolicy $Config
    $bytes = $null
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($Config | ConvertTo-Json -Depth 30 -Compress))
        $Session.SendForRun($bytes, $InputTimeoutMs)
    } catch { throw 'Xray in-memory config delivery failed. Native diagnostics discarded.' }
    finally { if ($bytes) { [Array]::Clear($bytes, 0, $bytes.Length) } }
}
