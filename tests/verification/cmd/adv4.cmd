@echo off
rem Battery 4 for foundations.cmd-advanced: hostile input to the pipe-based check, and recursion with setlocal.
rem Run:  cmd.exe /d /c ".\adv4.cmd > out.txt 2>&1"
setlocal
set "work=%TEMP%\wlb%RANDOM%%RANDOM%"
if exist "%work%" (echo %work% already exists & exit /b 1)
mkdir "%work%" || exit /b 1
pushd "%work%" || exit /b 1
> v.cmd echo @echo off
>> v.cmd echo setlocal EnableDelayedExpansion
>> v.cmd echo set "x=%%~1"
>> v.cmd echo echo(!x!^| findstr /r "^[0-9][0-9]*$" ^>nul ^&^& echo   accepted ^|^| echo   rejected
echo === hostile input to the pipe version
for %%v in ("5&echo.> pwned.txt" "5>made.txt" "5|echo x> piped.txt") do (echo input %%v & call .\v.cmd %%v)
echo files that appeared:
dir /b | findstr /v /i ".cmd"
echo === recursion with setlocal at 400 and 1000
> r.cmd echo @echo off
>> r.cmd echo set "max=%%1"
>> r.cmd echo set "d=0"
>> r.cmd echo call :down
>> r.cmd echo echo reached the target depth %%max%%
>> r.cmd echo exit /b 0
>> r.cmd echo :down
>> r.cmd echo setlocal
>> r.cmd echo set /a d+=1
>> r.cmd echo if %%d%% lss %%max%% call :down
>> r.cmd echo exit /b 0
for %%n in (300 1000) do (echo depth %%n: & cmd /d /c .\r.cmd %%n)
popd
rmdir /s /q "%work%"
if exist "%work%" (echo cleanup FAILED) else (echo cleaned up)
