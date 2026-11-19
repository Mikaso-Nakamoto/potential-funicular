@echo off
rem Точка входа Windows: Pi целиком с этого носителя, путь может быть любым.
setlocal enableextensions

set "ROOT=%~dp0.."
pushd "%ROOT%" >nul && set "ROOT=%CD%" && popd >nul

set "PI_STICK_ROOT=%ROOT%"
set "PATH=%ROOT%\node;%ROOT%\npm-global;%ROOT%\venv\Scripts;%PATH%"
set "NPM_CONFIG_PREFIX=%ROOT%\npm-global"
set "NPM_CONFIG_CACHE=%ROOT%\tmp\npm-cache"
set "NODE_REPL_HISTORY=%ROOT%\tmp\node_repl_history"
set "PI_CODING_AGENT_DIR=%ROOT%\config"
set "PI_CODING_AGENT_SESSION_DIR=%ROOT%\sessions"
set "TMPDIR=%ROOT%\tmp"
set "TEMP=%ROOT%\tmp"
set "TMP=%ROOT%\tmp"
set "XDG_CACHE_HOME=%ROOT%\tmp\xdg-cache"
set "XDG_CONFIG_HOME=%ROOT%\tmp\xdg-config"
set "XDG_STATE_HOME=%ROOT%\tmp\xdg-state"

if not exist "%ROOT%\tmp" mkdir "%ROOT%\tmp"
if not exist "%ROOT%\sessions" mkdir "%ROOT%\sessions"
if not exist "%ROOT%\config\skills" mkdir "%ROOT%\config\skills"

if not exist "%ROOT%\node\node.exe" (
  echo Стек ещё не собран. Выполните: powershell -ExecutionPolicy Bypass -File "%ROOT%\tools\bootstrap.ps1" >&2
  exit /b 1
)

"%ROOT%\node\node.exe" "%ROOT%\npm-global\node_modules\@earendil-works\pi-coding-agent\bin\pi.js" %*
set "RC=%ERRORLEVEL%"

rem Ручная зачистка кэшей (для автоочистки см. tools\wipe-temp.bat)
endlocal & exit /b %RC%
