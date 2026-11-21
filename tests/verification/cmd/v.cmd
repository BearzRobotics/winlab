@echo off
setlocal
echo --- spaces trap
set x = 1
set x
echo [%x %] [%x%]
set "x ="
echo --- quoted form
set "name=Alice "
echo [%name%]
set name=Bob 
echo [%name%]
set "name=Bob"
echo [%name%]
echo --- delete
set name=
if defined name (echo defined) else (echo not defined)
echo --- arithmetic
set /a a=7*6
echo %a%
set /a b=17/5, c=17%%5
echo %b% %c%
set /a d=010+1
echo octal: %d%
set /a e=0x1F
echo hex: %e%
set /a f=2147483647+1
echo overflow: %f%
set /a g=1 ^<^< 4
echo shift: %g%
set /a h=5, h+=3
echo %h%
echo --- substitution
set s=C:\Dir\file.txt
echo %s:\=/%
echo %s:~3,3%
echo %s:~-3%
echo %s:~0,-4%
echo %s:*\=%
echo --- same-line trap
set y=1 & echo y=%y%
echo after: %y%
echo --- delayed
setlocal enabledelayedexpansion
set z=0
for %%i in (a b c) do (set /a z+=1 & echo !z!)
for %%i in (a b c) do (set /a z+=1 & echo %z%)
endlocal
echo --- modifiers
call :mods "C:\Windows\System32\drivers\etc\hosts"
echo --- random range
set /a r=%random% %% 6 + 1
if %r% geq 1 if %r% leq 6 echo random-ok
echo --- builtin dyn
echo %CMDEXTVERSION%
goto :eof
:mods
echo %~1
echo f=%~f1
echo d=%~d1
echo p=%~p1
echo n=%~n1
echo x=%~x1
echo dp=%~dp1
echo nx=%~nx1
echo z=%~z1
goto :eof
