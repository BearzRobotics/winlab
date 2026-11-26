@echo off
rem Battery 2 for foundations.cmd-text-and-files. Works only inside a new folder under %TEMP%.
rem Run:  cmd.exe /d /c ".\text2.cmd > out.txt 2>&1"
setlocal
set "work=%TEMP%\wlt%RANDOM%%RANDOM%"
if exist "%work%" (echo %work% already exists & exit /b 1)
mkdir "%work%\src\sub" "%work%\dst" || exit /b 1
pushd "%work%" || exit /b 1
> a.txt echo alpha
>> a.txt echo beta
>> a.txt echo gamma
> b.txt echo alpha
>> b.txt echo BETA changed
>> b.txt echo gamma
>> b.txt echo delta
echo === fc of different files
fc a.txt b.txt
echo errorlevel %errorlevel%
echo === fc /n
fc /n a.txt b.txt
echo === fc /b on two small different files
> c.bin echo ab
> d.bin echo ac
fc /b c.bin d.bin
echo errorlevel %errorlevel%
echo === fc with a missing file
fc a.txt nothere.txt
echo errorlevel %errorlevel%
echo === LF only file, created by PowerShell
powershell -NoProfile -Command "[IO.File]::WriteAllText('lf.log', ('one ERROR' + [char]10 + 'two ok' + [char]10 + 'three ERROR' + [char]10))"
echo -- plain search
findstr /n "ERROR" lf.log
echo -- anchored at end of line
findstr /n /e "ERROR" lf.log
echo exit %errorlevel%
findstr /n "ERROR$" lf.log
echo exit %errorlevel%
echo -- count of lines according to find
type lf.log | find /c /v ""
echo === the same text with CRLF
powershell -NoProfile -Command "[IO.File]::WriteAllText('crlf.log', ('one ERROR' + [char]13 + [char]10 + 'two ok' + [char]13 + [char]10 + 'three ERROR' + [char]13 + [char]10))"
findstr /n /e "ERROR" crlf.log
echo exit %errorlevel%
echo === a file written by Windows PowerShell 5.1 redirection (UTF-16)
powershell -NoProfile -Command "'disk ERROR here' > u16.log"
echo -- type shows
type u16.log
echo -- findstr
findstr "ERROR" u16.log
echo findstr exit %errorlevel%
echo -- find
find "ERROR" u16.log
echo find exit %errorlevel%
echo -- type piped to findstr
type u16.log | findstr "ERROR"
echo pipe exit %errorlevel%
echo === findstr on a missing file
findstr "x" nothere.txt
echo exit %errorlevel%
echo === robocopy mirror: dry run, then real
> src\keep.txt echo keep
> src\sub\new.txt echo new
> dst\old-report.txt echo do not lose me
> dst\keep.txt echo older keep
mkdir dst\stale
> dst\stale\x.log echo x
echo -- dry run with /mir /l
robocopy src dst /mir /l /njh /njs /np /ndl
echo exit %errorlevel%
dir /b /s dst | find /c /v ""
echo -- dry run summary
robocopy src dst /mir /l /njh /np /nfl /ndl
echo -- real run
robocopy src dst /mir /njh /njs /np /ndl /nfl
echo exit %errorlevel%
echo -- destination now
dir /b /s /a-d dst | findstr /r "."
echo === xcopy
xcopy src xc /e /i /y
echo exit %errorlevel%
echo === attrib output
> att.txt echo x
attrib +r +h att.txt
attrib att.txt
attrib -r -h att.txt
attrib att.txt
echo === forfiles: age filter
> fresh.log echo new
> stale.log echo old
powershell -NoProfile -Command "(Get-Item stale.log).LastWriteTime = (Get-Date).AddDays(-40)"
forfiles /m *.log /d -30 /c "cmd /c echo older than 30 days: @file @fdate"
echo exit %errorlevel%
forfiles /m *.none /c "cmd /c echo @file"
echo exit %errorlevel%
echo === sort with padding
> n.txt echo 10
>> n.txt echo 9
>> n.txt echo 100
sort n.txt
popd
rmdir /s /q "%work%"
if exist "%work%" (echo cleanup FAILED) else (echo cleaned up)
