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
>>"%LATEST%" echo Bus Master Prototype Launcher v0.2
>>"%LATEST%" echo Started: %DATE% %TIME%
>>"%LATEST%" echo Project: %ROOT%
>>"%LATEST%" echo ============================================================

if exist "%ENGINE_LOG%" del /q "%ENGINE_LOG%" >nul 2>nul
if exist "%CONSOLE_LOG%" del /q "%CONSOLE_LOG%" >nul 2>nul

set "GODOT_EXE="

rem 1) An explicitly configured GODOT_PATH is authoritative. Do not replace it
rem    with a nearby *_console.exe: official console wrappers require their
rem    matching GUI executable and can fail if files were renamed/moved.
if defined GODOT_PATH (
    if exist "%GODOT_PATH%" set "GODOT_EXE=%GODOT_PATH%"
)

rem 2) Prefer normal GUI executables. --log-file still captures Godot errors.
if not defined GODOT_EXE (
    for %%C in (godot4.exe godot.exe godot4 godot) do (
        if not defined GODOT_EXE (
            for /f "delims=" %%P in ('where %%C 2^>nul') do (
                if not defined GODOT_EXE set "GODOT_EXE=%%P"
            )
        )
    )
)

rem 3) Search common folders for a non-console Godot executable.
if not defined GODOT_EXE call :find_gui "%ROOT%"
if not defined GODOT_EXE call :find_gui "%ROOT%\tools"
if not defined GODOT_EXE call :find_gui "%USERPROFILE%\Downloads"
if not defined GODOT_EXE call :find_gui "%ProgramFiles%\Godot"
if not defined GODOT_EXE call :find_gui "%ProgramFiles(x86)%\Steam\steamapps\common\Godot Engine"

rem 4) Last resort: console executables from PATH. These normally work when the
rem    official matching GUI executable is installed beside them.
if not defined GODOT_EXE (
    for %%C in (godot4_console.exe godot_console.exe) do (
        if not defined GODOT_EXE (
            for /f "delims=" %%P in ('where %%C 2^>nul') do (
                if not defined GODOT_EXE set "GODOT_EXE=%%P"
            )
        )
    )
)

if not defined GODOT_EXE goto :godot_not_found

>>"%LATEST%" echo Godot executable: %GODOT_EXE%
>>"%LATEST%" echo.
>>"%LATEST%" echo --- Godot version ---
"%GODOT_EXE%" --version >>"%LATEST%" 2>&1
set "VERSION_EXIT=%ERRORLEVEL%"
if not "%VERSION_EXIT%"=="0" (
    >>"%LATEST%" echo ERROR: Selected Godot executable failed its --version check. Exit code: %VERSION_EXIT%
    goto :launch_failed
)

>>"%LATEST%" echo.
>>"%LATEST%" echo NOTE: Prototype forces the Dummy audio driver because it currently has no audio.
>>"%LATEST%" echo --- Prototype output ---

echo [Bus Master] Launching prototype...
echo [Bus Master] Godot: "%GODOT_EXE%"
echo [Bus Master] Latest log: "%LATEST%"
echo [Bus Master] Audio driver: Dummy
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
echo [Bus Master] Prototype closed. Exit code: %EXIT_CODE%
echo [Bus Master] Latest log: "%LATEST%"
echo [Bus Master] Archived log: "%ARCHIVE%"
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
copy /y "%LATEST%" "%ARCHIVE%" >nul
echo [Bus Master] Selected Godot executable could not start.
echo See "%LATEST%"
pause
exit /b %EXIT_CODE%

:godot_not_found
>>"%LATEST%" echo ERROR: Godot executable was not found.
>>"%LATEST%" echo.
>>"%LATEST%" echo Recommended fix:
>>"%LATEST%" echo Set GODOT_PATH to the actual GUI executable you launch Godot with.
copy /y "%LATEST%" "%ARCHIVE%" >nul

echo [Bus Master] Godot executable was not found.
echo See "%LATEST%"
echo.
echo Example:
echo   setx GODOT_PATH "C:\godot\godot.exe"
echo.
pause
exit /b 2
