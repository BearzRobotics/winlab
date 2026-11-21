@echo off
echo --- quoted shift
set /a "g=1<<4"
echo %g%
set /a "m=0xFF & 0x0F"
echo %m%
echo --- nul set /p
<nul set /p "=no newline here"
echo  <-- same line
echo --- set /p from pipe
echo Alice| (set /p who=Name: & call echo got %%who%%)
echo --- endlocal return
call :f
echo result=%result%
echo --- x86 in block
if 1==1 (
  echo before
  echo %ProgramFiles(x86)%
)
echo --- percent in set /a mod
set /a k=10 %% 3
echo %k%
echo --- !bang with delayed
setlocal enabledelayedexpansion
set "t=Hello!"
echo !t!
echo %t%
endlocal
echo --- shift
call :sh a b c
goto :eof
:f
setlocal
set "local1=value from inside"
endlocal & set "result=%local1%"
goto :eof
:sh
echo %1 %2 %3
shift
echo %1 %2 %3
goto :eof
