@echo off
setlocal EnableDelayedExpansion
echo --- double expansion with call
set "name=color"
set "color=blue"
call echo %%%name%%%
call echo value is %%%name%%%
echo --- emulated array
set i=0
for %%f in (apple banana cherry) do (set /a i+=1 & set "arr[!i!]=%%f")
set count=%i%
for /l %%n in (1,1,%count%) do echo arr[%%n]=!arr[%%n]!
echo --- list array via set prefix
set arr
echo --- string length
set "s=hello world"
set "len=0"
:lenloop
if not "!s:~%len%,1!"=="" (set /a len+=1 & goto lenloop)
echo length=%len%
echo --- upper case via loop replace
set "u=hello"
for %%c in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do set "u=!u:%%c=%%c!"
echo upper=%u%
echo --- test string contains
set "path1=C:\Program Files\App"
if not "!path1:Program=!"=="!path1!" (echo contains-Program) else echo no
echo --- trim trailing spaces
set "t=hello   "
for /l %%i in (1,1,5) do if "!t:~-1!"==" " set "t=!t:~0,-1!"
echo [%t%]
echo --- bang literal
set "msg=Wow^^!"
echo !msg!
echo --- loop sum with arrays and goto
set "sum=0"
for /l %%i in (1,1,100) do set /a sum+=%%i
echo sum1to100=%sum%
echo --- start /b parallel
start /b cmd /c "echo job1 done"
start /b cmd /c "echo job2 done"
timeout /t 1 >nul 2>&1
ping -n 2 127.0.0.1 >nul
echo --- reg query
reg query "HKCU\Control Panel\Desktop" /v WallPaper 2>nul | findstr /i wallpaper >nul && echo reg-ok
echo --- here: PowerShell inline
for /f "delims=" %%a in ('powershell -NoProfile -Command "(Get-Date).Year"') do echo year=%%a
