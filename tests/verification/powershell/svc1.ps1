# Battery for windows-admin.services-and-startup. THROWAWAY VM ONLY, elevated: makes services and tasks
# named wl-*, kills the Spooler process once, and removes what it made.
$ErrorActionPreference = 'Continue'
function Section($t) { "`n=== $t" }
function Show($x) { ($x | Out-String -Width 160).Trim("`r", "`n") }
function Scm($since) {
    Start-Sleep 2
    Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Service Control Manager'; StartTime = $since } -ErrorAction SilentlyContinue |
        Sort-Object RecordId | ForEach-Object { "event $($_.Id): $(($_.Message -replace '\s+', ' ').Trim())" }
}
function TryStart($name) { try { Start-Service $name -ErrorAction Stop; 'started' } catch { "Start-Service: $($_.Exception.Message) / $($_.Exception.InnerException.Message)" }; sc.exe start $name }
"PowerShell $($PSVersionTable.PSVersion)  $((Get-CimInstance Win32_OperatingSystem).Caption)"

Section 'Spooler as it is'
Show (Get-Service Spooler | Format-List Name, DisplayName, Status, StartType)
Show (Get-CimInstance Win32_Service -Filter "Name='Spooler'" | Format-List Name, StartMode, DelayedAutoStart, StartName, PathName, State, ProcessId)
sc.exe qc Spooler
sc.exe query Spooler
sc.exe qfailure Spooler
Section 'automatic but stopped'
Show (Get-Service | Where-Object { $_.Status -eq 'Stopped' -and $_.StartType -eq 'Automatic' } | Format-Table Name, DisplayName, Status, StartType -AutoSize)
Show (Get-CimInstance Win32_Service -Filter "StartMode='Auto' AND State<>'Running'" | Format-Table Name, ExitCode, DelayedAutoStart -AutoSize)

Section 'running and disabled at once'
Set-Service Spooler -StartupType Disabled
Show (Get-Service Spooler | Format-List Status, StartType)
Stop-Service Spooler
try { Start-Service Spooler -ErrorAction Stop } catch { "Start-Service: $($_.Exception.Message) / $($_.Exception.InnerException.Message)" }
sc.exe start Spooler
Set-Service Spooler -StartupType Automatic; Start-Service Spooler

Section 'delayed start as Get-Service shows it'
sc.exe config Spooler start= delayed-auto
Show (Get-Service Spooler | Format-List StartType)
Show (Get-CimInstance Win32_Service -Filter "Name='Spooler'" | Format-List StartMode, DelayedAutoStart)
sc.exe config Spooler start= auto
Section 'without the space'
sc.exe config Spooler start=auto
"exit code: $LASTEXITCODE"

Section 'the process dies: recovery configured'
$t = Get-Date
Stop-Process -Id (Get-CimInstance Win32_Service -Filter "Name='Spooler'").ProcessId -Force
Start-Sleep 9
"status 9 s later: $((Get-Service Spooler).Status)"
Scm $t

Section 'fault 1: program missing'
New-Service -Name wl-missing -BinaryPathName 'C:\wl\nothere.exe' -StartupType Manual | Out-Null
$t = Get-Date; TryStart wl-missing; Scm $t
Section 'fault 2: a dependency is disabled'
New-Service -Name wl-base -BinaryPathName 'C:\wl\base.exe' -StartupType Disabled | Out-Null
New-Service -Name wl-child -BinaryPathName 'C:\Windows\System32\cmd.exe' -StartupType Manual -DependsOn wl-base | Out-Null
$t = Get-Date; TryStart wl-child; Scm $t
Section 'fault 3: wrong account password'
net.exe user wlsvcuser 'Wl-Battery-7q!x2' /add | Out-Null
sc.exe create wl-account binPath= C:\Windows\System32\cmd.exe obj= .\wlsvcuser password= 'not-the-password'
$t = Get-Date; TryStart wl-account; Scm $t
Section 'fault 4: a program that is not a service'
New-Service -Name wl-notsvc -BinaryPathName 'C:\Windows\System32\cmd.exe /c ping -n 60 127.0.0.1' -StartupType Manual | Out-Null
$t = Get-Date; $sw = [Diagnostics.Stopwatch]::StartNew(); TryStart wl-notsvc; "after $([int]$sw.Elapsed.TotalSeconds) s"; Scm $t
Section 'new service events were logged as'
Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 7045 } -MaxEvents 1 | ForEach-Object { ($_.Message -replace "`r", '') }
Section 'dependents'
Show (Get-Service RpcSs -DependentServices | Where-Object Status -eq 'Running' | Select-Object -First 5 | Format-Table Name, Status -AutoSize)
Show (Get-Service Spooler -RequiredServices | Format-Table Name, Status -AutoSize)
foreach ($n in 'wl-missing', 'wl-child', 'wl-base', 'wl-account', 'wl-notsvc') { sc.exe delete $n | Out-Null }
net.exe user wlsvcuser /delete | Out-Null
"services left: $(@(Get-Service wl-* -ErrorAction SilentlyContinue).Count)"

New-Item -ItemType Directory C:\wl -Force | Out-Null
Set-Content C:\wl\job.ps1 @'
"user=$([Environment]::UserName) cwd=$((Get-Location).Path) temp=$env:TEMP" | Set-Content C:\wl\context.txt
Get-Content input.txt
'@
Set-Content C:\wl\input.txt 'data'
Set-Content C:\wl\fail.ps1 'exit 3'
function RunTask($name, $exe, $arg, $dir) {
    $a = if ($dir) { New-ScheduledTaskAction -Execute $exe -Argument $arg -WorkingDirectory $dir } else { New-ScheduledTaskAction -Execute $exe -Argument $arg }
    Register-ScheduledTask -TaskName $name -Action $a -User SYSTEM -Force | Out-Null
    Start-ScheduledTask -TaskName $name
    for ($i = 0; $i -lt 40; $i++) { Start-Sleep 1; if ((Get-ScheduledTask -TaskName $name).State -ne 'Running') { break } }
    $r = (Get-ScheduledTask -TaskName $name | Get-ScheduledTaskInfo).LastTaskResult
    "$name : LastTaskResult $r (0x{0:X})" -f $r
}
Section 'tasks: results'
$ps = 'powershell.exe'; $base = '-NoProfile -ExecutionPolicy Bypass -File'
RunTask wl-relative $ps "$base C:\wl\job.ps1" $null
Get-Content C:\wl\context.txt
RunTask wl-exit3 $ps "$base C:\wl\fail.ps1" $null
RunTask wl-nofile $ps "$base C:\wl\no-such.ps1" $null
RunTask wl-noprogram 'C:\wl\nothere.exe' ' ' $null
Section 'what the relative script really did'
Set-Content C:\wl\job2.ps1 'try { Get-Content input.txt -ErrorAction Stop | Set-Content C:\wl\out.txt } catch { $_.Exception.Message | Set-Content C:\wl\out.txt }'
RunTask wl-rel2 $ps "$base C:\wl\job2.ps1" $null; Get-Content C:\wl\out.txt
RunTask wl-rel3 $ps "$base C:\wl\job2.ps1" 'C:\wl'; Get-Content C:\wl\out.txt
Section 'a task as Get-ScheduledTaskInfo shows it'
Show (Get-ScheduledTask -TaskName wl-exit3 | Get-ScheduledTaskInfo | Format-List TaskName, LastRunTime, LastTaskResult, NextRunTime, NumberOfMissedRuns)
Section 'running now'
$a = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c ping -n 30 127.0.0.1'
Register-ScheduledTask -TaskName wl-long -Action $a -User SYSTEM -Force | Out-Null; Start-ScheduledTask wl-long; Start-Sleep 3
"state=$((Get-ScheduledTask wl-long).State) result=$((Get-ScheduledTask wl-long | Get-ScheduledTaskInfo).LastTaskResult)"
Stop-ScheduledTask wl-long
Section 'disabled task started'
Disable-ScheduledTask wl-long | Out-Null
try { Start-ScheduledTask wl-long -ErrorAction Stop; 'no error' } catch { "Start-ScheduledTask: $($_.Exception.Message)" }
Section 'task history log enabled?'
wevtutil.exe gl Microsoft-Windows-TaskScheduler/Operational | Select-String 'enabled'
Get-ScheduledTask -TaskName wl-* | Unregister-ScheduledTask -Confirm:$false
Remove-Item C:\wl -Recurse -Force
"tasks left: $(@(Get-ScheduledTask -TaskName wl-* -ErrorAction SilentlyContinue).Count)"
