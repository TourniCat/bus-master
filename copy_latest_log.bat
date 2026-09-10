@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "LOG_FILE=%~dp0logs\prototype_latest.log"
set "ENGINE_LOG=%~dp0logs\godot_engine_latest.log"
set "TEMP_COPY=%TEMP%\grow_combined_log.txt"

if not exist "%LOG_FILE%" (
    echo [Grow] No prototype log found yet.
    echo Run run_prototype.bat first.
    pause
    exit /b 1
)

>"%TEMP_COPY%" type "%LOG_FILE%"
if exist "%ENGINE_LOG%" (
    >>"%TEMP_COPY%" echo.
    >>"%TEMP_COPY%" echo --- Live Godot engine log ---
    >>"%TEMP_COPY%" type "%ENGINE_LOG%"
)

type "%TEMP_COPY%" | clip
if errorlevel 1 (
    echo [Grow] Could not copy the log to the clipboard.
    echo Open this file manually:
    echo   "%LOG_FILE%"
    pause
    exit /b 1
)

del /q "%TEMP_COPY%" >nul 2>nul
echo [Grow] Latest log copied to clipboard.
echo Paste it directly into ChatGPT with Ctrl+V.
pause
