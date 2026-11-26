# Battery 5 for foundations.cmd-advanced: the lesson's input-validation loop, taken from the Markdown as
# printed, fed answers (including hostile ones) through standard input. Writes only in a new %TEMP% folder.
#   pwsh -NoProfile -File tests\verification\cmd\adv5.ps1
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path (Split-Path $PSScriptRoot))
$md = [IO.File]::ReadAllText("$repo\course\foundations\cmd-advanced.md").Replace("`r`n", "`n")
$section = $md.Substring($md.IndexOf('## Menus and input validation'))
$loop = [regex]::Match($section, '(?s)\n```[a-z]*\n(.*?:ask.*?)\n```').Groups[1].Value
if (-not $loop) { throw 'could not extract the loop' }
$work = Join-Path $env:TEMP "wlv$PID"; New-Item -ItemType Directory $work | Out-Null
try {
    $script = "@echo off`r`nsetlocal EnableDelayedExpansion`r`n" + $loop.Replace("`n", "`r`n") + "`r`necho ACCEPTED [!x!]`r`n"
    [IO.File]::WriteAllText("$work\ask.cmd", $script, [Text.Encoding]::ASCII)
    foreach ($bad in '5&echo.> pwned.txt', '5>made.txt', '5|echo x> piped.txt', 'abc', '4a2', '12 34', '"7"', '1=1', '!x!', '%TEMP%') {
        # each run gets the hostile answer, then a good one, so the loop can end
        [IO.File]::WriteAllText("$work\in.txt", "$bad`r`n42`r`n", [Text.Encoding]::ASCII)
        Push-Location $work
        try { cmd.exe /d /c ".\ask.cmd < in.txt > out.txt 2>&1" ; $o = (Get-Content out.txt) -join ' / ' } finally { Pop-Location }
        "{0,-22} -> {1}" -f $bad, $o
    }
    "files created besides the script's own: $(@(Get-ChildItem $work -File | Where-Object Name -notin 'ask.cmd','in.txt','out.txt').Count)"
}
finally { Remove-Item $work -Recurse -Force; "cleaned up: $(-not (Test-Path $work))" }
