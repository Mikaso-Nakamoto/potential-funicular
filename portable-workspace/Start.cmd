@echo off
setlocal
title IRIS - Portable Workspace
powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0Workspace-Console.ps1"
if errorlevel 1 (
  echo.
  echo Console could not start. Review the error above. No execution policy was changed.
  pause
)
endlocal
