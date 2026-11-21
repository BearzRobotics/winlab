@echo off
cd /d "%~dp0tx"
echo --- find
find /c "ERROR" logs\app.log
find /i "error" logs\app.log
find /v /c "" logs\app.log
echo --- findstr regex and options
findstr /n /i "error" logs\app.log
findstr /r "^2026-11-21.*ERROR" logs\app.log
findstr /b /c:"2026-11-20" logs\app.log
findstr /i /c:"ERROR disk" /c:"timeout" logs\app.log
findstr /s /i "adam" data\*.txt
findstr /v /i "info" logs\app.log
findstr /m "ERROR" logs\*.log
echo --- sort
sort data\names.txt
sort /r data\names.txt
sort data\nums.txt
echo --- sort+uniq via sort only
sort data\names.txt | findstr /v /b /c:"x"
echo --- type and more
type data\names.txt | find /c /v ""
echo --- forfiles
forfiles /p logs /m *.log /c "cmd /c echo @file @fsize bytes"
echo --- robocopy dry run
robocopy logs "%TEMP%\wl-cmd-demo\rc-dest" *.log /l /njh /njs /ndl /nc /ns
echo rc=%errorlevel%
echo --- attrib and dir /a
attrib +h data\names.txt
dir /b /a:h data
attrib -h data\names.txt
echo --- fc
copy data\names.txt data\copy.txt >nul
fc data\names.txt data\copy.txt
echo fc-same=%errorlevel%
> data\copy.txt echo different
fc data\names.txt data\copy.txt >nul
echo fc-diff=%errorlevel%
echo --- comp-ish via type
type data\copy.txt
echo --- tree and dir /s /b
dir /s /b *.log
