#requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Workspace.Common.ps1')
. (Join-Path $PSScriptRoot 'VaultRefresh.Diagnostics.ps1')
$sentinel = 'PRIVATE-SENTINEL-DO-NOT-PRINT'
$link = 'vless://12345678-1234-4234-8234-123456789abc@example.invalid:443?security=tls&type=tcp&sni=example.invalid&fp=chrome'
function Check([string]$Name,[string]$Body,[string]$Expected) {
    $output = @(Get-RefreshResponseDiagnostics $Body) -join "`n"
    foreach ($secret in @($sentinel,'example.invalid','12345678-')) {
        if ($output.Contains($secret)) { throw 'Diagnostic leaked synthetic private data.' }
    }
    if (-not $output.Contains($Expected)) { throw ('Diagnostic category mismatch: ' + $Name) }
    Write-Host ('PASS: read-only diagnostic ' + $Name)
}
Check 'HTML' ('<html>' + $sentinel + '</html>') 'FORMAT: html'
Check 'JSON' ('{"private":"' + $sentinel + '"}') 'FORMAT: json-like-not-uri-list'
Check 'bad Base64' ('!!!' + $sentinel) 'FORMAT: neither-uri-list-nor-valid-base64-utf8'
Check 'mixed list' ($link + "`nss://" + $sentinel) 'supported=1; skipped=1'
Check 'unsupported transport' ($link.Replace('type=tcp','type=xhttp') + '#' + $sentinel) 'REJECT: unsupported-transport; count=1'
Check 'unknown query' ($link + '&private=' + $sentinel) 'REJECT: unsupported-query; count=1'
Check 'unknown fingerprint' ($link.Replace('fp=chrome',('fp=' + $sentinel))) 'REJECT: unsupported-fingerprint; count=1'
Check 'Base64 URI list' ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($link))) 'supported=1; skipped=0'
Check 'Base64 HTML' ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('<html>' + $sentinel + '</html>'))) 'FORMAT: base64-html'
# Unclassified exceptions must never be echoed, including messages containing secrets.
function Convert-Vless { param([string]$Link); throw ('PRIVATE-SENTINEL-DO-NOT-PRINT ' + $Link) }
Check 'unclassified exception' $link 'REJECT: unclassified-parser-error; count=1'
Write-Host 'RESULT: PASS for synthetic diagnostic categories and sentinel non-disclosure only.'
