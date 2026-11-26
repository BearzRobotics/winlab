# Battery for foundations.troubleshooting-method: which events are old noise and which are new. Read-only.
"PowerShell $($PSVersionTable.PSVersion)  $((Get-CimInstance Win32_OperatingSystem).Caption)"
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
"boot: $boot"
$all = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1, 2, 3 }
"critical, error and warning events in System: $($all.Count)"
"=== grouped by source and ID, with first and last time seen"
($all | Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 8 Count, Name,
    @{ n = 'First'; e = { ($_.Group.TimeCreated | Measure-Object -Minimum).Minimum } },
    @{ n = 'Last'; e = { ($_.Group.TimeCreated | Measure-Object -Maximum).Maximum } } | Format-Table -AutoSize | Out-String -Width 150).Trim()
"=== kinds never seen before the last boot"
$new = $all | Group-Object ProviderName, Id | Where-Object { ($_.Group.TimeCreated | Measure-Object -Minimum).Minimum -ge $boot }
($new | Sort-Object Count -Descending | Select-Object -First 6 Count, Name | Format-Table -AutoSize | Out-String -Width 150).Trim()
"=== oldest event kept in the log"
(Get-WinEvent -LogName System -MaxEvents 1 -Oldest).TimeCreated
