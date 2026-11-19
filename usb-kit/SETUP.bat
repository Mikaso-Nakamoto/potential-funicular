@echo off
rem ============================================================
rem  One-click setup launcher. All UI text lives in tools\setup.ps1
rem  (this file is pure ASCII on purpose: no codepage problems).
rem ============================================================
setlocal enableextensions
chcp 65001 >nul
title USB-KIT setup

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

if not exist "%ROOT%\tools\setup.ps1"    goto :nofiles
if not exist "%ROOT%\tools\bootstrap.ps1" goto :nofiles

set "PSEXE=powershell"
where powershell >nul 2>nul || set "PSEXE=pwsh"
where %PSEXE% >nul 2>nul || goto :nops

rem --- self-heal: ensure UTF-8 BOM in the .ps1 files ---
rem (zip tools, editors and extractors like to strip it, and PowerShell 5.1
rem  then reads Russian text in the ANSI codepage and refuses to parse)
for %%F in (setup.ps1 bootstrap.ps1 sync-skills.ps1) do call :fixbom "%ROOT%\tools\%%F"

"%PSEXE%" -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%ROOT%\tools\setup.ps1"
set "RC=%ERRORLEVEL%"

echo.
pause
exit /b %RC%

:fixbom
rem %1 = full path to a .ps1 file
"%PSEXE%" -NoProfile -Command "$f='%~1'; $b=[IO.File]::ReadAllBytes($f); if ($b[0] -ne 239) { $n=[byte[]]::new($b.Length+3); $n[0]=239; $n[1]=187; $n[2]=191; [Array]::Copy($b,0,$n,3,$b.Length); [IO.File]::WriteAllBytes($f,$n) }"
exit /b 0

:nofiles
echo.
echo  [ERROR] tools\setup.ps1 or tools\bootstrap.ps1 not found next to this file.
echo  The archive seems to be extracted with an extra folder level.
echo  Expected:  F:\usb-kit\SETUP.bat
echo  Not:       F:\usb-kit\usb-kit\SETUP.bat
echo  Move the usb-kit folder to the root of the stick and run again.
echo.
pause
exit /b 1

:nops
echo.
echo  [ERROR] PowerShell not found (powershell.exe / pwsh.exe).
echo  Windows 10/11 includes it by default.
echo.
pause
exit /b 1
