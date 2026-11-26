# Battery for foundations.ps-modules-and-remoting: reading Get-Job and Get-Module. Local jobs only.
function Show($x) { ($x | Out-String -Width 110).Trim("`r", "`n") }
"PowerShell $($PSVersionTable.PSVersion)"
$ok = Start-Job -Name works { Start-Sleep 1; 'result' }
$bad = Start-Job -Name fails { Get-Item C:\nope-nope -ErrorAction Stop }
$long = Start-Job -Name busy { Start-Sleep 60 }
Wait-Job $ok, $bad | Out-Null
'=== Get-Job'
Show (Get-Job)
'=== HasMoreData before and after Receive-Job'
"before: $($ok.HasMoreData)"; $r1 = Receive-Job $ok; "first receive: $r1   HasMoreData now: $($ok.HasMoreData)"; $r2 = Receive-Job $ok; "second receive: [$r2]"
'=== a failed job'
"state: $($bad.State)"; try { Receive-Job $bad -ErrorAction Stop } catch { "error on receive: $($_.Exception.Message)" }
"reason: $($bad.ChildJobs[0].JobStateInfo.Reason.Message)"
Stop-Job $long; "stopped job state: $($long.State)"
Get-Job | Remove-Job
"jobs left: $(@(Get-Job).Count)"
'=== Get-Module -ListAvailable (one built-in module)'
Show (Get-Module -ListAvailable Microsoft.PowerShell.Management | Format-Table ModuleType, Version, Name, @{n = 'ExportedCommands'; e = { @($_.ExportedCommands.Keys).Count } } -AutoSize)
