# Battery for endpoints.update-and-policy. THROWAWAY VM ONLY, elevated: writes a demo policy key
# (HKLM\SOFTWARE\Policies\WinLabDemo), runs gpupdate, and removes the key. Does not scan for updates.
$ErrorActionPreference = 'Continue'
function Section($t) { "`n=== $t" }
function Show($x) { ($x | Out-String -Width 150).Trim("`r", "`n") }
"PowerShell $($PSVersionTable.PSVersion)  $((Get-CimInstance Win32_OperatingSystem).Caption)"
Section 'update services'
Show (Get-Service wuauserv, bits, cryptsvc, UsoSvc, TrustedInstaller | Format-Table Name, DisplayName, Status, StartType -AutoSize)
Section 'wuauserv triggers'
sc.exe qtriggerinfo wuauserv
Section 'Get-HotFix'
Show (Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 5 HotFixID, Description, InstalledOn | Format-Table -AutoSize)
"hotfixes: $(@(Get-HotFix).Count)"
Section 'update history through the Windows Update Agent'
$searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
$n = $searcher.GetTotalHistoryCount(); "history entries: $n"
if ($n) { Show ($searcher.QueryHistory(0, [math]::Min($n, 6)) | Select-Object Date, ResultCode, @{n = 'HResult'; e = { '0x{0:X8}' -f $_.HResult } }, @{n = 'Title'; e = { $_.Title.Substring(0, [math]::Min(70, $_.Title.Length)) } } | Format-Table -AutoSize) }
Section 'update client events'
Show (Get-WinEvent -LogName Microsoft-Windows-WindowsUpdateClient/Operational -MaxEvents 6 -ErrorAction SilentlyContinue | Format-Table TimeCreated, Id, LevelDisplayName, @{n = 'First line'; e = { ($_.Message -split "`r?`n")[0] } } -AutoSize)
Section 'free space and uptime'
Show (Get-PSDrive C | Format-Table Name, @{n = 'UsedGB'; e = { [math]::Round($_.Used / 1GB, 1) } }, @{n = 'FreeGB'; e = { [math]::Round($_.Free / 1GB, 1) } } -AutoSize)
"last boot: $((Get-CimInstance Win32_OperatingSystem).LastBootUpTime)"
Section 'restart pending markers'
"RebootRequired: $(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')   CBS RebootPending: $(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')"
Section 'what is under Policies now'
Show (Get-ChildItem HKLM:\SOFTWARE\Policies\Microsoft -Recurse -ErrorAction SilentlyContinue | Where-Object ValueCount -gt 0 | Select-Object -First 8 -ExpandProperty Name)

$k = 'HKLM:\SOFTWARE\Policies\WinLabDemo'
Section 'a direct registry write, then gpupdate'
New-Item -Path $k -Force | Out-Null
New-ItemProperty -Path $k -Name Setting -Value 1 -PropertyType DWord -Force | Out-Null
gpupdate.exe /force
"value after gpupdate: $((Get-ItemProperty $k -ErrorAction SilentlyContinue).Setting)"
Section 'gpresult /r (computer part)'
gpresult.exe /r /scope computer
Section 'does gpresult mention the demo key?'
gpresult.exe /h C:\Windows\Temp\gp.html /f | Out-Null
"report written: $(Test-Path C:\Windows\Temp\gp.html)   mentions WinLabDemo: $([bool](Select-String -Path C:\Windows\Temp\gp.html -Pattern 'WinLabDemo' -Quiet))"
Section 'gpresult for another scope without elevation context'
gpresult.exe /r /scope user 2>&1 | Select-Object -First 6

Section 'export, change, import: what comes back'
reg.exe export HKLM\SOFTWARE\Policies\WinLabDemo C:\Windows\Temp\before.reg /y
Get-Content C:\Windows\Temp\before.reg
Set-ItemProperty -Path $k -Name Setting -Value 0
New-ItemProperty -Path $k -Name AddedLater -Value 'oops' -PropertyType String -Force | Out-Null
"changed: Setting=$((Get-ItemProperty $k).Setting) AddedLater=$((Get-ItemProperty $k).AddedLater)"
reg.exe import C:\Windows\Temp\before.reg
"after import: Setting=$((Get-ItemProperty $k).Setting) AddedLater=$((Get-ItemProperty $k).AddedLater)"
Section 'delete the key, then import: exact restore'
Remove-Item $k -Recurse
reg.exe import C:\Windows\Temp\before.reg
Show (Get-ItemProperty $k | Select-Object * -ExcludeProperty PS* | Format-List)
Section 'absent, zero and one are three states'
foreach ($state in 'absent', 'zero', 'one') {
    Remove-ItemProperty -Path $k -Name Setting -ErrorAction SilentlyContinue
    if ($state -eq 'zero') { New-ItemProperty -Path $k -Name Setting -Value 0 -PropertyType DWord | Out-Null }
    if ($state -eq 'one') { New-ItemProperty -Path $k -Name Setting -Value 1 -PropertyType DWord | Out-Null }
    $v = (Get-ItemProperty $k -ErrorAction SilentlyContinue).Setting
    "$state : value=[$v]  (-eq 0: $($v -eq 0))  (-not value: $(-not $v))  exists: $((Get-Item $k).GetValueNames() -contains 'Setting')"
}
Remove-Item $k -Recurse -Force
Remove-Item C:\Windows\Temp\before.reg, C:\Windows\Temp\gp.html -ErrorAction SilentlyContinue
"demo key removed: $(-not (Test-Path $k))"
