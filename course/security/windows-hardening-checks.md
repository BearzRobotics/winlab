*Draft for owner review.* **Hardening** means closing the doors that are open for no good reason; a **baseline check** is a short script that reports, from the outside, whether each door is closed. This lesson builds one for a single Windows machine with built-in tools only (`Get-NetFirewallProfile`, `Get-SmbServerConfiguration`, `Get-LocalUser`, `net accounts`, `Get-MpComputerStatus`, `Get-HotFix`, the registry), runs it on a fresh server, plants nine weaknesses to see whether it notices, fixes the real findings, and shows what a lockout policy actually does. It is the Windows counterpart of `security.linux-hardening-checks`. Lab machines only; read `security.authorization-and-scope` first.

**What was tested, and where.** One VM: **Windows Server 2022 Standard Evaluation**, build 10.0.20348.0, Windows PowerShell **5.1.20348.558**, elevated, a standalone machine (not in a domain). The scripts are `tests/verification/security/wl-winbaseline.ps1` (the checker), `win2.ps1` (planted weaknesses), `win3.ps1` (fixes) and `win4.ps1` (lockout); output is real. **Not tested:** **Windows 10 or 11** (defaults differ: I did not look), **domain-joined** machines and **Group Policy** (the settings below would then be set from a policy and a local change can be overwritten), domain controllers, **PowerShell 7**, a **non-elevated** run, **BitLocker**, AppLocker or Windows Defender Application Control, Credential Guard, LAPS, and Microsoft's own security baselines. Thresholds in the script (12 characters, 90 days, "Administrator is the only administrator") are **this script's choices, not Microsoft's**.

## What a baseline check is, and is not

It is a list of questions with a yes or no answer, run the same way every time, so that a change is visible. It is **not** a security audit, not a compliance certification, and not a substitute for Microsoft's published baselines ([Windows security baselines](https://learn.microsoft.com/en-us/windows/security/operating-system-security/device-management/windows-security-configuration-framework/windows-security-baselines), which I only confirmed load). The script **changes nothing** and prints three kinds of line: `PASS`, `FAIL`, and `REVIEW` (a list a person must read, because only a person knows whether an entry belongs).

## The script

```powershell
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
```

Run it from an elevated PowerShell: `powershell -NoProfile -ExecutionPolicy Bypass -File .\wl-winbaseline.ps1`. Each check sits inside `Check`, so a command that fails (a cmdlet missing, a service off) is reported as a `FAIL ... could not check` line instead of ending the run silently.

## Run on a fresh server

```text
PASS    firewall enabled on all profiles
PASS    SMB1 is disabled
FAIL    SMB signing is not required
PASS    Remote Desktop is off
PASS    local administrators: Administrator
PASS    the Guest account is disabled
PASS    every enabled account requires a password
FAIL    minimum password length is 0 (want at least 12)
FAIL    account lockout threshold is Never
PASS    Microsoft Defender real-time protection is on
PASS    UAC is on
FAIL    newest update KB5008882 is 1726 days old (limit 90)
REVIEW  TCP listeners below port 49152 (port/process): 22/sshd 135/svchost 139/System 445/System 5985/System 47001/System
REVIEW  Run-key entries: SecurityHealth=C:\Windows\system32\SecurityHealthSystray.exe
REVIEW  scheduled tasks outside \Microsoft\: \MicrosoftEdgeUpdateTaskMachineCore1dd6f37cb42fd30 | \MicrosoftEdgeUpdateTaskMachineUA
REVIEW  automatic services running from outside C:\Windows and C:\Program Files: (none)
4 check(s) failed
```

Four real findings on a machine that was never touched, and each needs reading rather than panic:

- **SMB signing not required.** `Get-SmbServerConfiguration` reported `RequireSecuritySignature: False`. Signing stops a man in the middle altering SMB traffic. Microsoft's [SMB signing overview](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-signing-overview) says domain controllers require it by default; this standalone server did not. Requiring it can break old clients (that page has guidance), which I did not test.
- **Minimum password length 0 and lockout `Never`.** `net accounts` showed `Minimum password length: 0` and `Lockout threshold: Never`. Microsoft's [minimum password length](https://learn.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/minimum-password-length) page says setting it to 0 means **no password is required**, and its [account lockout threshold](https://learn.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/account-lockout-threshold) page lists the stand-alone server default as **0 invalid sign-in attempts**, meaning an account is never locked, so a guesser can keep guessing. These are the defaults on this evaluation image, so expect them on a fresh standalone server and check yours.
- **Patches 1726 days old.** The evaluation image's newest installed update dates from March 2022 (`Get-HotFix`; the three listed were all `3/3/2022`), and the VM's clock says 2026. The check works; the finding is true of this image. It is the best reason to run the check against anything you build from an old image. (`Get-HotFix` lists only some updates, those installed by the servicing stack in a way it can see; I did not compare it with Windows Update's own history.)
- Everything else passed, including **SMB1 off** and **Remote Desktop off** (`fDenyTSConnections = 1`).

The `REVIEW` lines are not verdicts. The listener list is the same idea as `ss -tlnp` in `security.own-lab-recon`: **22** is the OpenSSH server the lab uses, **135** is RPC, **139** and **445** are SMB, **5985** is WinRM over HTTP (the WinRM service was running; I did not look up **47001**). Anything you cannot name is a question for the owner of the machine. Run keys, scheduled tasks and services that start from odd folders are where an intruder's persistence usually sits (`security.incident-response-linux` has the Linux version of the idea).

## What each check reads

| Check | Source | Pass when |
|---|---|---|
| Firewall | `Get-NetFirewallProfile` ([doc](https://learn.microsoft.com/en-us/powershell/module/netsecurity/get-netfirewallprofile)) | Domain, Private and Public are all `Enabled` |
| SMB | `Get-SmbServerConfiguration` ([doc](https://learn.microsoft.com/en-us/powershell/module/smbshare/get-smbserverconfiguration)); the page [Detect, enable and disable SMBv1](https://learn.microsoft.com/en-us/windows-server/storage/file-server/troubleshoot/detect-enable-and-disable-smbv1-v2-v3) | SMB1 off, signing required |
| Remote Desktop | registry `fDenyTSConnections`, `UserAuthentication` | off, or on with Network Level Authentication |
| Administrators | `Get-LocalGroupMember` ([doc](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.localaccounts/get-localgroupmember)) | only the names in `-AllowedAdmins` |
| Accounts | `Get-LocalUser` | `Guest` disabled; every enabled account requires a password |
| Password policy | `net accounts` | length at least `-MinPasswordLength`, lockout threshold not `Never` |
| Defender | `Get-MpComputerStatus` ([doc](https://learn.microsoft.com/en-us/powershell/module/defender/get-mpcomputerstatus)) | real-time protection on |
| UAC | registry `EnableLUA` | 1 |
| Patches | `Get-HotFix` ([doc](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-hotfix)) | newest update is within `-MaxPatchAgeDays` |

Note that the firewall check reads whether a profile is **on**. On this server `DefaultInboundAction` showed `NotConfigured` for all three profiles, so "on" says nothing about which **rules** allow what; the script does not review rules.

## Does it notice? Nine planted weaknesses

A checker that has only ever printed `PASS` has not been shown to work. `win2.ps1` plants weaknesses and runs it again:

```text
plant: a new local user wlintruder added to Administrators; Guest enabled; Public firewall profile off;
       Remote Desktop on with NLA off; a Run key wlupdate; a scheduled task wlsync (SYSTEM, daily);
       an automatic service wlsvc from C:\Users\Public; Defender real-time protection off; a listener on port 4444

FAIL    firewall profile(s) off: Public
FAIL    Remote Desktop is on without Network Level Authentication
FAIL    unexpected local administrator(s): wlintruder
FAIL    the Guest account is enabled
FAIL    enabled account(s) that need no password: Guest, wlintruder
FAIL    Microsoft Defender real-time protection is off
REVIEW  TCP listeners below port 49152 (port/process): 22/sshd 135/svchost 139/System 445/System 3389/svchost 4444/powershell 5985/System 47001/System
REVIEW  Run-key entries: SecurityHealth=C:\Windows\system32\SecurityHealthSystray.exe | wlupdate=C:\Users\Public\wlupdate.exe
REVIEW  scheduled tasks outside \Microsoft\: ... | \wlsync
REVIEW  automatic services running from outside C:\Windows and C:\Program Files: wlsvc=C:\Users\Public\wlsvc.exe
10 check(s) failed
```

All nine showed up, six as `FAIL` and the persistence entries and the listener as `REVIEW` lines (as designed: a task or a port is only wrong if you do not know it). I removed everything afterwards and the output returned to the same four original failures.

Two honest limits from that run:

- **The SMB1 check was not proven to fire.** I tried `Set-SmbServerConfiguration -EnableSMB1Protocol $true` and the server answered `The specified service does not exist.` (the SMB1 feature is not installed on this image), so SMB1 stayed off and that check has only ever passed. Do not trust it until you have seen it fail on a machine where SMB1 can be turned on.
- **`wlintruder` was reported as an account that "needs no password"**, although I created it with `New-LocalUser -Password`. `Get-LocalUser` showed `PasswordRequired` as `False` for it. I do not know why and did not test whether such an account can log on with a blank password; the check reports the flag as the system reports it.

Turning Defender's real-time protection off with `Set-MpPreference -DisableRealtimeMonitoring $true` **succeeded** here, from an elevated PowerShell. That is the reason the check exists: on this image nothing stopped it. (Windows has a Tamper Protection feature meant to prevent this; I did not examine whether it was configured.)

## Fixing the real findings

I ran these on the fresh server and then the baseline (`win3.ps1`):

```powershell
Set-SmbServerConfiguration -RequireSecuritySignature $true -Force
net accounts /minpwlen:12 /lockoutthreshold:5
```

```text
Minimum password length:    0  ->  12
Lockout threshold:          Never  ->  5
RequireSecuritySignature:   False  ->  True
PASS    SMB signing is required
PASS    minimum password length is 12
PASS    account lockout threshold is 5
FAIL    newest update KB5008882 is 1726 days old (limit 90)
1 check(s) failed
```

Only the patch finding remained, which needs updates, not a setting. After the change a short password is refused (`The password does not meet the password policy requirements. Check the minimum password length, password complexity and password history requirements.`). A word on the **limit of `net accounts`**: it changes the **local** policy. On a domain-joined machine the domain's policy can overwrite it, and on a domain the same setting lives in Group Policy (not tested).

## What a lockout does, and what it logs

With the lockout threshold at 5, I made six failed network logons for a lab account (`win4.ps1`):

```text
attempt 1..5 : System error 1326 has occurred.      (the user name or password is incorrect)
attempt 6    : System error 1909 has occurred.      (the account is locked out)
Account active               Locked
```

Then I tried the **correct** password: **also `System error 1909`**. A locked account refuses the right password. Security event **4740** (account locked out) was written:

```text
18:17:47 id=4740 account=wlvictim from=WINLAB-LAB-C
```

and `net user wlvictim /active:yes` unlocked it; the correct password then worked. Two lessons here. First, **lockout is a defence against guessing and a lever for denial of service**: anyone who can reach the logon prompt can lock a name out by guessing it, so the threshold is a trade-off, not a free win (Microsoft has an [account lockout policy](https://learn.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/account-lockout-policy) page; I only confirmed that it loads, and read the threshold page only for its default). Second, **4740 is a detection**: add it to the list in `security.windows-logging-and-detection`. The lockout duration and window were 30 minutes in my test; I did not wait them out.

## Reading the check alongside the logs

The baseline says what is **configured now**; the event log says what **happened**. A new local administrator shows in the baseline (`FAIL unexpected local administrator(s)`) and as events 4720 and 4732 in the log (the previous lesson), which also tell you **who** and **when**. A check that runs every day and a log that is shipped off the machine make a pair; either alone leaves a gap.

## Common mistakes

- **Trusting a check that has never failed.** Plant a weakness and watch it fire; the SMB1 check above has not been proven.
- **Reading `Enabled` as safe.** A firewall that is on can still have a rule allowing everything.
- **Hardening by setting `net accounts` on a domain machine** and not noticing the domain overwrites it.
- **A lockout threshold of 1 or 2.** One typo, or one guesser, locks the user out.
- **Forgetting that Guest and service accounts exist.** The check lists them; a person decides.
- **Fixing a finding and not recording the date and the person.** A baseline is a conversation over time.
- **Running a check from a machine you do not own.** Lab machines only.

## Check yourself

1. Run `wl-winbaseline.ps1` on a Windows machine you own. Which lines fail, and which of those are settings versus a missing update?
2. Plant a weakness the script does not check (for example, a second listener on 4445) and say which line shows it and which does not.
3. Set `-MinPasswordLength 14` and re-run. What changes, and why is the number a choice?
4. With a threshold of 3, lock a lab account out. Which error code did the third bad attempt give, which event was written, and how do you unlock it?
5. Why is a lockout both a defence and a risk?

## Not tested, and honest limits

Windows 10 and 11; domain-joined machines and Group Policy; a non-elevated run; PowerShell 7; BitLocker, AppLocker, Credential Guard, LAPS and Tamper Protection; the SMB1 positive case; blank-password behaviour of an account flagged `PasswordRequired = False`; waiting out the lockout window; and Microsoft's own baselines. Everything above comes from one evaluation-image server on one day. A check for one machine is not an inventory of many.
