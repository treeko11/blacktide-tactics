@echo off
rem ---------------------------------------------------------------------------
rem  Double-click to run the test suite.
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

rem Refresh the class cache first, or a newly added class_name is invisible and
rem every script referencing it fails to compile.
"%GODOT%" --headless --path "%~dp0." --import >nul 2>&1

rem Several tests deliberately exercise error paths and Godot prints a six-line
rem backtrace for each. The ERROR line itself is kept - that is real signal - but
rem its continuation lines are stripped.
set "LOG=%TEMP%\blacktide_tests.txt"
"%GODOT%" --headless --path "%~dp0." --script res://tools/run_tests.gd -- %* > "%LOG%" 2>&1
set "RESULT=%ERRORLEVEL%"

findstr /V /B /C:"   at: " /C:"   GDScript backtrace" /C:"       [" "%LOG%"

rem A SCRIPT ERROR is never deliberate. A GDScript error abandons the test method
rem and returns to the runner as though it finished, so the runner counts it as
rem passed - it cannot see its own stderr, but this can.
findstr /B /C:"SCRIPT ERROR" "%LOG%" >nul
if not errorlevel 1 (
    echo.
    echo   SCRIPT ERRORS - a test that errors mid-way still reports as passed,
    echo   so the run is failed here instead:
    echo.
    findstr /B /C:"SCRIPT ERROR" "%LOG%"
    echo.
    set "RESULT=1"
)

del "%LOG%" >nul 2>&1

echo.
pause

rem Everything above this line only prints. Without the exit code the runner's
rem own non-zero result was discarded by the last findstr, and the SCRIPT ERROR
rem branch said "the run is failed here instead" while still exiting 0 - so a red
rem suite was green to anything chaining off it.
exit /b %RESULT%
