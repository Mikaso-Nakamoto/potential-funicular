#requires -Version 5.1
# Synthetic offline tests. Does not connect to any server or execute Xray.
. (Join-Path $PSScriptRoot 'Workspace.Common.ps1')
$path = Join-Path ([IO.Path]::GetTempPath()) ('workspace-policy-test-' + [Guid]::NewGuid().ToString('N') + '.json')
function New-TestConfig {
    return @{
        log = @{ loglevel = 'none' }
        inbounds = @(@{ listen = '127.0.0.1'; port = 17890; protocol = 'socks'; settings = @{ auth = 'noauth'; udp = $false } })
        outbounds = @((Convert-Vless 'vless://00000000-0000-4000-8000-000000000001@example.invalid:443?security=tls&type=tcp'))
    }
}
function Check-Policy($Config, [bool]$ShouldPass) {
    [IO.File]::WriteAllText($path, ($Config | ConvertTo-Json -Depth 20))
    $passed = $true
    try { Assert-ConfigPolicy $path } catch { $passed = $false }
    if ($passed -ne $ShouldPass) { throw 'Crypto policy regression test failed.' }
}
try {
    Check-Policy (New-TestConfig) $true
    $c = New-TestConfig; $c.outbounds[0].streamSettings.tlsSettings.allowInsecure = $true; Check-Policy $c $false
    $c = New-TestConfig; $c.outbounds[0].streamSettings.tlsSettings.minVersion = '1.0'; Check-Policy $c $false
    $c = New-TestConfig; $c.outbounds[0].streamSettings.security = 'none'; Check-Policy $c $false
    $c = New-TestConfig; $c.outbounds += @{ protocol = 'freedom' }; Check-Policy $c $false
    $c = New-TestConfig; $c.routing = @{}; Check-Policy $c $false
    $c = New-TestConfig; $c.outbounds[0].streamSettings.tlsSettings.fingerprint = 'unsafe'; Check-Policy $c $false
    $c = New-TestConfig; $c.inbounds[0].listen = '0.0.0.0'; Check-Policy $c $false
    $c = New-TestConfig
    $c.outbounds = @((Convert-Vless 'vless://00000000-0000-4000-8000-000000000001@example.invalid:443?security=reality&type=tcp&sni=example.invalid&pbk=AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA&sid=ab'))
    Check-Policy $c $true
    $c.outbounds[0].streamSettings.realitySettings.password = 'invalid'; Check-Policy $c $false
    Write-Host 'Synthetic crypto policy tests passed.'
} finally { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }
