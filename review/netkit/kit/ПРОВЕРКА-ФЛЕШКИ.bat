@echo off
chcp 65001 >nul
title LibreWolf-USB - проверка скорости флешки
echo.
echo   Замер займёт до минуты. На флешку временно пишется до 64 МБ,
echo   потом всё удаляется. config.json и sub.txt не трогаются.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\usb-speed.ps1" %*
echo.
echo   Нажми любую клавишу, чтобы закрыть окно...
pause >nul
