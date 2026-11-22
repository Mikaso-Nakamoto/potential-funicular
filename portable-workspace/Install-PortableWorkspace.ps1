#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Root = 'Z:\Iran\Browser'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# This standalone installer runs in a fresh PowerShell process. Do not retain legacy protocol flags.
if ($null -ne [Net.ServicePointManager]::ServerCertificateValidationCallback) { throw 'Custom certificate validation callback is prohibited.' }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::CheckCertificateRevocationList = $true

if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitOperatingSystem) {
    throw 'Windows x64 is required.'
}
if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') {
    throw 'This installer targets x64 PCs, not ARM64.'
}
if ($Root -notmatch '^[A-Za-z]:\\') { throw 'Root must be an absolute local drive path.' }
$Root = [IO.Path]::GetFullPath($Root).TrimEnd('\')
$drive = [IO.Path]::GetPathRoot($Root)
if ($Root.Length -le 3) { throw 'Destination must not be a drive root.' }
if (-not (Test-Path -LiteralPath $drive)) { throw "Drive not found: $drive" }
if (Test-Path -LiteralPath $Root) { throw 'Destination already exists. Choose a NEW folder; nothing will be overwritten.' }
$parent = Split-Path -Parent $Root
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Destination parent must already exist.' }
# Reject junctions/symlinks in the parent chain so staging and destination stay on the displayed volume.
$ancestor = Get-Item -LiteralPath $parent -Force
while ($null -ne $ancestor) {
    if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse-point parents are not supported.' }
    $ancestor = $ancestor.Parent
}
$letter = $drive.Substring(0, 1)
$volume = Get-Volume -DriveLetter $letter -ErrorAction Stop
$partitions = @(Get-Partition -DriveLetter $letter -ErrorAction Stop)
if ($partitions.Count -ne 1) { throw 'Cannot identify a single local disk for this drive.' }
$disk = Get-Disk -Number $partitions[0].DiskNumber -ErrorAction Stop
$volume | Format-List DriveLetter, FileSystemLabel, DriveType, Size, SizeRemaining | Out-Host
$disk | Format-List Number, FriendlyName, SerialNumber, BusType | Out-Host
Write-Host "Destination: $Root"
Write-Host 'Check the model and serial number against your SSD. USB bus type alone does not identify it.'
if ((Read-Host "Type the complete destination path to confirm") -cne $Root) { throw 'Destination not confirmed.' }
# A sibling staging directory permits one same-volume directory rename at publication.
$stage = Join-Path $parent ('.install-' + [Guid]::NewGuid().ToString('N'))
$bundle = Join-Path $stage 'bundle'
$stageOwned = $false
$headers = @{ 'User-Agent' = 'PortableWorkspaceInstaller'; 'Accept' = 'application/vnd.github+json' }
function Download([string]$Url, [string]$Destination) {
    if ($Url -notmatch '^https://') { throw 'Only HTTPS downloads are allowed.' }
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Destination -Headers @{ 'User-Agent' = 'PortableWorkspaceInstaller' }
}
try {
    New-Item -ItemType Directory -Path $stage | Out-Null
    $stageOwned = $true
    New-Item -ItemType Directory -Path $bundle | Out-Null
    Write-Host 'Discovering the official LibreWolf portable x64 archive...'
    $page = Invoke-WebRequest -UseBasicParsing -Uri 'https://librewolf.net/installation/windows/'
    $pattern = 'https://dl\.librewolf\.net/librewolf/[^\s"<>]+/librewolf-[^\s"<>]+-windows-x86_64-portable\.zip'
    $urls = @([regex]::Matches($page.Content, $pattern) | ForEach-Object { $_.Value } | Select-Object -Unique)
    if ($urls.Count -ne 1) { throw 'Official LibreWolf page format changed. Refusing to guess a download URL.' }
    $lwUrl = $urls[0]
    $lwZip = Join-Path $stage 'librewolf.zip'
    Download $lwUrl $lwZip
    $lwExtract = Join-Path $bundle 'LibreWolf'
    Expand-Archive -LiteralPath $lwZip -DestinationPath $lwExtract
    $browsers = @(Get-ChildItem -LiteralPath $lwExtract -Recurse -File -Filter 'librewolf.exe')
    if ($browsers.Count -ne 1) { throw 'Expected exactly one librewolf.exe in the official archive.' }
    $signature = Get-AuthenticodeSignature -LiteralPath $browsers[0].FullName
    if ($signature.Status -ne 'Valid') {
        throw "LibreWolf Authenticode signature is not valid: $($signature.Status). No bypass is provided."
    }
    $signerName = $signature.SignerCertificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
    # Windows certificate SimpleName includes the OSSign brand, not just the legal entity.
    if ($signerName -cne 'OSSign (Scheibling Consulting AB)') {
        throw "Unexpected LibreWolf signer: $signerName. Verify publisher changes with the official project; do not bypass this check."
    }
    Write-Host "LibreWolf signer: $($signature.SignerCertificate.Subject)"

    Write-Host 'Discovering the latest stable XTLS/Xray-core release...'
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/XTLS/Xray-core/releases/latest' -Headers $headers
    $assets = @($release.assets | Where-Object { $_.name -eq 'Xray-windows-64.zip' })
    if ($assets.Count -ne 1) { throw 'Official Xray x64 asset missing or ambiguous.' }
    $asset = $assets[0]
    if ($asset.browser_download_url -notmatch '^https://github\.com/XTLS/Xray-core/releases/download/') {
        throw 'Unexpected Xray download origin.'
    }
    if (-not ($asset.PSObject.Properties.Name -contains 'digest') -or $asset.digest -notmatch '^sha256:([0-9a-fA-F]{64})$') {
        throw 'GitHub did not provide a SHA-256 digest. Refusing unverified installation.'
    }
    $expected = $Matches[1]
    $xrayZip = Join-Path $stage 'xray.zip'
    Download $asset.browser_download_url $xrayZip
    $actual = (Get-FileHash -LiteralPath $xrayZip -Algorithm SHA256).Hash
    if ($actual -ne $expected) { throw 'Xray SHA-256 mismatch.' }
    $xrayExtract = Join-Path $bundle 'Xray'
    Expand-Archive -LiteralPath $xrayZip -DestinationPath $xrayExtract
    if (-not (Test-Path -LiteralPath (Join-Path $xrayExtract 'xray.exe'))) { throw 'xray.exe missing.' }

    $manifest = [ordered]@{
        installedAtUtc = [DateTime]::UtcNow.ToString('o')
        architecture = 'windows-x64'
        libreWolf = @{
            source = $lwUrl
            sha256 = (Get-FileHash -LiteralPath $lwZip -Algorithm SHA256).Hash
            signer = $signature.SignerCertificate.Subject
            certificateThumbprint = $signature.SignerCertificate.Thumbprint
        }
        xray = @{ version = $release.tag_name; source = $asset.browser_download_url; sha256 = $actual }
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $bundle 'install-manifest.json') -Encoding UTF8
    # Directory.Move fails if the destination appeared meanwhile; it does not merge or overwrite.
    # This is a single rename, not a guarantee of durability under power loss or hardware failure.
    [IO.Directory]::Move($bundle, $Root)
    Write-Host "Installed to $Root. Nothing was launched. Proxy and profile are NOT configured."
}
finally {
    if ($stageOwned -and (Test-Path -LiteralPath $stage)) {
        try { Remove-Item -LiteralPath $stage -Recurse -Force }
        catch { Write-Warning "Could not remove staging directory ${stage}: $($_.Exception.Message)" }
    }
}
