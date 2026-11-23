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
# Pure managed frame rendering exercises geometry without calling kernel32 or opening a console.
foreach ($size in @(@(40,16), @(96,30), @(120,38))) {
    foreach ($time in @(0.0, 3.0, 6.4, 10.8, 16.0, 22.0, 27.0, 29.8)) {
        $frame = [VicAAscii.Intro]::EyeSnapshot($size[0], $size[1], $time)
        if ($frame.Length -ne ($size[0] * $size[1])) { throw 'Incorrect eye frame dimensions.' }
        foreach ($cell in $frame) {
            if (($cell -band 65535) -eq 0 -or ($cell -shr 16) -gt 15) { throw 'Invalid glyph or console color.' }
        }
    }
}
$open = [VicAAscii.Intro]::EyeSnapshot(96, 30, 4.0)
$closed = [VicAAscii.Intro]::EyeSnapshot(96, 30, 6.4)
if (@($open | Where-Object { ($_ -shr 16) -eq 15 }).Count -eq 0) { throw 'Open eye is missing white sclera.' }
if (@($closed | Where-Object { ($_ -shr 16) -eq 15 }).Count -ne 0) { throw 'Closed eyelid did not hide the sclera.' }
Write-Host 'VIC-A: PowerShell parsed, renderer compiled and managed eye frames checked. No animation, session or network request was started.' -ForegroundColor Green
Write-Host 'This test does not verify Win32 rendering, process control, remote connectivity or privacy.'
