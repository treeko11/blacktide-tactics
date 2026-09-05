@echo off
rem ---------------------------------------------------------------------------
rem  Double-click to build the web export into web\.
rem
rem  Options, for a terminal:
rem    --debug        export the debug template instead of the release one
rem    --serve        after exporting, serve web\ and open a browser at it
rem    --serve-only   skip the export, just serve what is already in web\
rem    --port N       the port --serve listens on (default 8060)
rem
rem  Godot is found in this order:
rem    1. a GODOT_BIN environment variable
rem    2. godot_path.txt beside this file - one line, the full path to the exe.
rem       That file is gitignored on purpose: an absolute path committed to a
rem       public repo names the machine, and usually whoever owns it.
rem    3. godot.exe on PATH
rem ---------------------------------------------------------------------------
setlocal enabledelayedexpansion

set "MODE=release"
set "DOEXPORT=1"
set "DOSERVE=0"
set "PORT=8060"
set "RESULT=0"

:parse
if "%~1"=="" goto parsed
if /i "%~1"=="--debug" (
    set "MODE=debug"
    shift
    goto parse
)
if /i "%~1"=="--serve" (
    set "DOSERVE=1"
    shift
    goto parse
)
if /i "%~1"=="--serve-only" (
    set "DOSERVE=1"
    set "DOEXPORT=0"
    shift
    goto parse
)
if /i "%~1"=="--port" (
    set "PORT=%~2"
    shift
    shift
    goto parse
)
echo.
echo   Unknown option "%~1". Options: --debug --serve --serve-only --port N
echo.
exit /b 2
:parsed

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

rem The shipped Godot_..._win64.exe is a GUI-subsystem binary: it detaches from
rem the console, so it prints nothing and its exit code is not waited for. An
rem export that failed would look exactly like one that worked. The 198 KB
rem _console.exe beside it keeps the console attached, so use that when it is
rem there.
set "GODOT_RUN=%GODOT%"
if /i "%GODOT:~-4%"==".exe" (
    set "CONSOLE=%GODOT:~0,-4%_console.exe"
    if exist "!CONSOLE!" set "GODOT_RUN=!CONSOLE!"
)

if "%DOEXPORT%"=="0" goto serve

rem ---------------------------------------------------------------------------
rem  Export templates. This check only ever helps: a version string it cannot
rem  parse, or templates installed somewhere else, prints nothing and the export
rem  goes ahead and speaks for itself.
rem ---------------------------------------------------------------------------
set "VER="
"%GODOT_RUN%" --headless --version > "%TEMP%\blacktide_version.txt" 2>&1
set /p VER=<"%TEMP%\blacktide_version.txt"
del "%TEMP%\blacktide_version.txt" >nul 2>&1

rem 4.7.2.stable.official.<hash>, but a .0 patch is omitted - 4.7.stable.official
rem - so the template folder is the version up to and including the first part
rem that is not a number.
set "TPL="
for /f "tokens=1-4 delims=." %%a in ("%VER%") do (
    echo %%c| findstr /R /C:"^[0-9][0-9]*$" >nul
    if errorlevel 1 (set "TPL=%%a.%%b.%%c") else (set "TPL=%%a.%%b.%%c.%%d")
)
if defined TPL (
    dir /b "%APPDATA%\Godot\export_templates\%TPL%\web_*.zip" >nul 2>&1
    if errorlevel 1 (
        echo.
        echo   No web export templates for %TPL% in
        echo   %%APPDATA%%\Godot\export_templates\.
        echo.
        echo   Open the editor once and use Editor ^> Manage Export Templates,
        echo   or drop the matching .tpz there. Trying the export anyway.
        echo.
    )
)

rem ---------------------------------------------------------------------------
rem  Export
rem ---------------------------------------------------------------------------
set "LOG=%TEMP%\blacktide_export.txt"

echo.
echo   Refreshing the import cache...
"%GODOT_RUN%" --headless --path "%~dp0." --import >nul 2>&1

echo   Exporting the Web preset (%MODE%) into web\...
echo.
"%GODOT_RUN%" --headless --path "%~dp0." --export-%MODE% "Web" "%~dp0web\index.html" > "%LOG%" 2>&1
set "RESULT=%ERRORLEVEL%"

rem The pack step names every one of the ~700 files it stores, which buries the
rem three lines anybody needs to read.
type "%LOG%" | findstr /V /C:"Storing File:" | findstr /V /B /C:"   at: " /C:"   GDScript backtrace" /C:"       ["

rem A plain ERROR cannot be the failure signal: a clean export ends with
rem "2 resources still in use at exit", which is Godot tidying up after itself.
rem A SCRIPT ERROR during an export is never deliberate, and the export can
rem still finish and exit 0 around one - a build that boots to a broken script
rem in a browser, which is the one place nobody can attach a debugger.
findstr /B /C:"SCRIPT ERROR" "%LOG%" >nul
if not errorlevel 1 (
    echo.
    echo   SCRIPT ERRORS during the export - the build is not trustworthy:
    echo.
    findstr /B /C:"SCRIPT ERROR" "%LOG%"
    set "RESULT=1"
)
del "%LOG%" >nul 2>&1

if not "%RESULT%"=="0" (
    echo.
    echo   THE EXPORT FAILED. web\ still holds the previous build.
    echo.
    pause
    exit /b %RESULT%
)

rem Godot has been known to report success having written nothing, so the four
rem files the page cannot load without are checked rather than assumed.
set "MISSING="
for %%F in ("%~dp0web\index.html" "%~dp0web\index.js" "%~dp0web\index.wasm" "%~dp0web\index.pck") do (
    if not exist %%F (
        set "MISSING=!MISSING! %%~nxF"
    ) else if %%~zF EQU 0 (
        set "MISSING=!MISSING! %%~nxF^(empty^)"
    )
)
if defined MISSING (
    echo.
    echo   The export reported success but did not write:!MISSING!
    echo.
    pause
    exit /b 1
)

echo.
echo   Exported. web\ now holds:
echo.
set /a TOTAL=0
for %%F in ("%~dp0web\*") do (
    set /a TOTAL+=%%~zF
    echo      %%~tF   %%~nxF
)
set /a TOTALMB=TOTAL/1048576
echo.
echo      %TOTALMB% MB in total - that is what a first visit downloads.

where git >nul 2>&1
if not errorlevel 1 (
    echo.
    echo   Changed, according to git:
    echo.
    git -C "%~dp0." status --short -- web/
)

echo.
echo   Nothing is committed or pushed by this script. The live build is
echo   whatever is on main, so it updates when web\ is pushed.

:serve
if "%DOSERVE%"=="0" goto done

set "PY="
for %%P in (py.exe python.exe python3.exe) do if not defined PY set "PY=%%~$PATH:P"
if not defined PY (
    echo.
    echo   --serve needs Python on PATH and did not find any. The build is
    echo   fine; serve web\ with any static server instead.
    goto done
)

echo.
echo   Serving web\ at http://localhost:%PORT%/ - Ctrl-C to stop.
echo.
echo   Opening a file:// double-click will NOT work: the browser refuses to
echo   fetch index.pck off the filesystem, so the page hangs on the loader.
echo.
start "" "http://localhost:%PORT%/"
"%PY%" -m http.server %PORT% --directory "%~dp0web"
goto :eof

:done
echo.
pause
exit /b %RESULT%
