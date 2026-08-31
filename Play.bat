@echo off
rem ---------------------------------------------------------------------------
rem  Double-click to play Blacktide Tactics.
rem
rem  If Godot ever moves, either set a GODOT_BIN environment variable or edit
rem  the path on the DEFAULT_GODOT line below.
rem ---------------------------------------------------------------------------
setlocal

set "DEFAULT_GODOT=F:\Users\Sam\Downloads\Godot_v4.7.2-stable_win64.exe"

set "GODOT=%GODOT_BIN%"
if "%GODOT%"=="" set "GODOT=%DEFAULT_GODOT%"

if not exist "%GODOT%" (
    echo.
    echo   Could not find Godot at:
    echo     %GODOT%
    echo.
    echo   Either set a GODOT_BIN environment variable pointing at your Godot
    echo   executable, or open this file in Notepad and change DEFAULT_GODOT.
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
