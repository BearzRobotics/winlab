@echo off
rem Battery 3 for foundations.cmd-advanced. Works only inside a new folder under %TEMP%; reads tasklist.
rem Run:  cmd.exe /d /c ".\adv3.cmd > out.txt 2>&1"
setlocal
set "work=%TEMP%\wla%RANDOM%%RANDOM%"
if exist "%work%" (echo %work% already exists & exit /b 1)
mkdir "%work%" || exit /b 1
pushd "%work%" || exit /b 1

echo === the lesson's validation line, delayed expansion on, several inputs
> v.cmd echo @echo off
>> v.cmd echo setlocal EnableDelayedExpansion
>> v.cmd echo set "x=%%~1"
>> v.cmd echo echo(!x!^| findstr /r "^[0-9][0-9]*$" ^>nul ^&^& echo   accepted [!x!] ^|^| echo   rejected [!x!]
for %%v in (42 abc "12 34") do call .\v.cmd %%v
echo -- what the left side of that pipe really sends:
> v2.cmd echo @echo off
>> v2.cmd echo setlocal EnableDelayedExpansion
>> v2.cmd echo set "x=42"
>> v2.cmd echo echo(!x!^| findstr "."
cmd /d /c .\v2.cmd

echo === a version that checks without a pipe: delete every digit and see if anything is left
> w.cmd echo @echo off
>> w.cmd echo setlocal EnableDelayedExpansion
>> w.cmd echo set "x=%%~1"
>> w.cmd echo if not defined x (echo   rejected empty ^& exit /b 1)
>> w.cmd echo set "rest=!x!"
>> w.cmd echo for /l %%%%d in (0,1,9) do if defined rest set "rest=!rest:%%%%d=!"
>> w.cmd echo if defined rest (echo   rejected [!x!]) else (echo   accepted [!x!])
for %%v in (42 0 abc 4a2 "12 34" "5&echo INJECTED" "") do call .\w.cmd %%v

echo === arrays: dump and walk
setlocal EnableDelayedExpansion
set i=0
for %%f in (apple banana "kiwi fruit") do (set /a i+=1 & set "arr[!i!]=%%~f")
echo -- set arr[
set arr[
echo -- walk with for /f
for /f "tokens=1,* delims==" %%a in ('set arr[') do echo   %%a holds %%b
echo -- eleven items list in text order
for /l %%n in (4,1,11) do set "arr[%%n]=item %%n"
set arr[
endlocal

echo === tasklist csv parsed with for /f
for /f "tokens=1,2 delims=," %%a in ('tasklist /fi "imagename eq explorer.exe" /fo csv /nh') do echo raw=[%%a] pid-quoted=[%%b] pid=[%%~b]
echo -- no such image
tasklist /fi "imagename eq nosuch-image.exe" /fo csv /nh
for /f "tokens=1 delims=," %%a in ('tasklist /fi "imagename eq nosuch-image.exe" /fo csv /nh') do echo loop saw [%%a]

echo === recursion depth
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
for %%n in (20 31 40 100) do (echo depth %%n: & cmd /d /c .\r.cmd %%n)
echo -- the same without setlocal
findstr /v /x "setlocal" r.cmd > r2.cmd
for %%n in (100 1000) do (echo depth %%n: & cmd /d /c .\r2.cmd %%n)

echo === waiting with ping
echo %time%
ping -n 4 127.0.0.1 >nul
echo %time%

popd
rmdir /s /q "%work%"
if exist "%work%" (echo cleanup FAILED) else (echo cleaned up)
