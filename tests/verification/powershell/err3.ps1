# Battery for foundations.ps-errors-and-debugging: reading error messages, and which errors let a script go on.
# Writes only a temp folder it removes. Run with powershell.exe and pwsh.
$work = Join-Path $env:TEMP "wl-err-$PID"; New-Item -ItemType Directory $work | Out-Null
$exe = (Get-Process -Id $PID).Path
function Section($t) { "`n=== $t" }
function Run-Script([string]$body) {
    $f = "$work\s.ps1"; Set-Content $f $body
    & $exe -NoProfile -ExecutionPolicy Bypass -File $f 2>&1 | ForEach-Object { ("$_").Replace($work, '<work>') }
    "exit code: $LASTEXITCODE"
}
try {
    "PowerShell $($PSVersionTable.PSVersion)"
    Section 'how an error is printed'
    Set-Content "$work\show.ps1" "`$name = 'C:\nope'`r`nGet-Item `$name"
    & $exe -NoProfile -ExecutionPolicy Bypass -File "$work\show.ps1" 2>&1 | ForEach-Object { ("$_").Replace($work, '<work>') }
    Section 'after a cmdlet non-terminating error, does the script continue?'
    Run-Script "Get-Item C:\nope`r`n'next line ran'"
    Section 'after a .NET method / conversion error (statement-terminating)'
    Run-Script "[int]'abc'`r`n'next line ran'"
    Run-Script "(1/0)`r`n'next line ran'"
    Run-Script "[IO.File]::ReadAllText('C:\nope.txt')`r`n'next line ran'"
    Section 'after throw (script-terminating)'
    Run-Script "throw 'stop here'`r`n'next line ran'"
    Section 'after -ErrorAction Stop'
    Run-Script "Get-Item C:\nope -ErrorAction Stop`r`n'next line ran'"
    Section 'after an unknown command'
    Run-Script "nosuchcommand`r`n'next line ran'"
    Section 'with ErrorActionPreference Stop, the .NET error'
    Run-Script "`$ErrorActionPreference = 'Stop'`r`n[int]'abc'`r`n'next line ran'"
    Section 'statement-terminating inside try is caught'
    try { [int]'abc' } catch { "caught: $($_.Exception.GetType().Name)" }
    Section 'what a failing step leaves behind'
    Run-Script "`$total = [int]'abc'`r`n`"total is [`$total]`""
}
finally { Remove-Item $work -Recurse -Force }
