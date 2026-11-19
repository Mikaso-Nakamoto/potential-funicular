#!/usr/bin/env python3
"""Собирает USB-KIT.bat — один самодостаточный файл установщика.

Внутри .bat лежит base64 ZIP всего дерева usb-kit (без рантайма node/venv/...).
При запуске батник (чистый ASCII, без кириллицы) просит путь, разворачивает ZIP
через PowerShell Expand-Archive и запускает SETUP.bat из развёрнутой папки.

Зачем: zip+архиватор давали две беды — потеря BOM и «SETUP.bat запущен без своих
папок». Здесь ни того, ни другого: файл один, разворачивает его сам батник.

Запуск:  python3 usb-kit/tools/make-single-bat.py [выходной_файл]
"""
from __future__ import annotations

import base64
import io
import os
import sys
import time
import zipfile

SKIP_DIRS = {"node", "npm-global", "venv", "tmp", "__pycache__", ".pytest_cache",
             ".mypy_cache", "build", "dist", ".eggs"}
SKIP_FILES = {"auth.json", "mcp.log", "mcp.log.1"}
LINE = 200  # батарея: у cmd ограничение на длину строки ~8191 символов

HEADER = r'''@echo off
rem ============================================================
rem  USB-KIT - one-file portable agent stack installer.
rem  Self-contained: the whole usb-kit tree is embedded below as
rem  base64 ZIP and is unpacked by this script itself.
rem  Pure ASCII on purpose: no codepage problems in cmd.
rem ============================================================
setlocal enableextensions
chcp 65001 >nul
title USB-KIT

set "SELF=%~f0"
set "TARGET=%~dp0USB-KIT"
if "%TARGET:~-1%"=="\" set "TARGET=%TARGET:~0,-1%"

where powershell >nul 2>nul || goto :nops

echo.
echo  USB-KIT: portable agent stack (Pi + skillbridge MCP)
echo  ---------------------------------------------
echo  This file contains the whole build inside it.
echo  It will be unpacked into:
echo      %TARGET%
echo.
set "ANS="
set /p "ANS=  Unpack there? [Y/n] (or type another path): "
if /i "%ANS%"=="n" goto :nops
if not "%ANS%"=="" if /i not "%ANS%"=="y" set "TARGET=%ANS%"

echo.
echo  Unpacking, please wait...
echo.

powershell -NoProfile -NoLogo -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $p=$env:SELF; $t=[IO.File]::ReadAllText($p); $a=$t.LastIndexOf('#@PAYLOAD@#'); $b=$t.LastIndexOf('#@END@#'); if ($a -lt 0 -or $b -le $a) { throw 'payload markers not found' }; $b64=($t.Substring($a+11, $b-$a-11) -replace '[^A-Za-z0-9+/=]',''); $bytes=[Convert]::FromBase64String($b64); $zip=Join-Path $env:TEMP ('usb-kit-' + [guid]::NewGuid().ToString('N') + '.zip'); [IO.File]::WriteAllBytes($zip,$bytes); $out=$env:TARGET; New-Item -ItemType Directory -Force -Path $out | Out-Null; Expand-Archive -LiteralPath $zip -DestinationPath $out -Force; Remove-Item -LiteralPath $zip -Force; Write-Host ('  unpacked ' + $bytes.Length + ' bytes -> ' + $out)"
if errorlevel 1 goto :unpackfail

if not exist "%TARGET%\SETUP.bat" goto :unpackfail
if not exist "%TARGET%\tools\setup.ps1" goto :unpackfail

echo.
echo  Running the installer from: %TARGET%
echo.
pushd "%TARGET%"
call "%TARGET%\SETUP.bat"
set "RC=%ERRORLEVEL%"
popd
endlocal & exit /b %RC%

:nops
echo.
echo  [ERROR] PowerShell not found, or you chose to stop.
echo  Windows 10/11 includes PowerShell 5.1 by default.
echo.
pause
endlocal & exit /b 1

:unpackfail
echo.
echo  [ERROR] Could not unpack the build.
echo  Copy this .bat to the target folder first (not inside a ZIP preview
echo  window !), then run it again and confirm the path it suggests.
echo.
pause
endlocal & exit /b 1

exit /b 0
#@PAYLOAD@#
'''


def collect(root: str) -> list[str]:
    files: list[str] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames
                             if d not in SKIP_DIRS and not d.endswith(".egg-info"))
        for name in sorted(filenames):
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, root).split(os.sep)
            if rel[0] == "sessions" and name != ".gitkeep":
                continue
            if name in SKIP_FILES or name.endswith((".pyc", ".pyo")):
                continue
            files.append(path)
    return files


def build(root: str, out: str) -> None:
    files = collect(root)
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for path in files:
            src = os.path.relpath(path, root).replace(os.sep, '/')
            info = zipfile.ZipInfo(src, date_time=time.localtime(os.path.getmtime(path))[:6])
            info.external_attr = (os.stat(path).st_mode & 0xFFFF) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(path, "rb") as fh:
                z.writestr(info, fh.read())
    payload = buf.getvalue()
    b64 = base64.b64encode(payload).decode("ascii")
    lines = [b64[i:i + LINE] for i in range(0, len(b64), LINE)]

    header = HEADER.replace("\n", "\r\n")
    body = "\r\n".join(lines) + "\r\n#@END@#\r\n"
    data = (header + body).encode("ascii")
    with open(out, "wb") as fh:
        fh.write(data)
    print(f"files: {len(files)}  zip: {len(payload)/1024:.1f} KiB  "
          f"bat: {len(data)/1024/1024:.2f} MiB  lines: {len(lines)}")


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(here)
    target = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(root), "USB-KIT.bat")
    build(root, target)
    print("written:", target)
