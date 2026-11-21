# Battery 1 for ps-system-admin-scripting. Read-only on the host except temp folder and a HKCU test key.
# Run in 5.1 and 7:  powershell.exe -NoProfile -File sysadmin1.ps1 ; pwsh -NoProfile -File sysadmin1.ps1
$ErrorActionPreference = 'Continue'
"PSVersion: $($PSVersionTable.PSVersion)  Edition: $($PSVersionTable.PSEdition)"

'--- CIM vs WMI cmdlets'
Get-Command Get-WmiObject -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, LastBootUpTime | Format-List

'--- CIM filter is server side (WQL)'
Get-CimInstance -ClassName Win32_Service -Filter "Name = 'Spooler'" | Select-Object Name, State, StartMode, StartName
(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' | Measure-Object).Count

'--- CIM objects: Get-CimClass, Get-CimInstance -Query'
Get-CimClass -ClassName Win32_Service | Select-Object -ExpandProperty CimClassMethods | Select-Object -First 4 -ExpandProperty Name
Get-CimInstance -Query "SELECT Name, State FROM Win32_Service WHERE State = 'Running'" | Select-Object -First 2 | Format-Table -AutoSize

'--- Typed CIM date vs string'
$os = Get-CimInstance Win32_OperatingSystem
$os.LastBootUpTime.GetType().FullName
((Get-Date) - $os.LastBootUpTime).GetType().Name

'--- Registry provider'
Get-PSDrive -PSProvider Registry | Select-Object Name, Root
Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' | Select-Object ProductName, CurrentBuild, DisplayVersion | Format-List
(Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').GetType().FullName
Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuild

'--- Registry write round trip in HKCU (own key, removed after)'
$key = 'HKCU:\Software\WinLabTest'
if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse }
New-Item -Path $key | Out-Null
New-ItemProperty -Path $key -Name Count -Value 5 -PropertyType DWord | Out-Null
New-ItemProperty -Path $key -Name Label -Value 'hi' -PropertyType String | Out-Null
New-ItemProperty -Path $key -Name Multi -Value @('a','b') -PropertyType MultiString | Out-Null
(Get-Item -LiteralPath $key).GetValueKind('Count')
(Get-Item -LiteralPath $key).GetValueKind('Multi')
Set-ItemProperty -Path $key -Name Count -Value 6
(Get-ItemProperty -Path $key).Count
'-- New-ItemProperty twice (error?)'
try { New-ItemProperty -Path $key -Name Count -Value 7 -PropertyType DWord -ErrorAction Stop } catch { $_.Exception.GetType().FullName; $_.Exception.Message }
'-- Set-ItemProperty on missing name creates it, type guessed'
Set-ItemProperty -Path $key -Name Guess -Value 5
(Get-Item -LiteralPath $key).GetValueKind('Guess')
Set-ItemProperty -Path $key -Name GuessS -Value '5'
(Get-Item -LiteralPath $key).GetValueKind('GuessS')
'-- Test-Path on a value name?'
Test-Path -Path "$key\Count"
'-- Remove-ItemProperty and key'
Remove-ItemProperty -Path $key -Name Count
(Get-ItemProperty -Path $key).PSObject.Properties.Name -join ','
'-- (default) value'
Set-Item -Path $key -Value 'dflt'
(Get-ItemProperty -Path $key).'(default)'
'-- Wildcard trap: key name containing [ ]'
New-Item -Path 'HKCU:\Software\WinLabTest\a[1]' -ErrorAction SilentlyContinue | Out-Null
(Get-ChildItem -Path $key).Name
Test-Path -Path 'HKCU:\Software\WinLabTest\a[1]'
Test-Path -LiteralPath 'HKCU:\Software\WinLabTest\a[1]'
Remove-Item -LiteralPath $key -Recurse
Test-Path -LiteralPath $key

'--- Services (read-only)'
Get-Service -Name Spooler | Select-Object Name, Status, StartType, ServiceType | Format-List
(Get-Service -Name Spooler).DependentServices.Name -join ','
(Get-Service -Name Spooler).ServicesDependedOn.Name -join ','
Get-Service | Group-Object Status | Select-Object Name, Count | Format-Table -AutoSize
'-- Get-Service on missing name'
try { Get-Service -Name NoSuchSvc -ErrorAction Stop } catch { $_.FullyQualifiedErrorId }
Get-Service -Name 'Spool*' | Select-Object -ExpandProperty Name

'--- Event log (read)'
Get-WinEvent -ListLog System, Application | Select-Object LogName, RecordCount, MaximumSizeInBytes, LogMode | Format-Table -AutoSize
Get-WinEvent -LogName System -MaxEvents 3 | Select-Object TimeCreated, Id, ProviderName, LevelDisplayName | Format-Table -AutoSize
'-- FilterHashtable'
Get-WinEvent -FilterHashtable @{ LogName='System'; Id=6005,6006,6013 } -MaxEvents 3 -ErrorAction SilentlyContinue | Select-Object TimeCreated, Id | Format-Table -AutoSize
'-- no match error'
try { Get-WinEvent -FilterHashtable @{ LogName='System'; Id=99999 } -ErrorAction Stop } catch { $_.FullyQualifiedErrorId; $_.Exception.Message }
'-- Where-Object slow path timing vs FilterHashtable'
$t1 = Measure-Command { Get-WinEvent -LogName System -MaxEvents 3000 | Where-Object Id -eq 7036 | Out-Null }
$t2 = Measure-Command { Get-WinEvent -FilterHashtable @{ LogName='System'; Id=7036 } -MaxEvents 50 -ErrorAction SilentlyContinue | Out-Null }
"where-object path ms: $([int]$t1.TotalMilliseconds)   filterhashtable ms: $([int]$t2.TotalMilliseconds)"
'-- Properties/Message of an event'
$e = Get-WinEvent -FilterHashtable @{ LogName='System'; Id=7036 } -MaxEvents 1
$e.Message
$e.Properties.Count
$e.Properties[0].Value
'-- Get-EventLog exists?'
Get-Command Get-EventLog -ErrorAction SilentlyContinue | Select-Object Name, Source

'--- Scheduled tasks (read)'
Get-ScheduledTask | Group-Object State | Select-Object Name, Count | Format-Table -AutoSize
Get-ScheduledTask -TaskPath '\Microsoft\Windows\Defrag\' | Select-Object TaskName, State | Format-Table -AutoSize
Get-ScheduledTaskInfo -TaskName 'ScheduledDefrag' -TaskPath '\Microsoft\Windows\Defrag\' | Select-Object LastRunTime, LastTaskResult, NextRunTime | Format-List
