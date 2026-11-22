# Security lesson battery for Windows: does the lockout threshold lock an account (run elevated in the Server VM)
"### policy: 5 bad attempts, 12 characters"
net accounts /minpwlen:12 /lockoutthreshold:5 /lockoutduration:30 /lockoutwindow:30 | Out-Null
net user wlvictim 'Lab-pass-12!!' /add | Select-Object -First 1
"### 6 bad logons"
1..6 | ForEach-Object { $o = net use \\localhost\IPC$ /user:wlvictim wrong 2>&1 | Select-Object -First 1; "attempt $_ : $o" }
net user wlvictim | Select-String 'Account active|Lockout|Last logon'
"### the right password now"
net use \\localhost\IPC$ /user:wlvictim 'Lab-pass-12!!' 2>&1 | Select-Object -First 1
"### event 4740 (account locked out)"
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4740; StartTime=(Get-Date).AddMinutes(-5)} -EA SilentlyContinue | ForEach-Object { $d=@{}; foreach ($i in ([xml]$_.ToXml()).Event.EventData.Data) { $d[$i.Name]=$i.'#text' }; '{0} id=4740 account={1} from={2}' -f $_.TimeCreated.ToString('HH:mm:ss'), $d.TargetUserName, $d.TargetDomainName }
"### unlock it"
net user wlvictim /active:yes | Select-Object -First 1
net user wlvictim | Select-String 'Account active|Lockout'
net use \\localhost\IPC$ /user:wlvictim 'Lab-pass-12!!' 2>&1 | Select-Object -First 1
net use * /delete /y 2>&1 | Out-Null
net user wlvictim /delete | Out-Null; net accounts /minpwlen:0 /lockoutthreshold:0 | Out-Null
