@echo off
chcp 65001 >nul
title TempleOS - LibreWolf-USB
setlocal
if not exist "%~dp0app\menu.ps1" (
  echo   [X] Не найден app\menu.ps1 - архив распакован не целиком.
  echo       Распакуй архив в папку на флешке и запусти снова.
  echo.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\menu.ps1" %*
set "EC=%ERRORLEVEL%"
echo.
exit /b %EC%
