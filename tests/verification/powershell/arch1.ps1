# Battery for foundations.architecture. Reads only. Writes two small temp files and removes them.
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\verification\powershell\arch1.ps1
$ErrorActionPreference = 'Continue'
function Section($t) { "`n=== $t" }

Section 'version'; "$($PSVersionTable.PSVersion)"; cmd.exe /c ver

Section 'driverquery header and count'
$table = driverquery.exe /fo table; $table | Select-Object -First 7
$csv = driverquery.exe /fo csv | ConvertFrom-Csv
"total: $($csv.Count)"
$csv | Group-Object 'Driver Type' | Format-Table Name, Count -AutoSize | Out-String
Section 'driverquery verbose columns'
$v = driverquery.exe /v /fo csv | ConvertFrom-Csv
($v | Get-Member -MemberType NoteProperty).Name -join ' | '
$v | Group-Object State | Format-Table Name, Count -AutoSize | Out-String
$v | Group-Object 'Start Mode' | Format-Table Name, Count -AutoSize | Out-String
$v | Where-Object 'Module Name' -in 'Ntfs', 'disk' | Format-List 'Module Name', 'Display Name', 'Driver Type', 'Start Mode', State, Status, 'Link Date', Path | Out-String
Section 'driverquery signed info'
$si = driverquery.exe /si /fo csv | ConvertFrom-Csv
"rows $($si.Count)"; $si | Group-Object IsSigned | Format-Table Name, Count -AutoSize | Out-String
Section 'newest link dates'
$csv | Sort-Object { [datetime]$_.'Link Date' } -Descending -ErrorAction SilentlyContinue | Select-Object -First 5 'Module Name', 'Display Name', 'Link Date' | Format-Table -AutoSize | Out-String
Section 'running kernel drivers (CIM)'
"running: $(@(Get-CimInstance Win32_SystemDriver | Where-Object State -eq 'Running').Count) of $(@(Get-CimInstance Win32_SystemDriver).Count)"

Section 'System process'
Get-Process -Id 0, 4 | Format-Table Id, ProcessName, SessionId -AutoSize | Out-String
"path of 4: [$((Get-Process -Id 4).Path)]"

Section 'DLLs between a program and the kernel, in this PowerShell'
(Get-Process -Id $PID).Modules | Where-Object ModuleName -in 'ntdll.dll', 'KERNEL32.DLL', 'KERNELBASE.dll' | Format-Table ModuleName, FileName -AutoSize | Out-String
"modules loaded: $(@((Get-Process -Id $PID).Modules).Count)"

Section 'user time against kernel (privileged) time'
function Measure-Split([string]$Label, [scriptblock]$Work) {
    $me = Get-Process -Id $PID; $u = $me.UserProcessorTime; $k = $me.PrivilegedProcessorTime
    & $Work
    $me.Refresh()
    "{0,-34} user {1,6:N0} ms   kernel {2,6:N0} ms" -f $Label, ($me.UserProcessorTime - $u).TotalMilliseconds, ($me.PrivilegedProcessorTime - $k).TotalMilliseconds
}
$f = Join-Path $env:TEMP "wl-arch-$PID.bin"
foreach ($run in 1..2) {
    Measure-Split 'arithmetic only (3 million adds)' { $x = 0; for ($i = 0; $i -lt 3000000; $i++) { $x += $i } }
    Measure-Split 'file: 20000 small writes to disk' {
        $s = New-Object System.IO.FileStream -ArgumentList $f, ([IO.FileMode]::Create), ([IO.FileAccess]::Write), ([IO.FileShare]::None), 1, ([IO.FileOptions]::WriteThrough) -ErrorAction Stop
        $b = New-Object byte[] 16
        for ($i = 0; $i -lt 20000; $i++) { $s.Write($b, 0, 16) }; $s.Dispose() }
}
Remove-Item $f -ErrorAction SilentlyContinue

Section 'processes by kernel time'
Get-Process | Where-Object { $_.TotalProcessorTime } | Sort-Object PrivilegedProcessorTime -Descending | Select-Object -First 5 ProcessName, @{n='UserSec';e={[int]$_.UserProcessorTime.TotalSeconds}}, @{n='KernelSec';e={[int]$_.PrivilegedProcessorTime.TotalSeconds}} | Format-Table -AutoSize | Out-String

Section 'threads, handles, memory of two notepad-like processes'
$a = Start-Process cmd.exe -ArgumentList '/k' -WindowStyle Hidden -PassThru
$b = Start-Process cmd.exe -ArgumentList '/k' -WindowStyle Hidden -PassThru
Start-Sleep 2
Get-Process -Id $a.Id, $b.Id | Format-Table Id, ProcessName, @{n='Threads';e={$_.Threads.Count}}, HandleCount, @{n='PrivateMB';e={[math]::Round($_.PrivateMemorySize64/1MB,1)}}, Path -AutoSize | Out-String -Width 200
Stop-Process -Id $a.Id, $b.Id

Section 'parent chain of this process'
$id = $PID
while ($id) {
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$id"; if (-not $p) { "  parent $id has exited"; break }
    "  $($p.Name) pid $($p.ProcessId) parent $($p.ParentProcessId) session $($p.SessionId)"
    if ($p.ParentProcessId -eq $id) { break }; $id = $p.ParentProcessId
}

Section 'sessions'
Get-Process | Group-Object SessionId | Sort-Object { [int]$_.Name } | Format-Table @{n='Session';e={$_.Name}}, Count -AutoSize | Out-String
quser.exe 2>&1 | Select-Object -First 1

Section 'svchost and its services'
$svc = Get-CimInstance Win32_Service | Where-Object State -eq 'Running'
"running services $($svc.Count), distinct processes $(@($svc.ProcessId | Sort-Object -Unique).Count)"
$svc | Where-Object Name -in 'Spooler', 'Dhcp', 'Dnscache', 'EventLog' | Format-Table Name, ProcessId, StartName, @{n='Program';e={$_.PathName}} -AutoSize | Out-String -Width 220
tasklist.exe /svc /fi "services eq Spooler"

Section 'accounts of services'
$svc | Group-Object StartName | Sort-Object Count -Descending | Format-Table Name, Count -AutoSize | Out-String

Section 'bug check and app crash events (counts only)'
"BugCheck 1001 in System: $(@(Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-WER-SystemErrorReporting';Id=1001} -ErrorAction SilentlyContinue).Count)"
"Application Error 1000: $(@(Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='Application Error';Id=1000} -ErrorAction SilentlyContinue).Count)"
"Minidump folder exists: $(Test-Path $env:SystemRoot\Minidump)"

Section 'whoami groups with integrity label'
whoami.exe /groups /fo csv | ConvertFrom-Csv | Where-Object { $_.SID -like 'S-1-16-*' -or $_.SID -eq 'S-1-5-32-544' } | Format-List 'Group Name', SID, Attributes | Out-String
Section 'done'
