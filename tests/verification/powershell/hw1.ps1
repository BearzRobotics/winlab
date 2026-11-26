# Battery for hardware.hardware-concepts. Read-only.
$ErrorActionPreference = 'Continue'
function Section($t) { "`n=== $t" }
function Show($x) { ($x | Out-String -Width 150).Trim("`r", "`n") }
"PowerShell $($PSVersionTable.PSVersion)  $((Get-CimInstance Win32_OperatingSystem).Caption)"
Section 'system'
Show (Get-CimInstance Win32_ComputerSystem | Format-List Manufacturer, Model, NumberOfProcessors, NumberOfLogicalProcessors, @{n = 'MemoryGB'; e = { [math]::Round($_.TotalPhysicalMemory / 1GB, 2) } }, HypervisorPresent)
Section 'processor'
Show (Get-CimInstance Win32_Processor | Format-List Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, LoadPercentage)
Section 'memory modules'
Show (Get-CimInstance Win32_PhysicalMemory | Format-Table DeviceLocator, @{n = 'GB'; e = { $_.Capacity / 1GB } }, Speed, Manufacturer -AutoSize)
Section 'memory in use'
$os = Get-CimInstance Win32_OperatingSystem
"total KB: $($os.TotalVisibleMemorySize)  free KB: $($os.FreePhysicalMemory)"
"free GB: $([math]::Round($os.FreePhysicalMemory / 1MB, 2)) of $([math]::Round($os.TotalVisibleMemorySize / 1MB, 2))"
Show (Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 4 Name, @{n = 'WorkingSetMB'; e = { [int]($_.WorkingSet64 / 1MB) } } | Format-Table -AutoSize)
Section 'physical disks'
Show (Get-PhysicalDisk | Format-Table FriendlyName, MediaType, BusType, HealthStatus, OperationalStatus, @{n = 'GB'; e = { [math]::Round($_.Size / 1GB) } } -AutoSize)
Section 'volumes'
Show (Get-Volume | Format-Table DriveLetter, FileSystemLabel, FileSystem, HealthStatus, @{n = 'FreeGB'; e = { [math]::Round($_.SizeRemaining / 1GB, 1) } }, @{n = 'SizeGB'; e = { [math]::Round($_.Size / 1GB, 1) } } -AutoSize)
Section 'devices with problems'
$bad = @(Get-CimInstance Win32_PnPEntity | Where-Object ConfigManagerErrorCode -ne 0)
"devices with a nonzero error code: $($bad.Count)"
Show ($bad | Select-Object -First 5 Name, ConfigManagerErrorCode | Format-Table -AutoSize)
Section 'disk and unexpected-shutdown events (System log)'
foreach ($f in @(@{ LogName = 'System'; ProviderName = 'disk' }, @{ LogName = 'System'; Id = 41, 6008 })) {
    $e = @(Get-WinEvent -FilterHashtable $f -MaxEvents 5 -ErrorAction SilentlyContinue)
    "$(($f.Keys | Sort-Object | ForEach-Object { "$_=$($f[$_] -join ',')" }) -join ' '): $($e.Count) events"
}
Section 'virtualization'
Show (Get-CimInstance Win32_Processor | Format-List VirtualizationFirmwareEnabled, VMMonitorModeExtensions)
