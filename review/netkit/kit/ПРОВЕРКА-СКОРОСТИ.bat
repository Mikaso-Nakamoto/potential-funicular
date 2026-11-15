@echo off
chcp 65001 >nul
title LibreWolf-USB - скорость серверов
echo.
echo   Проверяет каждый сервер из vpn\config.json: отклик и скорость.
echo   Занимает до пары минут. config.json и sub.txt не меняются.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\speed-test.ps1" %*
echo.
echo   Нажми любую клавишу, чтобы закрыть окно...
pause >nul
