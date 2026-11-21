@echo off
cd /d "%TEMP%\wl-cmd-demo"
echo --- ver
ver
echo --- where
where notepad
echo --- pathext
echo %PATHEXT%
echo --- mkdir/copy/ren/move/del
mkdir sub
echo one> a.txt
copy a.txt sub\b.txt
ren a.txt c.txt
move c.txt sub\ >nul
dir /b sub
tree /f
echo --- wildcard
dir /b sub\*.txt
echo --- redirect 2>&1
dir nothere > out.txt 2>&1
type out.txt
echo --- errorlevel
dir nothere >nul 2>nul
echo %ERRORLEVEL%
echo --- ampersand
echo a & echo b
echo --- escape
echo 1 ^& 2
echo --- cmd /c
cmd /c exit 3
echo %ERRORLEVEL%
echo --- cd forms
cd
echo %CD%
echo --- start
echo ok
