@echo off
rem Battery 2 for foundations.cmd-variables-and-expansion. Works only inside a new folder under %TEMP%.
rem Run:  cmd.exe /d /c ".\vars2.cmd > out.txt 2>&1"
setlocal
set "work=%TEMP%\wl-cmdv-%RANDOM%%RANDOM%"
if exist "%work%" (echo %work% already exists & exit /b 1)
mkdir "%work%" || exit /b 1
pushd "%work%" || exit /b 1
set "nosuch="
echo === undefined variable in a batch file
echo [%nosuch%]
echo === undefined variable on a command line given to cmd /c
cmd /d /c echo [%%nosuch%%]
echo === slicing an undefined variable in a batch file
echo [%nosuch:~0,3%]
echo [%nosuch:a=b%]
echo === the empty variable in an if
> t1.cmd echo @echo off
>> t1.cmd echo set "v="
>> t1.cmd echo if %%v%%==yes echo matched
>> t1.cmd echo echo reached the end
cmd /d /c .\t1.cmd
echo exit %errorlevel%
> t2.cmd echo @echo off
>> t2.cmd echo set "v="
>> t2.cmd echo if "%%v%%"=="yes" echo matched
>> t2.cmd echo echo reached the end
echo -- quoted:
cmd /d /c .\t2.cmd
echo === echo on shows lines AFTER percent expansion
> t3.cmd echo set "name=World"
>> t3.cmd echo set "n=0"
>> t3.cmd echo for %%%%i in (a b) do (set /a n+=1 ^& echo %%name%% %%n%%)
cmd /d /c .\t3.cmd
echo === echo on with delayed expansion
> t4.cmd echo setlocal enabledelayedexpansion
>> t4.cmd echo set "n=0"
>> t4.cmd echo for %%%%i in (a b) do (set /a n+=1 ^& echo !n!)
cmd /d /c .\t4.cmd
echo === a child cannot change the parent
set "FROM=parent"
> child.cmd echo @echo off
>> child.cmd echo set "FROM=child"
>> child.cmd echo echo inside child: %%FROM%%
cmd /d /c .\child.cmd
echo after running it in a new cmd: %FROM%
call .\child.cmd
echo after CALL, same cmd: %FROM%
set "FROM=parent"
echo === inheritance
set "HANDED_DOWN=hello"
cmd /d /c set HANDED_DOWN
echo === set /p from a pipe and from a file
set "ans=before"
echo.| (set /p ans=prompt: )
echo after a pipe, in this cmd: [%ans%]
set "ans=before"
> empty.txt echo.
set /p ans=<empty.txt
echo after an empty line from a file: [%ans%]
> two.txt echo first line
>> two.txt echo second line
set /p ans=<two.txt
echo from a two line file: [%ans%]
echo === set /a errors
set /a x=08
echo errorlevel %errorlevel%
set /a y=1/0
echo errorlevel %errorlevel%
set /a z=abc+1
echo z=%z%
set "t=12abc"
set /a w=t+1
echo errorlevel %errorlevel% w=%w%
echo === padding a number with a leading zero before arithmetic
set "m=09"
set /a mm=1%m%-100
echo %mm%
echo === what set lists for a name that begins the same
set "wl_a=1"
set "wl_ab=2"
set wl_a
echo === dynamic variables are not listed
set ERRORLEVEL
echo === DATE and TIME here
echo [%DATE%] [%TIME%]
popd
rmdir /s /q "%work%"
if exist "%work%" (echo cleanup FAILED) else (echo cleaned up)
