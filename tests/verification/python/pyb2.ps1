# Battery for foundations.python-basics: how Python is started from Windows shells. Writes only to a temp folder.
# Run with PowerShell 7:  pwsh -NoProfile -File tests\verification\python\pyb2.ps1
$ErrorActionPreference = 'Continue'
$work = Join-Path $env:TEMP "wl-pyb2-$PID"
New-Item -ItemType Directory -Path $work | Out-Null
Push-Location $work
try {
    '=== what each name is'
    foreach ($name in 'python', 'python3', 'py') {
        $all = @(Get-Command $name -All -ErrorAction SilentlyContinue)
        "$name : $(($all.Source) -join ' ; ')"
    }
    '=== versions'
    python --version
    python3 --version
    py --version
    '=== py list'
    py list
    '=== sys.executable through each name'
    python -c 'import sys; print(sys.executable)'
    py -c 'import sys; print(sys.executable)'

    Set-Content -Path hello.py -Value 'import sys', 'print("args:", sys.argv[1:])', 'sys.exit(3)'
    '=== python hello.py'
    python hello.py a 'b c'
    "LASTEXITCODE=$LASTEXITCODE  ?=$?"
    '=== .\hello.py (file association)'
    .\hello.py a 'b c'
    "LASTEXITCODE=$LASTEXITCODE"
    '=== association'
    cmd.exe /d /c 'assoc .py'
    '=== bare name from current folder'
    try { hello.py } catch { $_.Exception.Message.Split("`n")[0] }

    $code = 'print("hi there")'
    '=== quoting: PowerShell 7'
    pwsh.exe -NoProfile -Command "python -c 'print(`"hi there`")'"
    "exit $LASTEXITCODE"
    Set-Content -Path q.ps1 -Value 'python -c ''print("hi there")''', '"exit $LASTEXITCODE"'
    '=== quoting: Windows PowerShell 5.1 running q.ps1'
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File q.ps1
    '=== quoting: PowerShell 7 running q.ps1'
    pwsh.exe -NoProfile -File q.ps1
    Set-Content -Path q.cmd -Value '@echo off', 'python -c "print(''hi there'')"', 'echo errorlevel %errorlevel%', 'python hello.py', 'echo errorlevel %errorlevel%'
    '=== cmd'
    cmd.exe /d /c .\q.cmd  # .\ because a tool may set NoDefaultCurrentDirectoryInExePath

    '=== missing script'
    python nosuch.py
    "LASTEXITCODE=$LASTEXITCODE"
}
finally {
    Pop-Location
    Remove-Item -Recurse -Force $work
}
