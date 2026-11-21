@echo off
cd /d "%~dp0tx"
echo --- for /f over piped command (escaped pipe)
for /f "tokens=2 delims=:" %%a in ('echo key:value:more ^| findstr key') do echo token2=%%a
echo --- more +n
more +2 data\names.txt
echo --- findstr regex limits
findstr /r "^[a-b]" data\names.txt
echo ---
findstr /r "o.*e" data\names.txt
echo ---
findstr /r /c:"a\{2\}" data\names.txt 2>&1
echo findstr-quantifier-el=%errorlevel%
echo --- findstr word match
findstr /r "\<adam\>" data\names.txt
echo --- sort by column
sort /+4 logs\app.log
echo --- dir sort by size and age
dir /b /o:-s logs
echo --- mklink
mklink /d linkdir logs 2>&1
echo mklink-el=%errorlevel%
echo --- xcopy flags
xcopy data "%TEMP%\wl-cmd-demo\xc" /e /i /y /q
echo xcopy-el=%errorlevel%
echo --- robocopy real copy and mirror
robocopy data "%TEMP%\wl-cmd-demo\rc2" /e /njh /njs /ndl /nc /ns /np
echo rc-first=%errorlevel%
robocopy data "%TEMP%\wl-cmd-demo\rc2" /e /njh /njs /ndl /nc /ns /np
echo rc-nochange=%errorlevel%
echo extra> "%TEMP%\wl-cmd-demo\rc2\extra.txt"
robocopy data "%TEMP%\wl-cmd-demo\rc2" /e /njh /njs /ndl /nc /ns /np /l
echo rc-extra-dryrun=%errorlevel%
robocopy data "%TEMP%\wl-cmd-demo\rc2" /mir /njh /njs /ndl /nc /ns /np /l
echo rc-mir-dryrun=%errorlevel%
echo --- forfiles older than
forfiles /p logs /m *.log /d -1 /c "cmd /c echo older @file" 2>&1
echo ff-el=%errorlevel%
echo --- type nul
type nul > empty.txt
dir /b empty.txt
for %%f in (empty.txt) do echo size=%%~zf
