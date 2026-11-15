@echo off
chcp 65001 >nul
title LibreWolf-USB — подготовка ДОМА
echo.
echo   ============================================================
echo    Подготовка флешки LibreWolf-USB - запускать ТОЛЬКО ДОМА!
echo    Скачает LibreWolf + Xray, предложит вставить vless:// ссылку.
echo   ============================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\prepare-home.ps1"
echo.
echo   Нажми любую клавишу, чтобы закрыть окно...
pause >nul
