@echo off
rem Battery 3 for foundations.cmd-basics: which failures ERRORLEVEL shows, and .cmd against .bat.
rem Works only inside a new folder under %TEMP% and removes it. Run:  cmd.exe /d /c ".\basics3.cmd > out.txt 2>&1"
setlocal
set "work=%TEMP%\wl-cmdc-%RANDOM%%RANDOM%"
if exist "%work%" (echo %work% already exists & exit /b 1)
mkdir "%work%\full" || exit /b 1
pushd "%work%" || exit /b 1
> full\x.txt echo x
echo === del of a missing file
cmd /c exit 0
del nothere.txt
echo errorlevel after del: %errorlevel%
del nothere.txt && echo "del: success branch" || echo "del: failure branch"
echo === del of a folder pattern that matches nothing
del *.nomatch && echo "del pattern: success branch" || echo "del pattern: failure branch"
echo === rmdir of a non-empty folder
cmd /c exit 0
rmdir full
echo errorlevel after rmdir: %errorlevel%
rmdir full && echo "rmdir: success branch" || echo "rmdir: failure branch"
echo errorlevel after the failure branch: %errorlevel%
echo === copy of a missing file
cmd /c exit 0
copy nothere.txt there.txt
echo errorlevel after copy: %errorlevel%
echo === md of an existing folder
cmd /c exit 0
mkdir full
echo errorlevel after mkdir: %errorlevel%
echo === streams with one missing name
dir nothere > o.txt 2> e.txt
echo -- standard output:
type o.txt
echo -- standard error:
type e.txt
echo === 2^>^&1 order
echo -- A:
dir nothere > a.txt 2>&1
type a.txt
echo -- B (the next line should reach the screen):
dir nothere 2>&1 > b.txt
echo -- b.txt holds:
type b.txt
echo === does set change ERRORLEVEL: in a .cmd and in a .bat
> probe.cmd echo @echo off
>> probe.cmd echo cmd /c exit 5
>> probe.cmd echo set X=1
>> probe.cmd echo echo   after set: %%errorlevel%%
copy probe.cmd probe.bat >nul
echo probe.cmd:
cmd /d /c .\probe.cmd
echo probe.bat:
cmd /d /c .\probe.bat
echo === PATHEXT and a local program name
echo %PATHEXT%
> hello.cmd echo @echo hello from hello.cmd in the current folder
call hello
set NoDefaultCurrentDirectoryInExePath=1
echo -- with NoDefaultCurrentDirectoryInExePath set:
cmd /d /c hello
echo exit %errorlevel%
cmd /d /c .\hello
set "NoDefaultCurrentDirectoryInExePath="
popd
rmdir /s /q "%work%"
if exist "%work%" (echo cleanup FAILED) else (echo cleaned up)
