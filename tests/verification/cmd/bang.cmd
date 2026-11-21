@echo off
setlocal EnableDelayedExpansion
set "a=Wow^!"
echo a=[!a!]
set "b=Wow^^!"
echo b=[!b!]
set "c=Wow^^^!"
echo c=[!c!]
setlocal DisableDelayedExpansion
set "e=Wow!"
setlocal EnableDelayedExpansion
echo e=[!e!]
echo e-pct=[%e%]
endlocal
echo e2=[%e%]
