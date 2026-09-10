@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

for %%I in ("%~dp0.") do set "ROOT=%%~fI"
set "LOG_DIR=%ROOT%\logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%I"
if not defined STAMP set "STAMP=unknown"

set "LATEST=%LOG_DIR%\prototype_latest.log"
set "ARCHIVE=%LOG_DIR%\prototype_%STAMP%.log"
set "ENGINE_LOG=%LOG_DIR%\godot_engine_latest.log"
set "CONSOLE_LOG=%TEMP%\bus_master_console_%STAMP%.log"

> "%LATEST%" echo ============================================================
>>"%LATEST%" echo Bus Master Prototype Launcher
>>"%LATEST%" echo Started: %DATE% %TIME%
>>"%LATEST%" echo Project: %ROOT%
>>"%LATEST%" echo ============================================================

if exist "%ENGINE_LOG%" del /q "%ENGINE_LOG%" >nul 2>nul
if exist "%CONSOLE_LOG%" del /q "%CONSOLE_LOG%" >nul 2>nul

set "GODOT_EXE="

rem 1) Explicit environment variable wins.
if defined GODOT_PATH (
    if exist "%GODOT_PATH%" set "GODOT_EXE=%GODOT_PATH%"
)

rem 2) Prefer console builds near the project or Downloads so stdout/stderr is available.
if not defined GODOT_EXE (
    for %%F in ("%ROOT%\Godot*_console.exe" "%ROOT%\tools\Godot*_console.exe" "%USERPROFILE%\Downloads\Godot*_console.exe") do (
        if exist "%%~fF" if not defined GODOT_EXE set "GODOT_EXE=%%~fF"
    )
)

rem 3) Check PATH.
if not defined GODOT_EXE (
    for %%C in (godot4_console.exe godot_console.exe godot4.exe godot.exe godot4 godot) do (
        if not defined GODOT_EXE (
            for /f "delims=" %%P in ('where %%C 2^>nul') do (
                if not defined GODOT_EXE set "GODOT_EXE=%%P"
            )
        )
    )
)

rem 4) Common install/download locations.
if not defined GODOT_EXE (
    for %%F in (
        "%ROOT%\Godot*.exe"
        "%ROOT%\tools\Godot*.exe"
        "%USERPROFILE%\Downloads\Godot*.exe"
        "%ProgramFiles%\Godot\Godot*.exe"
        "%ProgramFiles(x86)%\Steam\steamapps\common\Godot Engine\*.exe"
    ) do (
        if exist "%%~fF" if not defined GODOT_EXE set "GODOT_EXE=%%~fF"
    )
)

if not defined GODOT_EXE goto :godot_not_found

rem If GODOT_PATH or PATH points at a GUI build, prefer a console sibling when available.
for %%G in ("%GODOT_EXE%") do set "GODOT_DIR=%%~dpG"
if exist "%GODOT_DIR%godot_console.exe" set "GODOT_EXE=%GODOT_DIR%godot_console.exe"
if exist "%GODOT_DIR%godot4_console.exe" set "GODOT_EXE=%GODOT_DIR%godot4_console.exe"
for %%F in ("%GODOT_DIR%Godot*_console.exe") do (
    if exist "%%~fF" set "GODOT_EXE=%%~fF"
)

>>"%LATEST%" echo Godot executable: %GODOT_EXE%
>>"%LATEST%" echo.
>>"%LATEST%" echo --- Godot version ---
"%GODOT_EXE%" --version >>"%LATEST%" 2>&1
>>"%LATEST%" echo.
>>"%LATEST%" echo NOTE: Prototype forces the Dummy audio driver because it currently has no audio.
>>"%LATEST%" echo --- Prototype output ---

echo [Bus Master] Launching prototype...
echo [Bus Master] Latest log: "%LATEST%"
echo [Bus Master] Audio driver: Dummy
echo.

rem Dummy audio avoids unrelated WASAPI/device failures during this gameplay-only prototype.
rem --log-file captures engine/script output even when a GUI Godot executable is selected.
start "" /wait "%GODOT_EXE%" --path "%ROOT%" --audio-driver Dummy --verbose --log-file "%ENGINE_LOG%" >"%CONSOLE_LOG%" 2>&1
set "EXIT_CODE=%ERRORLEVEL%"

if exist "%CONSOLE_LOG%" (
    type "%CONSOLE_LOG%" >>"%LATEST%"
)

if exist "%ENGINE_LOG%" (
    >>"%LATEST%" echo.
    >>"%LATEST%" echo --- Godot engine log ---
    type "%ENGINE_LOG%" >>"%LATEST%"
)

>>"%LATEST%" echo.
>>"%LATEST%" echo --- Launcher result ---
>>"%LATEST%" echo Exit code: %EXIT_CODE%
>>"%LATEST%" echo Finished: %DATE% %TIME%

copy /y "%LATEST%" "%ARCHIVE%" >nul
if exist "%CONSOLE_LOG%" del /q "%CONSOLE_LOG%" >nul 2>nul

echo.
echo [Bus Master] Prototype closed. Exit code: %EXIT_CODE%
echo [Bus Master] Latest log: "%LATEST%"
echo [Bus Master] Archived log: "%ARCHIVE%"
echo.
echo If something broke, run copy_latest_log.bat and paste the result into ChatGPT.
pause
exit /b %EXIT_CODE%

:godot_not_found
>>"%LATEST%" echo ERROR: Godot executable was not found.
>>"%LATEST%" echo.
>>"%LATEST%" echo Fix one of these ways:
>>"%LATEST%" echo 1. Put Godot or Godot_console.exe in this project folder.
>>"%LATEST%" echo 2. Add Godot to PATH.
>>"%LATEST%" echo 3. Set GODOT_PATH to the full path of your Godot executable.
copy /y "%LATEST%" "%ARCHIVE%" >nul

echo [Bus Master] Godot executable was not found.
echo See "%LATEST%"
echo.
echo Example:
echo   setx GODOT_PATH "C:\Path\To\Godot_v4.x-stable_win64_console.exe"
echo.
pause
exit /b 2
