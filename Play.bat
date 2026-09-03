@echo off
rem ---------------------------------------------------------------------------
rem  Double-click to play Blacktide Tactics.
rem
rem  Godot is found in this order:
rem    1. a GODOT_BIN environment variable
rem    2. godot_path.txt beside this file - one line, the full path to the exe.
rem       That file is gitignored on purpose: an absolute path committed to a
rem       public repo names the machine, and usually whoever owns it.
rem    3. godot.exe on PATH
rem ---------------------------------------------------------------------------
setlocal

set "GODOT=%GODOT_BIN%"

if not defined GODOT (
    if exist "%~dp0godot_path.txt" set /p GODOT=<"%~dp0godot_path.txt"
)

if not defined GODOT (
    for %%G in (godot.exe) do set "GODOT=%%~$PATH:G"
)

if not exist "%GODOT%" (
    echo.
    echo   Could not find Godot.
    echo.
    echo   Either set a GODOT_BIN environment variable pointing at your Godot
    echo   executable, or create godot_path.txt beside this file containing the
    echo   full path to it on a single line.
    echo.
    pause
    exit /b 1
)

echo Starting Blacktide Tactics...
echo.

rem "%~dp0." is this file's own folder. The trailing dot keeps the closing quote
rem from being escaped by the backslash Windows puts on the end of %~dp0.
"%GODOT%" --path "%~dp0."

if errorlevel 1 (
    echo.
    echo   The game exited with an error. The messages above should say why.
    echo.
    pause
)
