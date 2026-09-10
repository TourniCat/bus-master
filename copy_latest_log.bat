@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "LOG_FILE=%~dp0logs\prototype_latest.log"

if not exist "%LOG_FILE%" (
    echo [Bus Master] No prototype log found yet.
    echo Run run_prototype.bat first.
    pause
    exit /b 1
)

type "%LOG_FILE%" | clip
if errorlevel 1 (
    echo [Bus Master] Could not copy the log to the clipboard.
    echo Open this file manually:
    echo   "%LOG_FILE%"
    pause
    exit /b 1
)

echo [Bus Master] Latest log copied to clipboard.
echo Paste it directly into ChatGPT with Ctrl+V.
pause
