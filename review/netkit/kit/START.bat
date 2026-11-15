@echo off
chcp 65001 >nul
title LibreWolf-USB
setlocal
echo.
echo   ============================================================
echo    LibreWolf-USB  -  трафик браузера через VPN, kill-switch
echo   ============================================================
echo.
if not exist "%~dp0app\start.ps1" (
  echo   [X] Не найден app\start.ps1 - архив распакован не целиком.
  echo       Распакуй LibreWolf-USB-fixed.zip в папку на флешке и запусти снова.
  echo.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\start.ps1" %*
set "EC=%ERRORLEVEL%"
echo.
if "%EC%"=="2" echo   [!] Сессия прервана KILL-SWITCH - браузер остановлен принудительно.
if not "%EC%"=="0" if not "%EC%"=="2" echo   [!] Ошибка запуска, код %EC% - смотри сообщение выше.
echo.
echo   Нажми любую клавишу, чтобы закрыть окно...
pause >nul
exit /b %EC%
