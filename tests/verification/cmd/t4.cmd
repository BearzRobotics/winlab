@echo off
timeout /t 1 /nobreak >nul
echo timeout-el=%errorlevel%
cmd /c exit /b 9
echo cmdc-el=%errorlevel%

