@echo off
setlocal EnableDelayedExpansion
for %%v in (42 4x 7) do (
  set "x=%%v"
  echo(!x!| findstr /r "^[0-9][0-9]*$" >nul && (echo !x! ok) || (echo !x! digits-only)
)
