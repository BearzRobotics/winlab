# Battery for endpoints.protect-devices. RUN ONLY IN A THROWAWAY VM, elevated: it changes the firewall,
# Defender exclusions and puts everything back.
$ErrorActionPreference = 'Continue'
function Section($t) { "`n=== $t" }
function Show($x) { ($x | Out-String -Width 150).Trim("`r", "`n") }
"PowerShell $($PSVersionTable.PSVersion)  $((Get-CimInstance Win32_OperatingSystem).Caption)"

Section 'which profile each connection uses'
Show (Get-NetConnectionProfile | Format-Table InterfaceAlias, NetworkCategory, IPv4Connectivity -AutoSize)
Section 'profiles (stored settings)'
Show (Get-NetFirewallProfile | Format-Table Name, Enabled, DefaultInboundAction, DefaultOutboundAction, LogBlocked -AutoSize)
Section 'profiles (ActiveStore: what is in force)'
Show (Get-NetFirewallProfile -PolicyStore ActiveStore | Format-Table Name, Enabled, DefaultInboundAction, DefaultOutboundAction, LogBlocked, NotifyOnListen -AutoSize)
Section 'netsh view of the current profile'
netsh advfirewall show currentprofile

Section 'rule counts'
$in = @(Get-NetFirewallRule -Direction Inbound)
"inbound rules: $($in.Count)  enabled: $(@($in | Where-Object Enabled -eq 'True').Count)  enabled+allow: $(@($in | Where-Object { $_.Enabled -eq 'True' -and $_.Action -eq 'Allow' }).Count)"

Section 'create one rule for one port'
New-NetFirewallRule -DisplayName 'WinLab test 8088' -Direction Inbound -Protocol TCP -LocalPort 8088 -Action Allow -Profile Private, Domain | Out-Null
$r = Get-NetFirewallRule -DisplayName 'WinLab test 8088'
Show ($r | Format-List DisplayName, Enabled, Direction, Action, Profile)
Show ($r | Get-NetFirewallPortFilter | Format-List Protocol, LocalPort)
Show ($r | Get-NetFirewallAddressFilter | Format-List RemoteAddress)
Section 'same DisplayName again'
New-NetFirewallRule -DisplayName 'WinLab test 8088' -Direction Inbound -Protocol TCP -LocalPort 8088 -Action Allow | Out-Null
"rules with that name: $(@(Get-NetFirewallRule -DisplayName 'WinLab test 8088').Count)"
Section 'find enabled inbound allow rules for a port'
Show (Get-NetFirewallPortFilter -Protocol TCP | Where-Object LocalPort -eq '8088' | Get-NetFirewallRule | Format-Table DisplayName, Enabled, Action, Profile -AutoSize)
Remove-NetFirewallRule -DisplayName 'WinLab test 8088'
"after removal: $(@(Get-NetFirewallRule -DisplayName 'WinLab test 8088' -ErrorAction SilentlyContinue).Count)"

Section 'turn Public off, read, restore'
Set-NetFirewallProfile -Profile Public -Enabled False
Show (Get-NetFirewallProfile | Format-Table Name, Enabled -AutoSize)
Set-NetFirewallProfile -Profile Public -Enabled True
Show (Get-NetFirewallProfile | Format-Table Name, Enabled -AutoSize)
Section 'who changed the firewall: event log'
Show (Get-WinEvent -LogName 'Microsoft-Windows-Windows Firewall With Advanced Security/Firewall' -MaxEvents 6 | Format-Table TimeCreated, Id, @{n = 'First line'; e = { ($_.Message -split "`r?`n")[0] } } -AutoSize)
$e = Get-WinEvent -LogName 'Microsoft-Windows-Windows Firewall With Advanced Security/Firewall' -MaxEvents 1; "--- newest message in full:"; $e.Message

Section 'Defender status'
Show (Get-MpComputerStatus | Format-List AMRunningMode, AMServiceEnabled, AntivirusEnabled, RealTimeProtectionEnabled, BehaviorMonitorEnabled, IoavProtectionEnabled, IsTamperProtected, AntivirusSignatureVersion, AntivirusSignatureLastUpdated, AntivirusSignatureAge, QuickScanAge, FullScanAge, QuickScanEndTime)
Section 'service'
Show (Get-Service WinDefend, mpssvc | Format-Table Name, DisplayName, Status, StartType -AutoSize)
Section 'exclusions before'
$p = Get-MpPreference; "path: $($p.ExclusionPath -join ', ' )  process: $($p.ExclusionProcess -join ', ')  extension: $($p.ExclusionExtension -join ', ')"
Section 'add and remove an exclusion'
New-Item -ItemType Directory C:\wltest -Force | Out-Null
Add-MpPreference -ExclusionPath C:\wltest
"path exclusions now: $((Get-MpPreference).ExclusionPath -join ', ')"
$ev = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Windows Defender/Operational'; Id = 5007 } -MaxEvents 1 -ErrorAction SilentlyContinue
"--- newest 5007:"; $ev.Message
Remove-MpPreference -ExclusionPath C:\wltest
"path exclusions after: [$((Get-MpPreference).ExclusionPath -join ', ')]"
Section 'custom scan of a clean folder'
Set-Content C:\wltest\hello.txt 'hello'
$t = Measure-Command { $out = Start-MpScan -ScanType CustomScan -ScanPath C:\wltest }
"output objects: $(@($out).Count)   seconds: $([math]::Round($t.TotalSeconds,1))"
"detections: $(@(Get-MpThreatDetection).Count)"
Show (Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Windows Defender/Operational'; Id = 1000, 1001 } -MaxEvents 2 -ErrorAction SilentlyContinue | Format-Table TimeCreated, Id, @{n = 'First line'; e = { ($_.Message -split "`r?`n")[0] } } -AutoSize)
Remove-Item C:\wltest -Recurse -Force

Section 'BitLocker and TPM'
Show (Get-WindowsFeature BitLocker -ErrorAction SilentlyContinue | Format-Table Name, InstallState -AutoSize)
"manage-bde present: $([bool](Get-Command manage-bde.exe -ErrorAction SilentlyContinue))   Get-BitLockerVolume present: $([bool](Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue))"
if (Get-Command manage-bde.exe -ErrorAction SilentlyContinue) { manage-bde.exe -status C: }
try { Show (Get-Tpm -ErrorAction Stop | Format-List TpmPresent, TpmReady) } catch { "Get-Tpm: $($_.Exception.Message)" }

Section 'sign-in settings'
$sys = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
"EnableLUA (UAC): $($sys.EnableLUA)   ConsentPromptBehaviorAdmin: $($sys.ConsentPromptBehaviorAdmin)   InactivityTimeoutSecs: [$($sys.InactivityTimeoutSecs)]"
Show (Get-LocalGroupMember Administrators | Format-Table Name, ObjectClass, PrincipalSource -AutoSize)
Show (Get-LocalUser | Format-Table Name, Enabled, PasswordRequired -AutoSize)
net.exe accounts
