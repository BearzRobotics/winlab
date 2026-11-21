@echo off
setlocal enabledelayedexpansion
cd /d "%TEMP%\wl-cmd-demo"
echo --- numeric vs string
if 10 gtr 9 (echo numeric: 10 gtr 9 true) else (echo numeric false)
if "10" lss "9" (echo string: "10" lss "9" true) else (echo string false)
if "10"=="10" echo equal-text
if /i "ABC"=="abc" echo case-insens
echo --- if exist folder
mkdir folderx 2>nul
if exist folderx\ (echo folder-exists) else echo no-folder
if exist folderx\nul echo nul-test-works
echo --- empty var
set "e="
if "%e%"=="" echo empty-ok
if not defined e echo not-defined
echo --- for /f forms
> data.csv echo id,name,city
>> data.csv echo 1,Ann,Oslo
>> data.csv echo 2,Bob,Rome
for /f "skip=1 tokens=1,2 delims=," %%a in (data.csv) do echo id=%%a name=%%b
for /f "skip=1 tokens=2* delims=," %%a in (data.csv) do echo first=%%a rest=%%b
for /f "tokens=*" %%a in ("   leading spaces kept?") do echo [%%a]
for /f "delims=" %%a in ('echo hello world') do echo cmd-output=%%a
for /f "usebackq delims=" %%a in (`echo backquoted`) do echo %%a
echo --- eol and blank lines
> lines.txt echo #comment
>> lines.txt echo.
>> lines.txt echo real line
>> lines.txt echo ;semi
for /f "delims=" %%a in (lines.txt) do echo got:[%%a]
for /f "eol=# delims=" %%a in (lines.txt) do echo eol-skip:[%%a]
echo --- for /l /d /r
for /l %%i in (3,-1,1) do <nul set /p "=%%i "
echo.
mkdir folderx\inner 2>nul
for /d %%d in (folderx\*) do echo dir:%%d
for /r folderx %%f in (*) do echo file:%%~nxf
echo --- errorlevel in block
dir nothere >nul 2>&1
if errorlevel 1 (echo block-sees-1)
dir nothere >nul 2>&1 & (echo percent=%errorlevel%) 
(dir nothere >nul 2>&1 & echo bang=!errorlevel!)
echo --- and/or chain gotcha
echo a | findstr z >nul && echo and-ok || echo or-fired
true 2>nul || echo or-after-missing-cmd
dir . >nul && (echo first-ok & dir nothere >nul 2>&1) || echo or-ran-after-failed-second
echo --- call and exit /b
call :add 2 3
echo sum=%sum% el=%errorlevel%
call :fail
echo fail-el=%errorlevel%
echo --- choice
choice /c YN /n /m "Press Y: " <nul 2>nul
echo choice-el=%errorlevel%
goto :eof
:add
set /a sum=%1+%2
exit /b 0
:fail
exit /b 7
