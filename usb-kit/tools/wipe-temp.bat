@echo off
rem Ручная зачистка всех кэшей стека (сессии и конфиг не трогаются).
setlocal
set "ROOT=%~dp0.."
pushd "%ROOT%" >nul && set "ROOT=%CD%" && popd >nul
if exist "%ROOT%\tmp" rmdir /s /q "%ROOT%\tmp"
echo tmp\ очищен.
endlocal
