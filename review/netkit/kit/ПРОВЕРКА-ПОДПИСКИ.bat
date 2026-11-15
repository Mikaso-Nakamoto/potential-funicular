@echo off
chcp 65001 >nul
title LibreWolf-USB — диагностика подписки
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\check-sub.ps1" %*
echo.
echo   Нажми любую клавишу, чтобы закрыть окно...
pause >nul
