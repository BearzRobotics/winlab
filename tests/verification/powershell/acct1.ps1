# Battery for windows-admin.accounts-and-permissions. THROWAWAY VM ONLY, elevated: makes the accounts
# wluser1 and the folder C:\wlacl, changes the lockout policy, then puts the policy back and removes all.
$ErrorActionPreference = 'Continue'
function Section($t) { "`n=== $t" }
function Show($x) { ($x | Out-String -Width 150).Trim("`r", "`n") }
"PowerShell $($PSVersionTable.PSVersion)  $((Get-CimInstance Win32_OperatingSystem).Caption)"
Section 'local users on a fresh server'
Show (Get-LocalUser | Format-Table Name, Enabled, LastLogon, PasswordExpires, PasswordRequired -AutoSize)
$good = 'Wl-Pw-8h!k2'
net.exe user wluser1 $good /add | Out-Null
net.exe share wlshare=C:\Windows\Temp /grant:Everyone,READ | Out-Null
function TryLogon($pw) {
    cmd.exe /d /c "net use \\127.0.0.1\wlshare /user:wluser1 $pw 2>&1"
    $code = $LASTEXITCODE
    cmd.exe /d /c "net use \\127.0.0.1\wlshare /delete /y >nul 2>&1"
}
function Why($since) {
    Start-Sleep 2
    $e = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4625; StartTime = $since } -MaxEvents 1 -ErrorAction SilentlyContinue
    if ($e) { $x = @{}; ([xml]$e.ToXml()).Event.EventData.Data | ForEach-Object { $x[$_.Name] = $_.'#text' }; "4625: LogonType=$($x.LogonType) Status=$($x.Status) SubStatus=$($x.SubStatus)" } else { 'no 4625' }
}
function Case($title, $pw) { Section "sign-in: $title"; $t = Get-Date; TryLogon $pw; Why $t; Start-Sleep 1 }
Case 'good password' $good
Case 'wrong password' 'nope-nope'
Disable-LocalUser wluser1
Case 'disabled account, right password' $good
Enable-LocalUser wluser1
Set-LocalUser wluser1 -AccountExpires (Get-Date).AddDays(-1)
Case 'expired account' $good
Set-LocalUser wluser1 -AccountNeverExpires
net.exe user wluser1 /logonpasswordchg:yes | Out-Null
Case 'must change password at next logon' $good
net.exe user wluser1 /logonpasswordchg:no | Out-Null
Section 'a user name that does not exist'
$t = Get-Date; cmd.exe /d /c "net use \\127.0.0.1\wlshare /user:wlnobody whatever 2>&1"; Why $t
Section 'lockout'
net.exe accounts /lockoutthreshold:3 /lockoutduration:30 /lockoutwindow:30 | Out-Null
1..3 | ForEach-Object { TryLogon 'nope-nope' | Out-Null }
Case 'locked out, right password' $good
$adsi = [ADSI]"WinNT://$env:COMPUTERNAME/wluser1,user"
"IsAccountLocked: $($adsi.InvokeGet('IsAccountLocked'))"
Show (Get-LocalUser wluser1 | Format-List Name, Enabled)
net.exe user wluser1 | Select-String 'active|expires|Password|Last logon|Memberships'
$ev = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4740 } -MaxEvents 1 -ErrorAction SilentlyContinue
"4740 logged: $([bool]$ev)"; if ($ev) { ($ev.Message -split "`r?`n" | Select-Object -First 1) }
$adsi.InvokeSet('IsAccountLocked', $false); $adsi.CommitChanges()
Case 'after unlocking' $good
net.exe accounts /lockoutthreshold:0 | Out-Null
Section 'help messages'
foreach ($n in 1326, 1331, 1793, 1907, 1909) { "$n : $((net.exe helpmsg $n | Where-Object { $_ }) -join ' ')" }
net.exe share wlshare /delete /y | Out-Null

Section 'icacls: grant adds, grant:r replaces'
New-Item -ItemType Directory C:\wlacl\data\sub -Force | Out-Null
Set-Content C:\wlacl\data\sub\f.txt 'x'
icacls.exe C:\wlacl\data /grant 'wluser1:(OI)(CI)R' | Out-Null
icacls.exe C:\wlacl\data /grant 'wluser1:(OI)(CI)M' | Out-Null
icacls.exe C:\wlacl\data | Select-String wluser1
icacls.exe C:\wlacl\data /grant:r 'wluser1:(OI)(CI)R' | Out-Null
"after /grant:r"; icacls.exe C:\wlacl\data | Select-String wluser1
Section 'grant without (OI)(CI)'
icacls.exe C:\wlacl\data /remove wluser1 | Out-Null
icacls.exe C:\wlacl\data /grant 'wluser1:M' | Out-Null
"folder:"; icacls.exe C:\wlacl\data | Select-String wluser1
"file below (lines naming wluser1): $(@(icacls.exe C:\wlacl\data\sub\f.txt | Select-String wluser1).Count)"
icacls.exe C:\wlacl\data /remove wluser1 | Out-Null
Section 'inheritance :d and :r on a copy'
New-Item -ItemType Directory C:\wlacl\inh -Force | Out-Null
icacls.exe C:\wlacl\inh
"--- /inheritance:d"; icacls.exe C:\wlacl\inh /inheritance:d | Out-Null; icacls.exe C:\wlacl\inh
New-Item -ItemType Directory C:\wlacl\inh2 -Force | Out-Null
"--- /inheritance:r"; icacls.exe C:\wlacl\inh2 /inheritance:r | Out-Null; icacls.exe C:\wlacl\inh2
try { Get-ChildItem C:\wlacl\inh2 -ErrorAction Stop | Out-Null; 'listing inh2: allowed' } catch { "listing inh2: $($_.Exception.Message)" }

Section 'save and restore'
icacls.exe C:\wlacl\data /grant 'wluser1:(OI)(CI)M' | Out-Null
icacls.exe C:\wlacl\data /save C:\wlacl\acl.txt /t
"--- the saved file:"; Get-Content C:\wlacl\acl.txt | Select-Object -First 6
icacls.exe C:\wlacl\data /remove wluser1 | Out-Null
"--- restore pointed at the folder itself:"; icacls.exe C:\wlacl\data /restore C:\wlacl\acl.txt
"entries now: $(@(icacls.exe C:\wlacl\data | Select-String wluser1).Count)"
"--- restore pointed at its PARENT:"; icacls.exe C:\wlacl /restore C:\wlacl\acl.txt
"entries now: $(@(icacls.exe C:\wlacl\data | Select-String wluser1).Count)"

Section 'owner'
(Get-Acl C:\wlacl\data).Owner

takeown.exe /f C:\wlacl\data | Out-Null
net.exe user wluser1 /delete | Out-Null
Remove-Item C:\wlacl -Recurse -Force
"cleaned: $(-not (Test-Path C:\wlacl))  lockout threshold:"; net.exe accounts | Select-String 'Lockout threshold'
