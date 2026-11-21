# Battery 2 for ps-system-admin-scripting: ELEVATED, run in the lab VM only (restore the snapshot afterwards).
$ErrorActionPreference = 'Continue'
"PSVersion: $($PSVersionTable.PSVersion)"
"Elevated: $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"

'--- Service control with -WhatIf'
Stop-Service -Name Spooler -WhatIf
Set-Service -Name Spooler -StartupType Disabled -WhatIf
'-- real: stop, state, start'
Stop-Service -Name Spooler
(Get-Service Spooler).Status
Start-Service -Name Spooler
(Get-Service Spooler).Status
'-- Start-Service on a running service: silent?'
Start-Service -Name Spooler; "rc ok"
'-- StartType change and CIM view'
Set-Service -Name Spooler -StartupType Manual
(Get-Service Spooler).StartType
(Get-CimInstance Win32_Service -Filter "Name='Spooler'").StartMode
Set-Service -Name Spooler -StartupType Automatic
'-- Stop with dependents'
try { Stop-Service -Name RPCSS -ErrorAction Stop } catch { $_.Exception.Message }
'-- Restart-Service'
Restart-Service -Name Spooler -PassThru | Select-Object Name, Status
'-- Get-Service -ComputerName in 5.1 only? (no remoting needed on local)'
(Get-Command Get-Service).Parameters.Keys -contains 'ComputerName'
'-- CIM Invoke-CimMethod ChangeStartMode'
Invoke-CimMethod -Query "SELECT * FROM Win32_Service WHERE Name='Spooler'" -MethodName ChangeStartMode -Arguments @{ StartMode = 'Manual' } | Select-Object ReturnValue
(Get-Service Spooler).StartType
Set-Service Spooler -StartupType Automatic

'--- Service recovery options (sc.exe)'
sc.exe qfailure Spooler
sc.exe failure Spooler reset= 86400 actions= restart/60000/restart/60000// | Out-Null
sc.exe qfailure Spooler

'--- Registry HKLM write + type behaviour'
$k = 'HKLM:\SOFTWARE\WinLabTest'
New-Item -Path $k -Force | Out-Null
New-ItemProperty -Path $k -Name Enabled -Value 1 -PropertyType DWord | Out-Null
Get-ItemProperty -Path $k | Select-Object Enabled | Format-List
'-- 64-bit vs WOW6432Node view from a 32-bit PowerShell'
[Environment]::Is64BitProcess
Test-Path 'HKLM:\SOFTWARE\WOW6432Node'
'-- Registry export/import with reg.exe'
reg.exe export 'HKLM\SOFTWARE\WinLabTest' "$env:TEMP\wl.reg" /y
Get-Content "$env:TEMP\wl.reg"
Remove-Item -Path $k -Recurse
Test-Path $k
'-- Load Default user hive? skip. -WhatIf on Remove-Item'
New-Item -Path $k -Force | Out-Null
Remove-Item -Path $k -Recurse -WhatIf
Remove-Item -Path $k -Recurse -Confirm:$false
Test-Path $k

'--- Event log: write a custom event'
New-EventLog -LogName Application -Source WinLabTool -ErrorAction SilentlyContinue
Write-EventLog -LogName Application -Source WinLabTool -EventId 4001 -EntryType Warning -Message 'WinLab test event'
Get-WinEvent -FilterHashtable @{ LogName='Application'; ProviderName='WinLabTool' } -MaxEvents 1 | Select-Object Id, LevelDisplayName, Message | Format-List
'-- remove the source'
Remove-EventLog -Source WinLabTool
'-- Get-WinEvent from Security log needs elevation'
Get-WinEvent -LogName Security -MaxEvents 1 | Select-Object Id, ProviderName | Format-List
'-- Event XML'
$ev = Get-WinEvent -FilterHashtable @{ LogName='System'; Id=7036 } -MaxEvents 1
([xml]$ev.ToXml()).Event.EventData.Data | ForEach-Object { "$($_.Name)=$($_.'#text')" }
'-- Limit-EventLog / wevtutil size'
wevtutil.exe gl Application | Select-Object -First 8

'--- Scheduled task lifecycle'
$action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -Command "Get-Date | Out-File C:\wl-task.txt"'
$trigger = New-ScheduledTaskTrigger -Daily -At 3am
$princ   = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
$set     = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName WinLabDemo -Action $action -Trigger $trigger -Principal $princ -Settings $set | Select-Object TaskName, State
Get-ScheduledTask -TaskName WinLabDemo | Select-Object TaskName, State | Format-Table -AutoSize
'-- registering again without -Force'
try { Register-ScheduledTask -TaskName WinLabDemo -Action $action -Trigger $trigger -ErrorAction Stop } catch { $_.Exception.Message }
Start-ScheduledTask -TaskName WinLabDemo
Start-Sleep -Seconds 6
Get-ScheduledTaskInfo -TaskName WinLabDemo | Select-Object LastTaskResult, LastRunTime | Format-List
Get-Content C:\wl-task.txt
(Get-ScheduledTask -TaskName WinLabDemo).Actions | Select-Object Execute, Arguments | Format-List
Disable-ScheduledTask -TaskName WinLabDemo | Select-Object State
Unregister-ScheduledTask -TaskName WinLabDemo -Confirm:$false
Get-ScheduledTask -TaskName WinLabDemo -ErrorAction SilentlyContinue
Remove-Item C:\wl-task.txt
'-- schtasks.exe view'
schtasks.exe /Query /TN '\Microsoft\Windows\Defrag\ScheduledDefrag' /FO LIST

'--- Local users and groups (5.1 module)'
Get-LocalGroupMember -Group Administrators | Select-Object Name, ObjectClass | Format-Table -AutoSize

'--- Disk and OS info through CIM, uptime'
Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Select-Object DeviceID, @{n='FreeGB';e={[math]::Round($_.FreeSpace/1GB,1)}}, @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}} | Format-Table -AutoSize
(Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime | Select-Object Days, Hours
'--- Idempotent pattern: ensure a service state'
function Set-WlServiceState {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Name, [ValidateSet('Running','Stopped')][string]$State)
    $svc = Get-Service -Name $Name -ErrorAction Stop
    if ($svc.Status -eq $State) { Write-Verbose "$Name already $State"; return 'unchanged' }
    if ($PSCmdlet.ShouldProcess($Name, "set $State")) {
        if ($State -eq 'Running') { Start-Service $Name } else { Stop-Service $Name }
        return 'changed'
    }
}
Set-WlServiceState -Name Spooler -State Running -Verbose
Set-WlServiceState -Name Spooler -State Stopped -WhatIf
Set-WlServiceState -Name Spooler -State Stopped
Set-WlServiceState -Name Spooler -State Stopped
Set-WlServiceState -Name Spooler -State Running
