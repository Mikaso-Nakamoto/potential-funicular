#requires -Version 5.1
# Synthetic offline test; no network requests.
. (Join-Path $PSScriptRoot 'Workspace.Common.ps1')
$expected = 'aabbccdd-1122-4333-8444-123456789abc'
if ((Convert-DeviceHwid 'AABBCCDD-1122-4333-8444-123456789ABC') -cne $expected) { throw 'Device UUID normalization failed.' }
foreach ($invalid in @('', 'not-a-guid', '00000000-0000-0000-0000-000000000000', "aabbccdd-1122-4333-8444-123456789abc`r`nx-header: injected")) {
    $rejected = $false
    try { $null = Convert-DeviceHwid $invalid } catch { $rejected = $true }
    if (-not $rejected) { throw 'Invalid device UUID accepted.' }
}
Write-Host 'Synthetic device UUID tests passed.'
