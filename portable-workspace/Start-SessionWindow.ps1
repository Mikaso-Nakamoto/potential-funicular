#requires -Version 5.1
[CmdletBinding()]
param([string]$Root = '')
$ErrorActionPreference = 'Stop'
try {
    & (Join-Path $PSScriptRoot 'Start-Workspace.ps1') -Root $Root
} catch {
    $message = $_.Exception.Message
    if ($message -match '^Managed session failed at: (runtime-path|session-lock|native-config-validation|port-check|browser-path|profile-policy|job-contained-xray-start|owned-socks-readiness|browser-start|browser-monitor)\. No automatic takeover or policy bypass was attempted\.$') {
        Write-Host $message -ForegroundColor Red
    } else {
        Write-Host 'Managed session could not start. Check required scripts, runtime path and execution policy. No automatic bypass.' -ForegroundColor Red
    }
    Write-Host 'This window remains open so the error does not disappear. No configuration was automatically replaced.'
    $null = Read-Host 'Press Enter to close this session window'
    exit 1
}
