@echo off
rem Battery 2 for foundations.cmd-basics: reading output, copy/move/ren/del behaviour, redirection, exit codes.
rem Works only inside a new folder under %TEMP% and removes it. Run:  cmd.exe /d /c .\basics2.cmd
setlocal
set "work=%TEMP%\wl-cmdb-%RANDOM%%RANDOM%"
if exist "%work%" (echo %work% already exists & exit /b 1)
mkdir "%work%\sub" "%work%\My Files" || exit /b 1
pushd "%work%" || exit /b 1
> a.txt echo one
> b.log echo two two two
> ".hidden-by-name.txt" echo x
> h.txt echo secret
attrib +h h.txt
echo === dir
dir
echo === dir /a
dir /a
echo === dir /b
dir /b
echo === dir /b /a
dir /b /a
echo === dir /b /o:-s /a-d
dir /b /o:-s /a-d
echo === dir /ad /b
dir /ad /b
echo === dir /b /s *.txt
dir /b /s *.txt
echo === dir of nothing
dir /b *.none
echo errorlevel %errorlevel%
echo === wildcard matches
dir /b ?.txt
echo === tree /f /a
tree /f /a
echo === copy onto an existing file in a batch file
> c.txt echo original
copy a.txt c.txt
type c.txt
echo === copy /-y asks (answer N is piped)
> d.txt echo keep-me
echo N| copy /-y a.txt d.txt
type d.txt
echo === move onto existing in a batch file
> e.txt echo old-e
> f.txt echo new-f
move f.txt e.txt
type e.txt
echo === ren onto existing
> g.txt echo g
ren g.txt a.txt
echo errorlevel %errorlevel%
echo === ren with wildcard
> one.tmp echo 1
> two.tmp echo 2
ren *.tmp *.bak
dir /b *.bak
echo === del preview then delete
dir /b *.bak
del *.bak
dir /b *.bak
echo === del hidden file without /a
del h.txt
echo errorlevel %errorlevel%
dir /b /a h.txt
echo === rmdir non-empty
> sub\x.txt echo x
rmdir sub
echo errorlevel %errorlevel%
echo === streams
dir /b a.txt nothere > out.txt 2> err.txt
echo -- out.txt
type out.txt
echo -- err.txt
type err.txt
echo -- order A: ^> both 2^>^&1
dir /b a.txt nothere > both.txt 2>&1
type both.txt
echo -- order B: 2^>^&1 ^> only
dir /b a.txt nothere 2>&1 > only.txt
echo -- only.txt holds:
type only.txt
echo === sort via redirect and pipe
> n.txt echo banana
>> n.txt echo apple
sort < n.txt
type n.txt | findstr /i APP
echo findstr found: %errorlevel%
type n.txt | findstr cherry
echo findstr not found: %errorlevel%
echo === chaining
dir /b a.txt >nul && echo found || echo missing
dir /b zzz >nul 2>nul && echo found || echo missing
dir /b a.txt >nul && cmd /c exit 1 || echo "or-branch ran although the first command worked"
echo === errorlevel not reset by echo or by a successful builtin
cmd /c exit 5
echo after exit 5: %errorlevel%
echo something
echo after echo: %errorlevel%
set X=1
echo after set: %errorlevel%
ver >nul
echo after ver: %errorlevel%
echo === unknown command
nosuchcommand 2>err.txt
echo errorlevel %errorlevel%
type err.txt
echo === quoted path
cd "My Files" && cd
cd ..
cd My Files && cd
cd ..
dir /b My Files
echo === where
where cmd
where dir
echo errorlevel %errorlevel%
echo === help first line
help dir
echo === cd on another drive without /d
echo start: %CD:~0,2%
popd
rmdir /s /q "%work%"
if exist "%work%" (echo cleanup FAILED) else (echo cleaned up)
