@echo off
rem Battery 2 for foundations.cmd-control-flow. Works only inside a new folder under %TEMP%.
rem Run:  cmd.exe /d /c ".\flow2.cmd > out.txt 2>&1"
setlocal
set "work=%TEMP%\wl-cmdf-%RANDOM%%RANDOM%"
if exist "%work%" (echo %work% already exists & exit /b 1)
mkdir "%work%\data\old" "%work%\data\empty" "%work%\My Files" || exit /b 1
pushd "%work%" || exit /b 1
> data\one.txt echo 1
> "data\two words.txt" echo 22
> data\old\three.log echo 333
> data\old\four.txt echo 4444
echo === for over words and wildcards
for %%a in (alpha "b c" data\*.txt) do echo [%%a]
echo === wildcard with no match
for %%f in (data\*.none) do echo found %%f
echo loop finished, errorlevel %errorlevel%
echo === a word without wildcard that does not exist
for %%f in (data\nothere.txt) do echo got %%f
echo === unquoted loop variable with a space
for %%f in (data\*.txt) do dir /b %%f 2>nul || echo   failed for [%%f]
echo === quoted
for %%f in (data\*.txt) do dir /b "%%f"
echo === for /d
for /d %%d in (data\*) do echo %%d
echo === for /r
for /r data %%f in (*.txt) do echo %%~nxf  in  %%~dpf
echo === modifiers
for %%f in (data\old\four.txt) do echo name=%%~nf ext=%%~xf size=%%~zf
echo === for /f tokens and empty fields
> csv.txt echo id,name,city
>> csv.txt echo 1,Ann,Leeds
>> csv.txt echo 2,,York
>> csv.txt echo 3,"Smith, Bo",Hull
for /f "skip=1 tokens=1-3 delims=," %%a in (csv.txt) do echo id=%%a name=%%b city=%%c
echo === spaces as delimiters collapse
echo   a    b   c > sp.txt
for /f "tokens=1-3" %%a in (sp.txt) do echo [%%a][%%b][%%c]
echo === tokens=1,*
echo ERROR 42 disk is full > log.txt
for /f "tokens=1,*" %%a in (log.txt) do echo first=[%%a] rest=[%%b]
echo === a path with spaces needs usebackq
> "My Files\list.txt" echo inside the file
for /f "delims=" %%a in ("My Files\list.txt") do echo without usebackq: [%%a]
for /f "usebackq delims=" %%a in ("My Files\list.txt") do echo with usebackq: [%%a]
echo === a missing file
for /f "delims=" %%a in (nothere.txt) do echo %%a
echo errorlevel %errorlevel%
echo === a pipe inside the command must be escaped
for /f "delims=" %%a in ('dir /b data ^| findstr txt') do echo [%%a]
echo === exit code of a failing command inside for /f
for /f "delims=" %%a in ('cmd /c exit 7') do echo never
echo errorlevel after: %errorlevel%
echo === robocopy output and exit codes
robocopy data backup *.txt /njh /njs /ndl /np
echo first run errorlevel %errorlevel%
robocopy data backup *.txt >nul
echo second run, nothing new: %errorlevel%
> backup\extra.txt echo x
robocopy data backup *.txt >nul
echo with an extra file in the destination: %errorlevel%
robocopy nosuchfolder backup >nul
echo missing source: %errorlevel%
echo === choice with piped input
echo N| choice /c YN /m "Continue"
echo errorlevel %errorlevel%
echo Y| choice /c YN /m "Continue"
echo errorlevel %errorlevel%
echo === falling through a label
> fall.cmd echo @echo off
>> fall.cmd echo call :hello
>> fall.cmd echo :hello
>> fall.cmd echo echo hello
cmd /d /c .\fall.cmd
echo === goto a missing label
> miss.cmd echo @echo off
>> miss.cmd echo goto nowhere
>> miss.cmd echo echo not reached
cmd /d /c .\miss.cmd
echo errorlevel %errorlevel%
popd
rmdir /s /q "%work%"
if exist "%work%" (echo cleanup FAILED) else (echo cleaned up)
