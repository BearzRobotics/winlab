@echo off
goto :two
:one
echo one
goto :eof
:two
echo two
call :sub
goto :eof
:sub
echo in-sub
exit /b 0
