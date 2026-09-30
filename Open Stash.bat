@echo off
setlocal
cd /d "%~dp0"
title Tube Stash
set "STASH_ROOT=%~dp0"
if "%STASH_ROOT:~-1%"=="\" set "STASH_ROOT=%STASH_ROOT:~0,-1%"
if not defined PORT set "PORT=47841"
set "URL=http://127.0.0.1:%PORT%"

set "VENDOR=%~dp0vendor\win-x64"
set "NODE=node"
if exist "%VENDOR%\node.exe" (
  set "PATH=%VENDOR%;%PATH%"
  set "NODE=%VENDOR%\node.exe"
  if exist "%VENDOR%\yt-dlp.exe" set "YTDLP=%VENDOR%\yt-dlp.exe"
) else (
  where node >nul 2>&1
  if errorlevel 1 (
    echo.
    echo Node.js 18 or newer is required.
    echo Install it from https://nodejs.org
    echo Or download the Windows zip from the Tube Stash GitHub release.
    echo.
    pause
    exit /b 1
  )
)

rem Already running? Just open it.
powershell -NoProfile -Command "try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 '%URL%/api/settings' | Out-Null; exit 0 } catch { exit 1 }" >nul 2>&1
if not errorlevel 1 (
  start "" "%URL%"
  exit /b 0
)

echo Tube Stash is running at %URL%
echo Keep this window open while you use it. Close it to stop Tube Stash.
echo.
start "" /b cmd /c "timeout /t 2 /nobreak >nul & start "" "%URL%""
"%NODE%" "%~dp0server\index.js"
if errorlevel 1 pause
