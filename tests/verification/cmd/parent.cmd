@echo off
cd /d "%~dp0"
echo before
call child.cmd
echo after-call el=%errorlevel%
child.cmd
echo NOT-REACHED-after-plain-run

