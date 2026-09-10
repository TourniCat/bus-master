@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "LOG_FILE=%~dp0logs\prototype_latest.log"
set "ENGINE_LOG=%~dp0logs\godot_engine_latest.log"
set "COMBINED=%TEMP%\bus_master_combined_log.txt"

if not exist "%LOG_FILE%" (
    echo [Bus Master] No prototype log found yet.
    echo Run run_prototype.bat first.
    pause
    exit /b 1
)

>"%COMBINED%" type "%LOG_FILE%"

if exist "%ENGINE_LOG%" (
    >>"%COMBINED%" echo.
    >>"%COMBINED%" echo --- LIVE GODOT ENGINE LOG ---
    >>"%COMBINED%" type "%ENGINE_LOG%"
) else (
    >>"%COMBINED%" echo.
    >>"%COMBINED%" echo --- LIVE GODOT ENGINE LOG ---
    >>"%COMBINED%" echo Engine log does not exist yet.
)

type "%COMBINED%" | clip
if errorlevel 1 (
    echo [Bus Master] Could not copy the log to the clipboard.
    echo Open these files manually:
    echo   "%LOG_FILE%"
    echo   "%ENGINE_LOG%"
    if exist "%COMBINED%" del /q "%COMBINED%" >nul 2>nul
    pause
    exit /b 1
)

if exist "%COMBINED%" del /q "%COMBINED%" >nul 2>nul

echo [Bus Master] Launcher + live Godot log copied to clipboard.
echo This works even while the prototype window is still open.
echo Paste it directly into ChatGPT with Ctrl+V.
pause
