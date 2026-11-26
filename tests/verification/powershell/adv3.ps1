# Battery for foundations.ps-advanced: how Measure-Command behaves, and the practice Base64 string (decoded only).
"PowerShell $($PSVersionTable.PSVersion)"
'=== the object'
(Measure-Command { Start-Sleep -Milliseconds 250 } | Format-List Seconds, Milliseconds, TotalSeconds, TotalMilliseconds | Out-String).Trim()
'=== output is swallowed'
$t = Measure-Command { 'you will not see me'; Write-Output 'nor me' }; "returned type: $($t.GetType().Name)"
'=== Out-Default shows it'
$null = Measure-Command { 'seen through Out-Default' | Out-Default }
'=== same scope: the block changes your variables'
$n = 1; $null = Measure-Command { $n = 99 }; "n afterwards: $n"
'=== five runs of the same block'
$block = { $r = foreach ($i in 1..200000) { $i } }
(1..5 | ForEach-Object { [int](Measure-Command $block).TotalMilliseconds }) -join ' ms, '
'=== .Milliseconds is only the part'
$s = [timespan]::FromMilliseconds(2350); "Milliseconds=$($s.Milliseconds)  TotalMilliseconds=$($s.TotalMilliseconds)"
'=== the practice string, decoded and not run'
[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('JABjAD0ATgBlAHcALQBPAGIAagBlAGMAdAAgAE4AZQB0AC4AVwBlAGIAQwBsAGkAZQBuAHQA'))
