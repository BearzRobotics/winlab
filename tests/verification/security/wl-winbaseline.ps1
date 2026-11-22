# wl-winbaseline.ps1 [-AllowedAdmins Administrator] [-MinPasswordLength 12] [-MaxPatchAgeDays 90]
# A read-only security baseline check for one Windows machine, run elevated in Windows PowerShell 5.1.
# Prints PASS / FAIL / REVIEW lines (REVIEW = a list a person must look at, not a verdict); exit status 1 if any FAIL.
# It changes nothing. The thresholds are this script's choices, not Microsoft's.
param(
  [string[]]$AllowedAdmins = @('Administrator'),
  [int]$MinPasswordLength = 12,
  [int]$MaxPatchAgeDays = 90
)
$ErrorActionPreference = 'Stop'
$script:fails = 0
function Pass($m)   { 'PASS    ' + $m }
function Fail($m)   { $script:fails++; 'FAIL    ' + $m }
function Review($m) { 'REVIEW  ' + $m }
function Check($name, [scriptblock]$body) {
  try { & $body } catch { Fail ("{0}: could not check ({1})" -f $name, $_.Exception.Message.Trim()) }
}

Check 'firewall' {
  $off = Get-NetFirewallProfile | Where-Object { -not $_.Enabled } | ForEach-Object Name
  if ($off) { Fail ('firewall profile(s) off: ' + ($off -join ', ')) } else { Pass 'firewall enabled on all profiles' }
}
Check 'smb' {
  $s = Get-SmbServerConfiguration
  if ($s.EnableSMB1Protocol) { Fail 'SMB1 is enabled' } else { Pass 'SMB1 is disabled' }
  if ($s.RequireSecuritySignature) { Pass 'SMB signing is required' } else { Fail 'SMB signing is not required' }
}
Check 'rdp' {
  $ts  = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server').fDenyTSConnections
  $nla = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp').UserAuthentication
  if ($ts -eq 1) { Pass 'Remote Desktop is off' }
  elseif ($nla -eq 1) { Pass 'Remote Desktop is on with Network Level Authentication' }
  else { Fail 'Remote Desktop is on without Network Level Authentication' }
}
Check 'admins' {
  $names = Get-LocalGroupMember -Group Administrators | ForEach-Object { $_.Name -replace '^.*\\', '' }
  $extra = $names | Where-Object { $AllowedAdmins -notcontains $_ }
  if ($extra) { Fail ('unexpected local administrator(s): ' + ($extra -join ', ')) } else { Pass ('local administrators: ' + ($names -join ', ')) }
}
Check 'accounts' {
  $g = Get-LocalUser -Name Guest
  if ($g.Enabled) { Fail 'the Guest account is enabled' } else { Pass 'the Guest account is disabled' }
  $np = Get-LocalUser | Where-Object { $_.Enabled -and -not $_.PasswordRequired } | ForEach-Object Name
  if ($np) { Fail ('enabled account(s) that need no password: ' + ($np -join ', ')) } else { Pass 'every enabled account requires a password' }
}
Check 'password policy' {
  $na = net accounts
  $len = [int](($na | Select-String 'Minimum password length').ToString() -replace '\D', '')
  $lock = ($na | Select-String 'Lockout threshold').ToString() -replace '^[^:]*:\s*', ''
  if ($len -ge $MinPasswordLength) { Pass "minimum password length is $len" } else { Fail "minimum password length is $len (want at least $MinPasswordLength)" }
  if ($lock -match 'Never') { Fail 'account lockout threshold is Never' } else { Pass "account lockout threshold is $lock" }
}
Check 'defender' {
  $m = Get-MpComputerStatus
  if ($m.RealTimeProtectionEnabled) { Pass 'Microsoft Defender real-time protection is on' } else { Fail 'Microsoft Defender real-time protection is off' }
}
Check 'uac' {
  if ((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System').EnableLUA -eq 1) { Pass 'UAC is on' } else { Fail 'UAC is off' }
}
Check 'patches' {
  $last = Get-HotFix | Where-Object InstalledOn | Sort-Object InstalledOn | Select-Object -Last 1
  if (-not $last) { Fail 'no installed update with a date found'; return }
  $age = [int]((Get-Date) - $last.InstalledOn).TotalDays
  if ($age -le $MaxPatchAgeDays) { Pass "newest update $($last.HotFixID) is $age days old" } else { Fail "newest update $($last.HotFixID) is $age days old (limit $MaxPatchAgeDays)" }
}

# Lists a person must read. The first three are where an intruder's persistence usually shows.
Check 'listeners' {
  $l = Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -lt 49152 } | Sort-Object LocalPort -Unique | ForEach-Object {
    '{0}/{1}' -f $_.LocalPort, (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName }
  Review ('TCP listeners below port 49152 (port/process): ' + ($l -join ' '))
}
Check 'run keys' {
  $r = foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run') {
    $p = Get-ItemProperty $k; $p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value } }
  Review ('Run-key entries: ' + $(if ($r) { $r -join ' | ' } else { '(none)' }))
}
Check 'tasks' {
  $t = Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } | ForEach-Object { $_.TaskPath + $_.TaskName }
  Review ('scheduled tasks outside \Microsoft\: ' + $(if ($t) { $t -join ' | ' } else { '(none)' }))
}
Check 'services' {
  $s = Get-CimInstance Win32_Service | Where-Object { $_.StartMode -eq 'Auto' -and $_.PathName -and ($_.PathName.Trim('"') -notlike 'C:\Windows\*') -and ($_.PathName.Trim('"') -notlike 'C:\Program Files*') } | ForEach-Object { $_.Name + '=' + $_.PathName }
  Review ('automatic services running from outside C:\Windows and C:\Program Files: ' + $(if ($s) { $s -join ' | ' } else { '(none)' }))
}

if ($script:fails) { "{0} check(s) failed" -f $script:fails; exit 1 } else { 'no check failed'; exit 0 }
