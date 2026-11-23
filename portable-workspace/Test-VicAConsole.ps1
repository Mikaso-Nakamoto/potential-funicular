#requires -Version 5.1
# Offline checks: parse UI scripts and compile the renderer WITHOUT playing it or starting a session.
$ErrorActionPreference = 'Stop'
$directory = $PSScriptRoot
if (-not $directory) { $directory = Split-Path -Parent $MyInvocation.MyCommand.Path }
$introAst = $null
foreach ($name in @('Workspace-Console.ps1','VicA.Intro.ps1')) {
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $directory $name), [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw ('PowerShell syntax errors in ' + $name) }
    if ($name -eq 'VicA.Intro.ps1') { $introAst = $ast }
}
$blocks = @($introAst.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $node.Value.Contains('namespace VicAAscii')
}, $true))
if ($blocks.Count -ne 1) { throw 'Expected one embedded renderer.' }
if (-not ('VicAAscii.Intro' -as [type])) { Add-Type -TypeDefinition $blocks[0].Value -ErrorAction Stop }
if (-not ('VicAAscii.Intro' -as [type])) { throw 'Renderer type was not compiled.' }
Write-Host 'VIC-A: PowerShell parsed and renderer compiled. No animation, session or network request was started.' -ForegroundColor Green
Write-Host 'This test does not verify Win32 rendering, process control, remote connectivity or privacy.'
