@echo off
setlocal EnableExtensions
rem backup.cmd SOURCE [DESTROOT]  -- exit codes: 0 ok, 1 copy failed, 2 usage, 3 not a folder

set "SELF=%~nx0"
if "%~1"=="" (echo usage: %SELF% SOURCE [DESTROOT] & exit /b 2)
if "%~1"=="/?" (echo usage: %SELF% SOURCE [DESTROOT] & exit /b 0)
if not exist "%~1\" (echo not a folder: %~1 & exit /b 3)

set "SRC=%~1"
set "DEST=%~2"
if not defined DEST set "DEST=%TEMP%\backups"

for /f %%a in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "TS=%%a"
set "TARGET=%DEST%\backup-%TS%"
set "LOG=%DEST%\backup.log"

if not exist "%DEST%\" mkdir "%DEST%" || (echo cannot create %DEST% & exit /b 1)
>> "%LOG%" echo %TS% start %SRC% to %TARGET%

robocopy "%SRC%" "%TARGET%" /e /r:1 /w:1 >nul
if errorlevel 8 (
    >> "%LOG%" echo %TS% FAILED code %errorlevel%
    echo backup failed
    exit /b 1
)
>> "%LOG%" echo %TS% ok
echo backup ok: %TARGET%
exit /b 0
