# Security lesson battery for Windows: auditing, failed and successful logons, account changes, log clearing (run elevated in the Server VM)
$ErrorActionPreference = 'Continue'
"### $((Get-CimInstance Win32_OperatingSystem).Caption)  build $([Environment]::OSVersion.Version)  PowerShell $($PSVersionTable.PSVersion)"

function Show-Events($id, $n = 3) {
  Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = $id; StartTime = (Get-Date).AddMinutes(-10) } -ErrorAction SilentlyContinue |
    Select-Object -First $n | ForEach-Object {
      $x = [xml]$_.ToXml(); $d = @{}
      foreach ($i in $x.Event.EventData.Data) { $d[$i.Name] = $i.'#text' }
      [pscustomobject]@{ Time = $_.TimeCreated.ToString('HH:mm:ss'); Id = $_.Id; Data = $d }
    }
}

"### 1. the audit policy (auditpol /get)"
auditpol /get /subcategory:"Logon","Logoff","Account Lockout","User Account Management","Security Group Management","Audit Policy Change","Security State Change" 2>&1 | Select-Object -Skip 1

"### 2. turn on logon auditing, then generate a failure and a success against a lab account"
auditpol /set /subcategory:"Logon" /success:enable /failure:enable | Out-Null
auditpol /get /subcategory:"Logon" | Select-Object -Skip 3
net user wlvictim 'Lab-pass-1!' /add 2>&1 | Select-Object -Last 1
net use \\localhost\IPC$ /user:wlvictim wrong-password 2>&1 | Select-Object -First 1
net use \\localhost\IPC$ /user:wlnosuchuser wrong-password 2>&1 | Select-Object -First 1
net use \\localhost\IPC$ /user:wlvictim 'Lab-pass-1!' 2>&1 | Select-Object -First 1
net use * /delete /y 2>&1 | Out-Null
Start-Sleep -Seconds 2

"### 3. event 4625 (failed logon): who, how, why, from where"
foreach ($e in (Show-Events 4625 3)) {
  $d = $e.Data
  '{0} id={1} user={2} domain={3} type={4} status={5} substatus={6} ip={7} process={8}' -f $e.Time, $e.Id, $d.TargetUserName, $d.TargetDomainName, $d.LogonType, $d.Status, $d.SubStatus, $d.IpAddress, ($d.ProcessName -replace '^.*\\')
}
"--- the raw message text of one event"
(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4625; StartTime = (Get-Date).AddMinutes(-10) } -MaxEvents 1).Message -split "`r?`n" | Select-Object -First 12

"### 4. event 4624 (successful logon) for the lab account"
foreach ($e in (Show-Events 4624 20 | Where-Object { $_.Data.TargetUserName -eq 'wlvictim' } | Select-Object -First 2)) {
  $d = $e.Data
  '{0} id={1} user={2} type={3} ip={4} process={5} auth={6}' -f $e.Time, $e.Id, $d.TargetUserName, $d.LogonType, $d.IpAddress, ($d.ProcessName -replace '^.*\\'), $d.AuthenticationPackageName
}

"### 5. account and group changes: 4720 (user created), 4732 (added to a local group)"
net localgroup Administrators wlvictim /add 2>&1 | Select-Object -Last 1
Start-Sleep -Seconds 1
foreach ($e in (Show-Events 4720 2 | Select-Object -First 1)) { '{0} id={1} created={2} by={3}' -f $e.Time, $e.Id, $e.Data.TargetUserName, $e.Data.SubjectUserName }
foreach ($e in (Show-Events 4732 5 | Select-Object -First 1)) { '{0} id={1} member={2} group={3} by={4}' -f $e.Time, $e.Id, $e.Data.MemberSid, $e.Data.TargetUserName, $e.Data.SubjectUserName }

"### 6. count failures per account, per type, with PowerShell"
Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4625; StartTime = (Get-Date).AddMinutes(-10) } -ErrorAction SilentlyContinue |
  ForEach-Object { ([xml]$_.ToXml()).Event.EventData.Data | Where-Object Name -eq 'TargetUserName' | ForEach-Object '#text' } |
  Group-Object | Sort-Object Count -Descending | Format-Table Count, Name -AutoSize | Out-String -Width 100

"### 7. wevtutil and the same query in XPath"
wevtutil qe Security '/q:*[System[(EventID=4625)]]' /c:1 /rd:true /f:text 2>&1 | Select-Object -First 8
"--- log size and retention"
wevtutil gl Security | Select-String 'name:|enabled:|retention:|maxSize:'

"### 8. clearing the log is itself logged (1102)"
$before = (Get-WinEvent -LogName Security -MaxEvents 1).RecordId
wevtutil cl Security
Start-Sleep -Seconds 1
Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 1102 } -MaxEvents 1 | ForEach-Object { '{0} id={1} provider={2}' -f $_.TimeCreated.ToString('HH:mm:ss'), $_.Id, $_.ProviderName; ($_.Message -split "`r?`n")[0..2] }
"events left in the Security log after the clear: $((Get-WinEvent -LogName Security -ErrorAction SilentlyContinue | Measure-Object).Count)"

"### cleanup"
net localgroup Administrators wlvictim /delete 2>&1 | Out-Null
net user wlvictim /delete 2>&1 | Select-Object -Last 1
"done"
