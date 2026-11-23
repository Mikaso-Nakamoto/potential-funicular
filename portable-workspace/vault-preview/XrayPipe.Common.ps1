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
    if ($digest -cne '02c1b535e49a14afff1693aea2328a754a2eba987f01eeb7e35216a9907ca3a7') { throw 'Xray pipe source integrity check failed.' }
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
