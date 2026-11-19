@echo off
rem Windows launcher: runs Pi entirely from this stick.
rem Path is computed at runtime, so any drive letter / mount path works.
rem Kept pure ASCII on purpose (no codepage surprises in cmd).
setlocal enableextensions
chcp 65001 >nul

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

set "PI_CMD=%ROOT%\npm-global\pi.cmd"
set "PI_CLI=%ROOT%\npm-global\node_modules\@earendil-works\pi-coding-agent\dist\bundle\cli.js"

if not exist "%ROOT%\node\node.exe" goto :nobuild
if exist "%PI_CMD%" goto :viaCmd
if exist "%PI_CLI%" goto :viaNode
goto :nobuild

:viaCmd
call "%PI_CMD%" %*
goto :done

:viaNode
"%ROOT%\node\node.exe" "%PI_CLI%" %*
goto :done

:done
set "RC=%ERRORLEVEL%"
rem caches live in tmp\ ; to wipe them run tools\wipe-temp.bat
endlocal & exit /b %RC%

:nobuild
echo Stack is not built yet. Run SETUP.bat in the usb-kit folder first. >&2
endlocal & exit /b 1
