<#
.SYNOPSIS
  Leak check for a portable privacy kit (Xray/VLESS + LibreWolf) on Windows.
  Read-only by default; the kill-switch test is opt-in and stops the tunnel process.

.DESCRIPTION
  Collects the facts you need before trusting a VPN/tunnel: real IPv4, real IPv6,
  DNS resolvers, proxy settings, listeners, tunnel/browser processes, firewall
  profiles. Then reports which of them look like leaks and why.

  Run it on a machine you own, or on one whose owner has allowed it.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Invoke-LeakCheck.ps1

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Invoke-LeakCheck.ps1 -KillTest -TunnelProcess xray
#>

[CmdletBinding()]
param(
    [string]$TunnelProcess = 'xray',
    [string]$BrowserProcess = 'librewolf',
    [string]$ReportPath = (Join-Path $PSScriptRoot 'leak-report.md'),
    [switch]$KillTest
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$rows = New-Object System.Collections.Generic.List[object]
$notes = New-Object System.Collections.Generic.List[string]

function Add-Row {
    param([string]$Check, [string]$Value, [string]$Verdict, [string]$Why)
    $rows.Add([pscustomobject]@{ Check = $Check; Value = $Value; Verdict = $Verdict; Why = $Why })
}

function Get-PublicIP {
    param([string]$IpVersion = '4', [int]$TimeoutSec = 6)
    $url = if ($IpVersion -eq '6') { 'https://api64.ipify.org' } else { 'https://api.ipify.org' }
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        $flag = if ($IpVersion -eq '6') { '-6' } else { '-4' }
        $out = & curl.exe $flag -s --max-time $TimeoutSec $url 2>$null
        if ($LASTEXITCODE -eq 0 -and $out) { return ($out | Out-String).Trim() }
        return $null
    }
    try {
        $wc = New-Object Net.WebClient
        $wc.Proxy = [Net.WebRequest]::DefaultWebProxy
        return $wc.DownloadString($url).Trim()
    } catch { return $null }
}

# --- 1. Identity of the machine and the session -----------------------------
Add-Row 'Host / user' "$env:COMPUTERNAME / $env:USERNAME" 'info' 'Where this run happened.'
Add-Row 'Is admin' "$([bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)))" 'info' 'Kill-switch via Windows Firewall needs admin; without it the kit cannot filter packets.'

# --- 2. Public addresses -----------------------------------------------------
$ip4 = Get-PublicIP -IpVersion '4'
$ip6 = Get-PublicIP -IpVersion '6'
Add-Row 'Public IPv4' ($(if ($ip4) { $ip4 } else { 'not reachable' })) ($(if ($ip4) { 'info' } else { 'warn' })) 'This is what sites see. Compare with the tunnel server IP, not with your ISP IP.'
Add-Row 'Public IPv6' ($(if ($ip6) { $ip6 } else { 'not reachable / no IPv6' })) ($(if ($ip6) { 'warn' } else { 'ok' })) 'If IPv6 works while the tunnel is IPv4-only, IPv6 traffic leaves the tunnel.'

$global6 = @()
try {
    $global6 = Get-NetIPAddress -AddressFamily IPv6 -ErrorAction Stop |
        Where-Object { $_.PrefixOrigin -ne 'WellKnown' -and $_.IPAddress -notlike 'fe80*' -and $_.IPAddress -ne '::1' } |
        Select-Object -ExpandProperty IPAddress
} catch {}
Add-Row 'Global IPv6 on adapters' ($(if ($global6) { ($global6 -join ', ') } else { 'none' })) ($(if ($global6 -and $ip6) { 'warn' } else { 'ok' })) 'IPv6 with real connectivity is the most common leak in IPv4-only tunnels.'

# --- 3. DNS -----------------------------------------------------------------
$dnsServers = @()
try {
    $dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object { $_.ServerAddresses } | ForEach-Object { $_.ServerAddresses }
} catch {}
Add-Row 'DNS servers (IPv4)' ($(if ($dnsServers) { ($dnsServers -join ', ') } else { 'none reported' })) 'info' 'If these are your router/ISP, DNS resolution happens outside the tunnel unless the browser uses DoH or the tunnel sets its own.'

$resolved = $null
try { $resolved = (Resolve-DnsName example.com -Type A -ErrorAction Stop | Where-Object { $_.IPAddress } | Select-Object -First 1).IPAddress } catch {}
Add-Row 'Resolves example.com' ($(if ($resolved) { $resolved } else { 'failed' })) ($(if ($resolved) { 'info' } else { 'warn' })) 'Resolution working is not proof of privacy; check which server answered.'

# --- 4. Proxy configuration -------------------------------------------------
$winhttp = ''
try { $winhttp = (& netsh winhttp show proxy 2>$null | Out-String).Trim() } catch {}
Add-Row 'WinHTTP proxy' ($(if ($winhttp) { ($winhttp -replace '\s+', ' ') } else { 'unknown' })) 'info' 'A system-wide proxy can silently route traffic around the expected path.'

$ieProxy = $null
try { $ieProxy = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop } catch {}
if ($ieProxy) {
    $enabled = [bool]$ieProxy.ProxyEnable
    Add-Row 'User proxy (WinINET)' ($(if ($enabled) { "$($ieProxy.ProxyServer)" } else { 'disabled' })) 'info' 'LibreWolf can bypass this entirely with its own proxy settings.'
}

# --- 5. Processes -----------------------------------------------------------
$tunnel = Get-Process -Name $TunnelProcess -ErrorAction SilentlyContinue
$browser = Get-Process -Name $BrowserProcess -ErrorAction SilentlyContinue
Add-Row "Process '$TunnelProcess'" ($(if ($tunnel) { (($tunnel | ForEach-Object { "PID $($_.Id) started $($_.StartTime)" }) -join '; ') } else { 'not running' })) ($(if ($tunnel) { 'ok' } else { 'warn' })) 'No tunnel process means no tunnel.'
Add-Row "Process '$BrowserProcess'" ($(if ($browser) { (($browser | ForEach-Object { "PID $($_.Id) started $($_.StartTime)" }) -join '; ') } else { 'not running' })) 'info' 'Check that the browser started after the tunnel, not before.'

# --- 6. Listeners -----------------------------------------------------------
$listen = @()
try {
    $listen = Get-NetTCPConnection -State Listen -ErrorAction Stop |
        Sort-Object LocalPort | Select-Object LocalAddress, LocalPort, OwningProcess
} catch {}
$proxyPorts = $listen | Where-Object { $_.LocalPort -in 1080, 1081, 10808, 10809, 8080, 8888 }
Add-Row 'Local proxy listeners' ($(if ($proxyPorts) { (($proxyPorts | ForEach-Object { "$($_.LocalAddress):$($_.LocalPort)" }) -join ', ') } else { 'none on common ports' })) 'info' 'A listener on 0.0.0.0 exposes your tunnel to the local network; 127.0.0.1 is the safe default.'

$onAll = $proxyPorts | Where-Object { $_.LocalAddress -in '0.0.0.0', '::' }
Add-Row 'Proxy bound to all interfaces' ($(if ($onAll) { 'YES' } else { 'no' })) ($(if ($onAll) { 'warn' } else { 'ok' })) 'Anyone on the same Wi-Fi could use your tunnel as an open proxy.'

# --- 7. Firewall profile state ---------------------------------------------
try {
    $fw = Get-NetFirewallProfile -ErrorAction Stop | Select-Object Name, Enabled
    Add-Row 'Firewall profiles' (($fw | ForEach-Object { "$($_.Name)=$($_.Enabled)" }) -join ', ') 'info' 'Domain/Private/Public must be enabled for any firewall-based kill-switch to mean anything.'
} catch {
    Add-Row 'Firewall profiles' 'cannot read without admin' 'info' 'Expected on a locked-down machine.'
}

# --- 8. Kill-switch test (opt-in) ------------------------------------------
if ($KillTest) {
    if (-not $tunnel) {
        Add-Row 'Kill-switch test' 'skipped: tunnel process not running' 'warn' 'Start the kit first, then run with -KillTest.'
    } else {
        $notes.Add('Kill-switch test: stopping the tunnel process now. The kit is NOT restarted automatically.')
        Stop-Process -Id ($tunnel | Select-Object -First 1).Id -Force
        Start-Sleep -Seconds 3
        $ipAfter = Get-PublicIP -IpVersion '4'
        $leaks = $ipAfter -and $ip4 -and ($ipAfter -ne $ip4)
        Add-Row 'IP after tunnel stopped' ($(if ($ipAfter) { $ipAfter } else { 'no connectivity' })) ($(if ($ipAfter) { 'FAIL' } else { 'pass' })) 'If traffic still flows after the tunnel dies, there is no kill-switch. "No connectivity" is the only safe outcome.'
        if ($leaks) { $notes.Add("Leak confirmed: browser traffic continued with public IP $ipAfter after the tunnel stopped.") }
    }
}

# --- 9. Report --------------------------------------------------------------
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$verdicts = $rows | Group-Object Verdict | ForEach-Object { "$($_.Name)=$($_.Count)" }
$warnCount = ($rows | Where-Object { $_.Verdict -in 'warn', 'FAIL' }).Count
$headline = if ($warnCount -gt 0) { "ATTENTION: $warnCount check(s) need a decision" } else { 'No automatic red flags in the checks that ran' }

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Leak check - $env:COMPUTERNAME - $stamp")
$md.Add('')
$md.Add("**$headline** ($($verdicts -join ', '))")
$md.Add('')
$md.Add('| Check | Value | Verdict | Why it matters |')
$md.Add('| --- | --- | --- | --- |')
foreach ($r in $rows) { $md.Add("| $($r.Check) | $($r.Value -replace '\|', '/') | $($r.Verdict) | $($r.Why -replace '\|', '/') |") }
if ($notes.Count -gt 0) {
    $md.Add('')
    $md.Add('## Notes')
    foreach ($n in $notes) { $md.Add("- $n") }
}
$md.Add('')
$md.Add('_Reads only: no firewall rules changed, no traffic generated beyond a few HTTPS calls to api.ipify.org._')

$text = $md -join [Environment]::NewLine
$text | Out-File -FilePath $ReportPath -Encoding UTF8
Write-Host $text
Write-Host ''
Write-Host "Report saved: $ReportPath" -ForegroundColor Cyan
