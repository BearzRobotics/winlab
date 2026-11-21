@echo off
setlocal
for /f %%a in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "ts=%%a"
echo ts-length=%ts:~15,1%x len-ok
> app.ini echo name=Demo App
>> app.ini echo path=C:\Program Files\Demo
>> app.ini echo ; comment
>> app.ini echo mode = fast
for /f "usebackq eol=; tokens=1,* delims==" %%k in ("app.ini") do echo key=[%%k] value=[%%l]
echo --- dry run pattern
set "RUN=echo WOULD RUN:"
%RUN% del "C:\important\*.*"
