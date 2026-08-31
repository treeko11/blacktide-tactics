@echo off
rem ---------------------------------------------------------------------------
rem  Double-click to open the project in the Godot editor.
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

echo Opening the Blacktide Tactics project in the Godot editor...
start "" "%GODOT%" --editor --path "%~dp0."
