#requires -Version 5.1
# Offline tests with synthetic credentials only. Does not start Xray or a browser.
. (Join-Path $PSScriptRoot 'Workspace.Common.ps1')
$base = 'vless://00000000-0000-4000-8000-000000000001@example.invalid:443?'
$tcp = Convert-Vless ($base + 'type=tcp&security=tls&sni=example.invalid')
if ($tcp.protocol -ne 'vless' -or $tcp.streamSettings.tlsSettings.allowInsecure -ne $false) { throw 'TLS test failed.' }
$reality = Convert-Vless ($base + 'type=raw&security=reality&sni=example.invalid&pbk=AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA&sid=ab&flow=xtls-rprx-vision')
if ($reality.streamSettings.realitySettings.password -ne 'AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA' -or $reality.streamSettings.network -ne 'tcp') { throw 'REALITY mapping failed.' }
$ws = Convert-Vless ($base + 'type=ws&security=tls&path=%2Fsocket&host=example.invalid&alpn=http%2F1.1')
if ($ws.streamSettings.wsSettings.path -ne '/socket' -or $ws.streamSettings.wsSettings.host -ne 'example.invalid' -or $ws.streamSettings.tlsSettings.alpn[0] -ne 'http/1.1') { throw 'WS mapping failed.' }
$header = Convert-Vless ($base + 'type=tcp&security=tls&headerType=none')
if ($header.streamSettings.network -ne 'tcp') { throw 'headerType=none mapping failed.' }
foreach ($query in @(
    'security=none',
    'security=tls&fp=unsafe',
    'security=reality&sni=example.invalid&pbk=invalid',
    'security=reality&sni=example.invalid&pbk=AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA&sid=abc',
    'security=tls&type=grpc',
    'security=tls&allowInsecure=1',
    'security=tls&type=ws&flow=xtls-rprx-vision',
    'security=tls&unknown=value',
    'security=tls&security=reality',
    'security=reality&type=tcp',
    'security=tls&pbk=unexpected',
    'security=tls&encryption=unsupported',
    'security=tls&type=tcp&path=%2Fignored',
    'security=tls&type=ws&headerType=none',
    'security=tls&type=tcp&headerType=http'
)) {
    $rejected = $false
    try { $null = Convert-Vless ($base + $query) } catch { $rejected = $true }
    if (-not $rejected) { throw "Expected rejection: $query" }
}
Write-Host 'Parser tests passed (synthetic inputs only).'
