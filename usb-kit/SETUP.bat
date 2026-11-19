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

"%PSEXE%" -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%ROOT%\tools\setup.ps1"
set "RC=%ERRORLEVEL%"

echo.
pause
exit /b %RC%

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
