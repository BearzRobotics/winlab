# Battery 2 for foundations.cmd-batch-files: runs the lesson's "A complete script" exactly as printed, taken
# from the Markdown, against awkward folder names. Writes only inside a new folder under %TEMP%.
#   pwsh -NoProfile -File tests\verification\cmd\batch2.ps1
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path (Split-Path $PSScriptRoot))
$md = [IO.File]::ReadAllText("$repo\course\foundations\cmd-batch-files.md").Replace("`r`n", "`n")
$section = $md.Substring($md.IndexOf('## A complete script'))
$code = [regex]::Match($section, '(?s)\n```[a-z]*\n(.*?)\n```').Groups[1].Value
if (-not $code.Contains('robocopy')) { throw 'could not extract the script from the lesson' }
$work = Join-Path $env:TEMP "wlb$PID"
New-Item -ItemType Directory "$work\dest" | Out-Null
try {
    [IO.File]::WriteAllText("$work\backup.cmd", $code.Replace("`n", "`r`n") + "`r`n", [Text.Encoding]::ASCII)
    function Run([string]$label, [string]$line) {
        "=== $label"
        [IO.File]::WriteAllText("$work\go.cmd", "@echo off`r`ncall `"$work\backup.cmd`" $line`r`necho exit code %errorlevel%`r`n", [Text.Encoding]::ASCII)
        Push-Location $work
        try { cmd.exe /d /c ".\go.cmd > out.txt 2>&1"; Get-Content out.txt | ForEach-Object { "  " + $_.Replace($work, '<work>') } } finally { Pop-Location }
    }
    foreach ($name in 'plain', 'with space', 'amp & sand', 'old (x86)', 'wow! a!b', 'hat ^ it') { New-Item -ItemType Directory "$work\src\$name" | Out-Null; Set-Content "$work\src\$name\f.txt" 'data' }
    Run 'no arguments' ''
    Run 'not a folder' "`"$work\src\missing`" `"$work\dest`""
    Run 'plain folder' "`"$work\src\plain`" `"$work\dest`""
    Start-Sleep 1
    Run 'folder with a space' "`"$work\src\with space`" `"$work\dest`""
    Start-Sleep 1
    Run 'folder with &' "`"$work\src\amp & sand`" `"$work\dest`""
    Start-Sleep 1
    Run 'folder with parentheses' "`"$work\src\old (x86)`" `"$work\dest`""
    Start-Sleep 1
    Run 'folder with !' "`"$work\src\wow! a!b`" `"$work\dest`""
    Start-Sleep 1
    Run 'folder with ^' "`"$work\src\hat ^ it`" `"$work\dest`""
    '=== folder with ^, started without CALL'
    [IO.File]::WriteAllText("$work\go2.cmd", "@echo off`r`n`"$work\backup.cmd`" `"$work\src\hat ^ it`" `"$work\dest`"`r`n", [Text.Encoding]::ASCII)
    Push-Location $work; try { cmd.exe /d /c ".\go2.cmd > out.txt 2>&1"; Get-Content out.txt | ForEach-Object { "  " + $_.Replace($work, '<work>') } } finally { Pop-Location }
    '=== help, started with cmd /c (CALL itself answers /? before the script can)'
    Push-Location $work; try { cmd.exe /d /c ".\backup.cmd /? > out.txt 2>&1"; Get-Content out.txt | ForEach-Object { "  $_" }; "  exit code $LASTEXITCODE" } finally { Pop-Location }
    Run 'missing folder with parentheses' "`"$work\src\gone (old)`" `"$work\dest`""
    '=== the log'
    if (Test-Path "$work\dest\backup.log") { Get-Content "$work\dest\backup.log" | ForEach-Object { "  " + $_.Replace($work, '<work>') } }
    '=== backups made'; Get-ChildItem "$work\dest" -Directory | ForEach-Object { "  $($_.Name): $((Get-ChildItem $_.FullName -File).Name -join ',')" }

    '=== a :log subroutine that echoes its argument, with special characters'
    [IO.File]::WriteAllText("$work\log.cmd", (@'
@echo off
set "LOG=%~dp0t.log"
if exist "%LOG%" del "%LOG%"
call :log "plain message"
call :log "saved A & B"
call :log "size > 5"
echo -- log holds:
type "%LOG%"
exit /b 0
:log
>> "%LOG%" echo %~1
exit /b 0
'@).Replace("`n", "`r`n"), [Text.Encoding]::ASCII)
    Push-Location $work; try { cmd.exe /d /c ".\log.cmd > out.txt 2>&1"; Get-Content out.txt | ForEach-Object { "  $_" }; "  stray file named 5 exists: $(Test-Path .\5)" } finally { Pop-Location }

    '=== the same with delayed expansion in the subroutine'
    [IO.File]::WriteAllText("$work\log2.cmd", (@'
@echo off
set "LOG=%~dp0t2.log"
call :log "saved A & B"
call :log "size > 5"
echo -- log holds:
type "%LOG%"
exit /b 0
:log
setlocal enabledelayedexpansion
set "msg=%~1"
>> "%LOG%" echo(!msg!
endlocal
exit /b 0
'@).Replace("`n", "`r`n"), [Text.Encoding]::ASCII)
    Push-Location $work; try { cmd.exe /d /c ".\log2.cmd > out.txt 2>&1"; Get-Content out.txt | ForEach-Object { "  $_" } } finally { Pop-Location }
}
finally { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue; "cleaned up: $(-not (Test-Path $work))" }
