# Battery for windows-admin.services-and-startup, part 2. THROWAWAY VM ONLY, elevated: checks claims that
# part 1 did not settle. Removes what it makes.
$ErrorActionPreference = 'Continue'
function Section($t) { "`n=== $t" }
function StartType($n) { (sc.exe qc $n | Select-String 'START_TYPE').Line.Trim() }
function Scm($since) {
    Start-Sleep 3
    Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Service Control Manager'; StartTime = $since } -ErrorAction SilentlyContinue |
        Sort-Object RecordId | Where-Object Id -ne 7036 | ForEach-Object { "event $($_.Id): $(($_.Message -replace '\s+', ' ').Trim())" }
}
"PowerShell $($PSVersionTable.PSVersion)"
New-Service -Name wl-cfg -BinaryPathName 'C:\wl\x.exe' -StartupType Manual | Out-Null
Section 'sc.exe config without the space, from cmd.exe'
"before: $(StartType wl-cfg)"
cmd.exe /d /c 'sc.exe config wl-cfg start=disabled'
"after start=disabled: $(StartType wl-cfg)"
cmd.exe /d /c 'sc.exe config wl-cfg start= demand'
"after 'start= demand': $(StartType wl-cfg)"
Section 'delayed-auto on a service with no load order group'
sc.exe config wl-cfg start= delayed-auto
StartType wl-cfg
"Get-Service StartType: $((Get-Service wl-cfg).StartType)"
Get-CimInstance Win32_Service -Filter "Name='wl-cfg'" | ForEach-Object { "CIM StartMode=$($_.StartMode) DelayedAutoStart=$($_.DelayedAutoStart)" }

Section 'service account whose password changed after the service was created'
net.exe user wlsvcuser 'Wl-Bat-7q!x2' /add
sc.exe create wl-account binPath= C:\Windows\System32\cmd.exe obj= .\wlsvcuser password= 'Wl-Bat-7q!x2'
net.exe user wlsvcuser 'Wl-New-9k!z4'
$t = Get-Date; sc.exe start wl-account; Scm $t

Section 'process dies with no recovery actions'
sc.exe failure Spooler reset= 0 actions= '""' | Out-Null
sc.exe qfailure Spooler
$t = Get-Date
Stop-Process -Id (Get-CimInstance Win32_Service -Filter "Name='Spooler'").ProcessId -Force
Start-Sleep 9
"status: $((Get-Service Spooler).Status)"
Scm $t
sc.exe query Spooler

Section 'what 1077 means'
net.exe helpmsg 1077

Section 'stop a service that others need, without -Force'
New-Service -Name wl-dummy -BinaryPathName 'C:\wl\x.exe' -StartupType Manual | Out-Null
try { Stop-Service RpcSs -ErrorAction Stop } catch { "$($_.Exception.Message)" }

foreach ($n in 'wl-cfg', 'wl-account', 'wl-dummy') { sc.exe delete $n | Out-Null }
net.exe user wlsvcuser /delete | Out-Null
"services left: $(@(Get-Service wl-* -ErrorAction SilentlyContinue).Count)"
