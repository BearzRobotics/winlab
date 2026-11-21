$pw = ConvertTo-SecureString $env:WLPW -AsPlainText -Force
$cred = [pscredential]::new("$env:COMPUTERNAME\Administrator", $pw)
$limit = 3
$PSSessionOption = New-PSSessionOption -OpenTimeout 20000 -OperationTimeout 30000
'--- Invoke-Command with explicit credential'
Invoke-Command -ComputerName localhost -Credential $cred -ScriptBlock { 'ran on ' + $env:COMPUTERNAME + ' as ' + [Environment]::UserName + ' (PS ' + $PSVersionTable.PSVersion + ')' }
'--- $using: and ArgumentList'
Invoke-Command -ComputerName localhost -Credential $cred -ScriptBlock { "using=[$using:limit]" }
Invoke-Command -ComputerName localhost -Credential $cred -ScriptBlock { param($a) "arg=[$a]" } -ArgumentList 'x'
'--- serialized results'
$r = Invoke-Command -ComputerName localhost -Credential $cred -ScriptBlock { Get-Process -Id $PID }
'type: ' + $r.GetType().FullName + ' ; PSComputerName=' + $r.PSComputerName + ' ; Kill() present=' + [bool]($r | Get-Member -Name Kill -MemberType Method) + ' ; RunspaceId present=' + [bool]$r.RunspaceId
'--- persistent session keeps state'
$s = New-PSSession -ComputerName localhost -Credential $cred
Invoke-Command -Session $s -ScriptBlock { $x = 42 }
'second call sees x=' + (Invoke-Command -Session $s -ScriptBlock { $x })
(Get-PSSession | ForEach-Object { 'session ' + $_.Name + ' state=' + $_.State + ' availability=' + $_.Availability })
'--- Enter state: working directory and variables are remote'
Invoke-Command -Session $s -ScriptBlock { (Get-Location).Path }
'--- copy a file over the session'
Set-Content "$env:TEMP\wl-send.txt" 'payload'
Copy-Item "$env:TEMP\wl-send.txt" -Destination 'C:\Windows\Temp\wl-recv.txt' -ToSession $s
Invoke-Command -Session $s -ScriptBlock { 'remote file: ' + (Get-Content C:\Windows\Temp\wl-recv.txt); Remove-Item C:\Windows\Temp\wl-recv.txt }
Remove-Item "$env:TEMP\wl-send.txt"
Remove-PSSession $s
'--- many computers: ordering and PSComputerName (same host twice by different names)'
Invoke-Command -ComputerName 'localhost',$env:COMPUTERNAME -Credential $cred -ScriptBlock { Start-Sleep -Milliseconds (Get-Random -Maximum 300); $env:COMPUTERNAME } | ForEach-Object { '  ' + $_ + ' from ' + $_.PSComputerName }
'--- errors in a remote block'
try { Invoke-Command -ComputerName localhost -Credential $cred -ScriptBlock { Get-Item C:\nope -ErrorAction Stop } -ErrorAction Stop } catch { 'caught: ' + $_.Exception.GetType().Name + ' - ' + ($_.Exception.Message -split "`n")[0] }
Invoke-Command -ComputerName localhost -Credential $cred -ScriptBlock { Write-Error 'remote soft error'; 'carried on' } -ErrorVariable ev -ErrorAction SilentlyContinue
'errors collected: ' + $ev.Count + ' ; origin: ' + $ev[0].OriginInfo
'--- AsJob'
$j = Invoke-Command -ComputerName localhost -Credential $cred -ScriptBlock { Start-Sleep 1; 'job done on ' + $env:COMPUTERNAME } -AsJob
'job type: ' + $j.GetType().Name + ' state now: ' + $j.State
$j | Wait-Job | Receive-Job
$j | Remove-Job
'--- by IP address (needs HTTPS or TrustedHosts with NTLM)'
try { Invoke-Command -ComputerName 127.0.0.1 -Credential $cred -ScriptBlock { 'reached by ip' } -ErrorAction Stop } catch { 'by IP failed: ' + (($_.Exception.Message -split "`n")[0]).Substring(0, [Math]::Min(260, (($_.Exception.Message -split "`n")[0]).Length)) }
