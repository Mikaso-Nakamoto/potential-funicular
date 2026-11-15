@echo off
chcp 65001 >nul
title LibreWolf-USB — чистка следов
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\clean-traces.ps1" %*
echo.
echo   Нажми любую клавишу, чтобы закрыть окно...
pause >nul
