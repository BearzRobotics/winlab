# Battery for endpoints.protect-devices, part 2. THROWAWAY VM ONLY, elevated: which events record a
# Defender exclusion and a firewall profile being switched off. Puts both back.
$ErrorActionPreference = 'Continue'
"PowerShell $($PSVersionTable.PSVersion)"
$start = Get-Date
New-Item -ItemType Directory C:\wltest -Force | Out-Null
Add-MpPreference -ExclusionPath C:\wltest
Set-NetFirewallProfile -Profile Public -Enabled False
Start-Sleep 15
"`n=== Defender 5007 events since the start that mention Exclusions"
Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Windows Defender/Operational'; Id = 5007; StartTime = $start } -ErrorAction SilentlyContinue |
    ForEach-Object { if ($_.Message -match 'Exclusions') { $_.Message } }
"`n=== all 5007 since the start: $(@(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Windows Defender/Operational'; Id = 5007; StartTime = $start } -ErrorAction SilentlyContinue).Count)"
"`n=== firewall events since the start"
Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Windows Firewall With Advanced Security/Firewall'; StartTime = $start } -ErrorAction SilentlyContinue |
    ForEach-Object { "--- Id $($_.Id)"; $_.Message }
Set-NetFirewallProfile -Profile Public -Enabled True
Remove-MpPreference -ExclusionPath C:\wltest
Remove-Item C:\wltest -Recurse -Force
"`nrestored: Public=$((Get-NetFirewallProfile -Name Public).Enabled) exclusions=[$((Get-MpPreference).ExclusionPath)]"
