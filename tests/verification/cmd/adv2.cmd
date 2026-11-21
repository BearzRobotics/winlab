@echo off
setlocal EnableDelayedExpansion
echo --- octal trap fix
set "mm=08"
set /a bad=mm+1 2>&1
set /a good=1%mm%-100
echo good=%good%
echo --- reg add/query/delete in HKCU test key
reg add "HKCU\Software\WinLabTest" /v Name /t REG_SZ /d "Demo App" /f
reg add "HKCU\Software\WinLabTest" /v Count /t REG_DWORD /d 5 /f
reg query "HKCU\Software\WinLabTest"
for /f "tokens=2,*" %%a in ('reg query "HKCU\Software\WinLabTest" /v Name ^| findstr Name') do echo parsed-name=[%%b]
reg export "HKCU\Software\WinLabTest" "%TEMP%\wl-cmd-demo\test.reg" /y >nul
type "%TEMP%\wl-cmd-demo\test.reg" | findstr /i "Name Count"
reg delete "HKCU\Software\WinLabTest" /f
reg query "HKCU\Software\WinLabTest" >nul 2>&1 || echo key-gone
echo --- tasklist filter
tasklist /fi "imagename eq explorer.exe" /fo csv /nh
echo --- taskkill help line
taskkill /? | findstr /i "/pid"
echo --- recursion factorial
call :fact 5 r
echo fact5=%r%
goto :eof
:fact
setlocal
set /a n=%1
if %n% leq 1 (endlocal & set "%2=1" & exit /b 0)
set /a m=n-1
call :fact %m% sub
set /a res=n*sub
endlocal & set "%2=%res%"
exit /b 0
