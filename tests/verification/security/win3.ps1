# Security lesson battery for Windows: fix the findings the fresh server really has, then re-run the baseline (run elevated in the Server VM; needs C:\Windows\Temp\wl-winbaseline.ps1)
$B = 'C:\Windows\Temp\wl-winbaseline.ps1'
"### before"; net accounts | Select-String 'Minimum password length|Lockout threshold'
(Get-SmbServerConfiguration).RequireSecuritySignature
"### fixes"
Set-SmbServerConfiguration -RequireSecuritySignature $true -Force; 'smb signing set'
net accounts /minpwlen:12 /lockoutthreshold:5
"### after"
net accounts | Select-String 'Minimum password length|Lockout threshold'
(Get-SmbServerConfiguration).RequireSecuritySignature
powershell -NoProfile -ExecutionPolicy Bypass -File $B | Where-Object { $_ -notlike 'REVIEW*' }
"### a password that is too short is now refused"
net user wlshort 'abc' /add 2>&1 | Select-Object -First 2
net user wllong 'Correct-horse-9!' /add 2>&1 | Select-Object -First 1; net user wllong /delete | Out-Null
"### a local admin tries 6 bad logons; is the account locked?"
net user wlvictim 'Correct-horse-9!' /add | Out-Null
1..6 | ForEach-Object { net use \localhost\IPC$ /user:wlvictim wrong 2>&1 | Select-Object -First 1 }
(net user wlvictim | Select-String 'Account active|Lockout')
net user wlvictim /delete | Out-Null
"### revert"
net accounts /minpwlen:0 /lockoutthreshold:0 | Out-Null; Set-SmbServerConfiguration -RequireSecuritySignature $false -Force
