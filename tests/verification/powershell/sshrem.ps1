$vm  = Join-Path $env:LOCALAPPDATA 'WinLab\vms\winlab-lab-c'
$key = Join-Path $vm 'id_ed25519'
$opts = @{ StrictHostKeyChecking = 'no'; UserKnownHostsFile = (Join-Path $vm 'known_hosts'); LogLevel = 'ERROR'; BatchMode = 'yes' }
'local edition: ' + $PSVersionTable.PSEdition + ' ' + $PSVersionTable.PSVersion
'--- New-PSSession over SSH (HostName)'
$s = New-PSSession -HostName 127.0.0.1 -Port 44024 -UserName Administrator -KeyFilePath $key -Options $opts -ErrorAction Stop
'session: Name=' + $s.Name + ' Transport=' + $s.Transport + ' State=' + $s.State + ' ComputerName=' + $s.ComputerName
'--- run a command remotely'
Invoke-Command -Session $s -ScriptBlock { 'remote: ' + $env:COMPUTERNAME + ' as ' + [Environment]::UserName + ' PS ' + $PSVersionTable.PSVersion + ' (' + $PSVersionTable.PSEdition + ')' }
'--- $using: and state'
$limit = 7
Invoke-Command -Session $s -ScriptBlock { $x = "kept"; "using=[$using:limit]" }
'state kept: ' + (Invoke-Command -Session $s -ScriptBlock { $x })
'--- serialization over SSH'
$r = Invoke-Command -Session $s -ScriptBlock { Get-Service sshd }
'type: ' + $r.GetType().FullName + '; Status=' + $r.Status + '; PSComputerName=' + $r.PSComputerName + '; Stop() method present: ' + [bool]($r | Get-Member -Name Stop -MemberType Method)
'--- elevated on the target? (Server 2022, Administrator over SSH)'
Invoke-Command -Session $s -ScriptBlock { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
'--- Windows-only cmdlets work remotely even though we run them from 7: Get-Service count'
(Invoke-Command -Session $s -ScriptBlock { (Get-Service).Count })
'--- Invoke-Command -HostName (one-shot, no session object)'
Invoke-Command -HostName 127.0.0.1 -Port 44024 -UserName Administrator -KeyFilePath $key -Options $opts -ScriptBlock { 'one-shot on ' + $env:COMPUTERNAME }
'--- error handling over SSH'
try { Invoke-Command -Session $s -ScriptBlock { Get-Item C:\nope -ErrorAction Stop } -ErrorAction Stop } catch { 'caught: ' + $_.Exception.GetType().Name + ' - ' + ($_.Exception.Message -split "`n")[0] }
'--- copy over the session'
Set-Content "$env:TEMP\wl-ssh-send.txt" 'via ssh'
Copy-Item "$env:TEMP\wl-ssh-send.txt" -Destination 'C:\Windows\Temp\wl-ssh-recv.txt' -ToSession $s
Invoke-Command -Session $s -ScriptBlock { 'remote file: ' + (Get-Content C:\Windows\Temp\wl-ssh-recv.txt); Remove-Item C:\Windows\Temp\wl-ssh-recv.txt }
Remove-Item "$env:TEMP\wl-ssh-send.txt"
Remove-PSSession $s
'session removed; remaining: ' + @(Get-PSSession).Count
