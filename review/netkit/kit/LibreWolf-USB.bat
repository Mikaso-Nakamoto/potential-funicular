@echo off
chcp 65001 >nul
title TempleOS - LibreWolf-USB
setlocal

if not exist "%~dp0app\gui.ps1" goto console
if not exist "%~dp0app\menu.ps1" (
  echo   [X] Не найден app\menu.ps1 - архив распакован не целиком.
  echo       Распакуй архив в папку на флешке и запусти снова.
  echo.
  pause
  exit /b 1
)

rem графическое окно; если WPF недоступен, вернёт код 1 и откроется консольное меню
start "" /wait powershell.exe -WindowStyle Hidden -STA -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\gui.ps1"
if not errorlevel 1 exit /b 0

:console
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\menu.ps1" %*
set "EC=%ERRORLEVEL%"
echo.
exit /b %EC%
