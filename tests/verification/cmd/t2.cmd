@echo off
cd /d C:\
cd C:\Program Files
echo cd-unquoted-errorlevel=%ERRORLEVEL% now=%CD%
cd /d C:\
dir C:\Program Files >nul 2>&1
echo dir-unquoted-errorlevel=%ERRORLEVEL%
where dir 2>&1
echo where-dir-errorlevel=%ERRORLEVEL%
cd /d C:\
D: 2>nul
if exist D:\ (cd D:\Windows 2>nul & echo drive-now=%CD%) else echo no-D-drive
