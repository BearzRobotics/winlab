@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
echo --- args loop with shift
call :args one "two words" three
echo --- switch parsing
call :parse /v "/out:my file.txt" target
echo --- admin check
net session >nul 2>&1 && (echo admin=yes) || (echo admin=no)
fltmc >nul 2>&1 && (echo fltmc-admin=yes) || (echo fltmc-admin=no)
echo --- echo blank lines
echo(
echo.
echo(text with leading paren trick
echo --- pushd popd
pushd "%TEMP%"
echo in %CD%
popd
echo back %CD%
echo --- log helper
set "LOG=%TEMP%\wl-cmd-demo\run.log"
> "%LOG%" echo start
call :log "step one"
call :log "step two"
type "%LOG%"
echo --- here-doc-ish
(
  echo line1
  echo line2 ^& more
) > heredoc.txt
type heredoc.txt
echo --- multi-line string via ^
echo first ^
second
echo --- start /wait
start /wait "" cmd /c exit 5
echo start-wait-el=%errorlevel%
echo --- findstr basics
findstr /i /c:"line2" heredoc.txt
echo found-el=%errorlevel%
findstr /i "zzz" heredoc.txt >nul
echo notfound-el=%errorlevel%
goto :eof
:args
set n=0
:argloop
if "%~1"=="" exit /b 0
set /a n+=1
echo arg!n!=[%~1]
shift
goto argloop
:parse
:ploop
if "%~1"=="" exit /b 0
set "a=%~1"
if "!a:~0,1!"=="/" (echo switch: %~1) else (echo positional: %~1)
shift
goto ploop
:log
>> "%LOG%" echo %date:~-4% %~1
exit /b 0
