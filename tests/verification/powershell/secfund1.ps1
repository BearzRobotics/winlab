# Battery for security.security-fundamentals. THROWAWAY VM ONLY, elevated: makes a folder, permission entries
# and one local account, causes one failed sign-in, and removes what it made.
$ErrorActionPreference = 'Continue'
function Section($t) { "`n=== $t" }
function Show($x) { ($x | Out-String -Width 150).Trim("`r", "`n") }
"PowerShell $($PSVersionTable.PSVersion)  $((Get-CimInstance Win32_OperatingSystem).Caption)"
Section 'who am I'
whoami.exe
whoami.exe /groups /fo table | Select-String -Pattern 'Administrators|Mandatory Label|BUILTIN\\Users'
whoami.exe /priv | Select-String -Pattern 'SeBackup|SeDebug|SeShutdown|SeTakeOwnership'

$d = 'C:\wlsec'; $f = "$d\report.txt"
New-Item -ItemType Directory $d -Force | Out-Null
Set-Content $f 'quarterly numbers'
Section 'icacls on a new folder'
icacls.exe $d
$me = "$env:COMPUTERNAME\$env:USERNAME"
function TryRead { try { "read: $(Get-Content $f -ErrorAction Stop)" } catch { "read: $($_.Exception.GetType().Name)" } }
Section 'deny on the parent, inherited by the file'
icacls.exe $d /deny 'Everyone:(OI)(CI)(RD)' | Out-Null
icacls.exe $f
TryRead
Section 'plus an EXPLICIT allow on the file itself'
icacls.exe $f /grant "${me}:(R)" | Out-Null
icacls.exe $f
TryRead
Section 'explicit deny and explicit allow on the same file'
icacls.exe $f /deny 'Everyone:(RD)' | Out-Null
icacls.exe $f
TryRead
icacls.exe $d /remove:d 'Everyone' | Out-Null
icacls.exe $f /remove:d 'Everyone' | Out-Null
TryRead

Section 'a disabled account and a failed sign-in'
$pw = ConvertTo-SecureString ('Wl-' + [guid]::NewGuid().ToString('N') + '!a') -AsPlainText -Force
New-LocalUser -Name wlalice -Password $pw -Description 'battery' | Out-Null
Show (Get-LocalUser wlalice | Format-List Name, Enabled, LastLogon, PasswordLastSet, SID)
Disable-LocalUser wlalice
"enabled: $((Get-LocalUser wlalice).Enabled)"
Enable-LocalUser wlalice
$start = Get-Date
net.exe use \\127.0.0.1\IPC$ /user:wlalice 'definitely-wrong' 2>&1
Start-Sleep 3
Section 'audit policy for logon'
auditpol.exe /get /subcategory:"Logon"
Section 'event 4625'
$e = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4625; StartTime = $start } -MaxEvents 1 -ErrorAction SilentlyContinue
if ($e) {
    $x = @{}; ([xml]$e.ToXml()).Event.EventData.Data | ForEach-Object { $x[$_.Name] = $_.'#text' }
    foreach ($k in 'TargetUserName', 'LogonType', 'Status', 'SubStatus', 'IpAddress', 'AuthenticationPackageName') { "$k = $($x[$k])" }
} else { 'no 4625 event found' }
Section 'delete and recreate: same name, different account'
$sid1 = (Get-LocalUser wlalice).SID.Value
icacls.exe $f /grant 'wlalice:(R)' | Out-Null
Remove-LocalUser wlalice
icacls.exe $f
New-LocalUser -Name wlalice -Password $pw | Out-Null
"old SID ends: $($sid1.Split('-')[-1])   new SID ends: $((Get-LocalUser wlalice).SID.Value.Split('-')[-1])"
icacls.exe $f
Remove-LocalUser wlalice

Section 'listening ports and their processes'
Show (Get-NetTCPConnection -State Listen | Sort-Object LocalPort, LocalAddress |
    Select-Object LocalAddress, LocalPort, @{n = 'Process'; e = { (Get-Process -Id $_.OwningProcess).Name } } |
    Where-Object { $_.LocalPort -lt 6000 } | Format-Table -AutoSize)
Remove-Item $d -Recurse -Force
"cleaned: $(-not (Test-Path $d))"
