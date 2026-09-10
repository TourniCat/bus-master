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
set "CONSOLE_LOG=%TEMP%\flow_control_console_%STAMP%.log"

> "%LATEST%" echo ============================================================
>>"%LATEST%" echo Flow Control Prototype Launcher
>>"%LATEST%" echo Started: %DATE% %TIME%
>>"%LATEST%" echo Project: %ROOT%
>>"%LATEST%" echo ============================================================

if exist "%ENGINE_LOG%" del /q "%ENGINE_LOG%" >nul 2>nul
if exist "%CONSOLE_LOG%" del /q "%CONSOLE_LOG%" >nul 2>nul

set "GODOT_EXE="

rem Explicit GODOT_PATH wins.
if defined GODOT_PATH (
    if exist "%GODOT_PATH%" set "GODOT_EXE=%GODOT_PATH%"
)

rem Prefer normal GUI executables. --log-file still captures script/engine errors.
if not defined GODOT_EXE (
    for %%C in (godot4.exe godot.exe godot4 godot) do (
        if not defined GODOT_EXE (
            for /f "delims=" %%P in ('where %%C 2^>nul') do (
                if not defined GODOT_EXE set "GODOT_EXE=%%P"
            )
        )
    )
)

if not defined GODOT_EXE call :find_gui "%ROOT%"
if not defined GODOT_EXE call :find_gui "%ROOT%\tools"
if not defined GODOT_EXE call :find_gui "%USERPROFILE%\Downloads"
if not defined GODOT_EXE call :find_gui "%ProgramFiles%\Godot"
if not defined GODOT_EXE call :find_gui "%ProgramFiles(x86)%\Steam\steamapps\common\Godot Engine"

if not defined GODOT_EXE goto :godot_not_found

>>"%LATEST%" echo Godot executable: %GODOT_EXE%
>>"%LATEST%" echo.
>>"%LATEST%" echo --- Godot version ---
"%GODOT_EXE%" --version >>"%LATEST%" 2>&1
set "VERSION_EXIT=%ERRORLEVEL%"
if not "%VERSION_EXIT%"=="0" goto :launch_failed

>>"%LATEST%" echo.
>>"%LATEST%" echo --- Prototype output ---

echo [Flow Control] Launching prototype...
echo [Flow Control] Godot: "%GODOT_EXE%"
echo [Flow Control] Latest log: "%LATEST%"
echo.

start "" /wait "%GODOT_EXE%" --path "%ROOT%" --audio-driver Dummy --verbose --log-file "%ENGINE_LOG%" >"%CONSOLE_LOG%" 2>&1
set "EXIT_CODE=%ERRORLEVEL%"

if exist "%CONSOLE_LOG%" type "%CONSOLE_LOG%" >>"%LATEST%"
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
echo [Flow Control] Prototype closed. Exit code: %EXIT_CODE%
echo [Flow Control] Latest log: "%LATEST%"
echo [Flow Control] Archived log: "%ARCHIVE%"
echo.
echo If something broke, run copy_latest_log.bat and paste the result into ChatGPT.
pause
exit /b %EXIT_CODE%

:find_gui
set "SEARCH_DIR=%~1"
if not exist "%SEARCH_DIR%" exit /b 0
for /f "delims=" %%F in ('dir /b /a-d "%SEARCH_DIR%\Godot*.exe" 2^>nul ^| findstr /v /i "_console.exe"') do (
    if not defined GODOT_EXE set "GODOT_EXE=%SEARCH_DIR%\%%F"
)
exit /b 0

:launch_failed
set "EXIT_CODE=%VERSION_EXIT%"
>>"%LATEST%" echo ERROR: Selected Godot executable failed its --version check. Exit code: %VERSION_EXIT%
copy /y "%LATEST%" "%ARCHIVE%" >nul
echo [Flow Control] Selected Godot executable could not start.
echo See "%LATEST%"
pause
exit /b %EXIT_CODE%

:godot_not_found
>>"%LATEST%" echo ERROR: Godot executable was not found.
copy /y "%LATEST%" "%ARCHIVE%" >nul
echo [Flow Control] Godot executable was not found.
echo See "%LATEST%"
echo.
echo Example:
echo   setx GODOT_PATH "C:\godot\Godot_v4.7.2-stable_win64.exe"
echo.
pause
exit /b 2
