# Security lesson battery for Windows: baseline check, planted weaknesses, then cleanup (run elevated in the Server VM; needs C:\Windows\Temp\wl-winbaseline.ps1)
$ErrorActionPreference = 'Continue'
$B = 'C:\Windows\Temp\wl-winbaseline.ps1'
"### $((Get-CimInstance Win32_OperatingSystem).Caption)  build $([Environment]::OSVersion.Version)  PowerShell $($PSVersionTable.PSVersion)"
function Run-Baseline { powershell -NoProfile -ExecutionPolicy Bypass -File $B; "exit status $LASTEXITCODE" }

"### 1. the baseline on the fresh server"
Run-Baseline

"### 2. plant eight weaknesses"
$pw = ConvertTo-SecureString 'Lab-pass-1!' -AsPlainText -Force
New-LocalUser -Name wlintruder -Password $pw | Out-Null; Add-LocalGroupMember -Group Administrators -Member wlintruder
Enable-LocalUser -Name Guest
Set-NetFirewallProfile -Profile Public -Enabled False
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' fDenyTSConnections 0
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' UserAuthentication 0
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name wlupdate -Value 'C:\Users\Public\wlupdate.exe'
schtasks /create /tn wlsync /tr 'C:\Users\Public\wlsync.exe' /sc daily /st 03:00 /ru SYSTEM /f | Out-Null
sc.exe create wlsvc binPath= 'C:\Users\Public\wlsvc.exe' start= auto | Out-Null
try { Set-SmbServerConfiguration -EnableSMB1Protocol $true -Force -ErrorAction Stop; 'SMB1 enable: ok' } catch { 'SMB1 enable: ' + $_.Exception.Message.Trim() }
try { Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction Stop; 'Defender real-time off: ok' } catch { 'Defender real-time off: ' + $_.Exception.Message.Trim() }
$l = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Any, 4444)
$job = Start-Job { $l = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Any, 4444); $l.Start(); Start-Sleep 120 }
Start-Sleep 3

"### 3. the baseline again"
Run-Baseline

"### 4. undo everything and check again"
Stop-Job $job; Remove-Job $job
Remove-LocalUser wlintruder; Disable-LocalUser Guest
Set-NetFirewallProfile -Profile Public -Enabled True
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' fDenyTSConnections 1
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' UserAuthentication 1
Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name wlupdate
schtasks /delete /tn wlsync /f | Out-Null; sc.exe delete wlsvc | Out-Null
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue
Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
Start-Sleep 2
Run-Baseline

"### 5. parameters and a bad parameter"
powershell -NoProfile -ExecutionPolicy Bypass -File $B -MinPasswordLength 0 -MaxPatchAgeDays 5000 | Select-String 'password length|newest update|failed'
powershell -NoProfile -ExecutionPolicy Bypass -File $B -MinPasswordLength abc 2>&1 | Select-Object -First 2
