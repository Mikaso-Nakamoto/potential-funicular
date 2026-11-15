@echo off
chcp 65001 >nul
title LibreWolf-USB — самопроверка (без сети)
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\self-check.ps1" %*
echo.
echo   Нажми любую клавишу, чтобы закрыть окно...
pause >nul
