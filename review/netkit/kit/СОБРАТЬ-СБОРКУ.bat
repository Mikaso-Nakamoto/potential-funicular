@echo off
chcp 65001 >nul
title LibreWolf-USB - собрать полный архив
echo.
echo   Собирает ОДИН zip: скрипты + браузер + xray + vpn-конфиг.
echo   Профиль браузера, логи и папка _download в архив не попадают.
echo   Займёт пару минут, рядом появится LibreWolf-USB-full-ДАТА.zip
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\make-bundle.ps1" %*
echo.
echo   Нажми любую клавишу, чтобы закрыть окно...
pause >nul
