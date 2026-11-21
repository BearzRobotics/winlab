# Battery 3 (elevated, lab VM): clean service control on BITS, disabled-service failure, dependents, Get-Service types.
'-- disabled service start error'
Get-Service Spooler | Select-Object Name, Status, StartType | Format-Table -AutoSize
try { Start-Service -Name Spooler -ErrorAction Stop } catch { $_.FullyQualifiedErrorId; $_.Exception.Message; $_.Exception.InnerException.Message }
'-- BITS lifecycle'
Get-Service BITS | Select-Object Status, StartType | Format-Table -AutoSize
Start-Service BITS -PassThru | Select-Object Name, Status | Format-Table -AutoSize
Stop-Service BITS -PassThru | Select-Object Name, Status | Format-Table -AutoSize
'-- Start-Service again when running'
Start-Service BITS; Start-Service BITS; (Get-Service BITS).Status
Restart-Service BITS -PassThru | Select-Object Name, Status | Format-Table -AutoSize
Stop-Service BITS
'-- Stop already stopped'
Stop-Service BITS; 'no error'
'-- ShouldProcess confirm impact: -Confirm shows prompt text? use -WhatIf and -Verbose'
Stop-Service BITS -WhatIf -Verbose
'-- Set-Service description, display name'
Set-Service BITS -Description 'WinLab test description'
(Get-CimInstance Win32_Service -Filter "Name='BITS'").Description
Set-Service BITS -Description 'Transfers files in the background using idle network bandwidth.'
'-- Get-Service pipeline: services stopped but Automatic'
Get-CimInstance Win32_Service -Filter "StartMode='Auto' AND State<>'Running'" | Select-Object Name, State, ExitCode | Format-Table -AutoSize
'-- Get-Service includes Where on StartType (5.1 has it)'
(Get-Service | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' }).Name -join ','
'-- Event log: services state changes via 7036 and 7045 install, 7040 start type'
Get-WinEvent -FilterHashtable @{ LogName='System'; Id=7036 } -MaxEvents 3 | ForEach-Object { $_.Message } 
Set-Service BITS -StartupType Manual
Get-WinEvent -FilterHashtable @{ LogName='System'; Id=7040 } -MaxEvents 1 | ForEach-Object { $_.Message }
'-- Scheduled task: a task registered w/o admin? action with -Argument quoting; trigger types'
New-ScheduledTaskTrigger -AtLogOn | Select-Object CimClass | Format-List
(New-ScheduledTaskTrigger -Once -At (Get-Date).AddHours(1) -RepetitionInterval (New-TimeSpan -Minutes 15)).Repetition | Select-Object Interval | Format-List
