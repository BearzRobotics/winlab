# Battery for windows-admin.registry-and-filesystems. Run as a STANDARD user. It writes only to a new folder
# under %TEMP% and to the key HKCU:\Software\WinLabDemo, and removes both. Reads everything else.
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\verification\powershell\regfs1.ps1
$ErrorActionPreference = 'Continue'
function Section($t) { "`n=== $t" }
function Try-It([string]$Label, [scriptblock]$Code) {
    try { $ErrorActionPreference = 'Stop'; $out = & $Code 2>&1 | Out-String; "$Label : OK"; $out.TrimEnd() } catch { "$Label : ERROR: $($_.Exception.Message)" }
}
$demo = 'HKCU:\Software\WinLabDemo'
$work = Join-Path $env:TEMP "wl-regfs-$PID"
if (Test-Path $demo) { throw "$demo already exists; not touching it" }
New-Item -ItemType Directory -Path $work | Out-Null
try {
    "PowerShell $($PSVersionTable.PSVersion); elevated: $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators'))"

    Section 'drives from the registry provider'; Get-PSDrive -PSProvider Registry | Format-Table Name, Root -AutoSize | Out-String
    Section 'read a key: Get-ItemProperty'
    Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' | Select-Object ProductName, EditionID, DisplayVersion, CurrentBuild, UBR | Format-List | Out-String
    Section 'reg query one value'; reg.exe query 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion' /v CurrentBuild; "exit $LASTEXITCODE"
    reg.exe query 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion' /v NoSuchValue 2>&1; "exit $LASTEXITCODE"
    Section 'subkeys vs values'
    "subkeys of HKLM:\SOFTWARE: $(@(Get-ChildItem HKLM:\SOFTWARE).Count)"

    Section 'create a test key and typed values'
    New-Item -Path $demo | Out-Null
    New-ItemProperty -Path $demo -Name Greeting -Value 'hello' -PropertyType String | Out-Null
    New-ItemProperty -Path $demo -Name Retries -Value 3 -PropertyType DWord | Out-Null
    New-ItemProperty -Path $demo -Name Servers -Value 'web01', 'db01' -PropertyType MultiString | Out-Null
    New-ItemProperty -Path $demo -Name LogDir -Value '%TEMP%\logs' -PropertyType ExpandString | Out-Null
    New-ItemProperty -Path $demo -Name LogDirPlain -Value '%TEMP%\logs' -PropertyType String | Out-Null
    Get-ItemProperty $demo | Out-String
    Section 'Get-Item shows names and kinds'
    $k = Get-Item $demo; $k.GetValueNames() | ForEach-Object { '{0,-12} {1,-13} {2}' -f $_, $k.GetValueKind($_), ($k.GetValue($_) -join ' | ') }
    "raw LogDir (not expanded): $($k.GetValue('LogDir', $null, 'DoNotExpandEnvironmentNames'))"
    Section 'reg query of the test key'; reg.exe query 'HKCU\Software\WinLabDemo'
    Section 'one value only'
    "$((Get-ItemProperty $demo -Name Retries).Retries)"
    Get-ItemPropertyValue $demo -Name Retries
    Try-It 'missing value' { Get-ItemPropertyValue $demo -Name Nope }

    Section 'Set-ItemProperty and types'
    Set-ItemProperty -Path $demo -Name Retries -Value 5; "Retries after Set 5: $($k = Get-Item $demo; $k.GetValueKind('Retries')) = $($k.GetValue('Retries'))"
    Set-ItemProperty -Path $demo -Name Retries -Value 'five'; $k = Get-Item $demo; "after Set 'five': $($k.GetValueKind('Retries')) = $($k.GetValue('Retries'))"
    Set-ItemProperty -Path $demo -Name Brand -Value '7'; $k = Get-Item $demo; "new value by Set '7': $($k.GetValueKind('Brand'))"
    Set-ItemProperty -Path $demo -Name Brand -Value 7 -Type DWord; $k = Get-Item $demo; "with -Type DWord: $($k.GetValueKind('Brand'))"
    Remove-ItemProperty -Path $demo -Name Brand, Retries
    New-ItemProperty -Path $demo -Name Retries -Value 3 -PropertyType DWord | Out-Null
    Try-It 'New-ItemProperty on existing without -Force' { New-ItemProperty -Path $demo -Name Retries -Value 9 -PropertyType DWord }
    Section 'New-Item -Force on an existing key'
    New-Item -Path "$demo\Child" | Out-Null; New-ItemProperty "$demo\Child" -Name Keep -Value 1 | Out-Null
    New-Item -Path $demo -Force | Out-Null
    "after New-Item -Force: values=[$((Get-Item $demo).GetValueNames() -join ',')] child exists=$(Test-Path "$demo\Child")"

    Section 'rebuild, export, change, import'
    New-ItemProperty -Path $demo -Name Greeting -Value 'hello' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $demo -Name Retries -Value 3 -PropertyType DWord -Force | Out-Null
    reg.exe export 'HKCU\Software\WinLabDemo' "$work\backup.reg" /y
    '--- backup.reg'; Get-Content "$work\backup.reg"
    "first bytes: $((Get-Content "$work\backup.reg" -Encoding Byte -TotalCount 2) -join ' ')"
    Set-ItemProperty $demo -Name Greeting -Value 'changed'
    New-ItemProperty $demo -Name AddedLater -Value 'still here?' | Out-Null
    reg.exe import "$work\backup.reg" 2>&1
    '--- after import'; Get-ItemProperty $demo | Select-Object Greeting, Retries, AddedLater | Format-List | Out-String

    Section 'writing to HKLM as a standard user'
    Try-It 'New-Item in HKLM' { New-Item -Path 'HKLM:\SOFTWARE\WinLabDemoNoRights' }
    reg.exe add 'HKLM\SOFTWARE\WinLabDemoNoRights' /f 2>&1; "exit $LASTEXITCODE"

    Section '32-bit view'
    "WOW6432Node exists: $(Test-Path HKLM:\SOFTWARE\WOW6432Node)"
    Section 'hive files in use'
    reg.exe query 'HKLM\SYSTEM\CurrentControlSet\Control\hivelist' 2>&1 | ForEach-Object { $_ -replace $env:USERNAME, 'student' -replace 'S-1-5-21-[0-9-]+', 'S-1-5-21-...' }

    Section 'startup: counts only'
    foreach ($p in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce') {
        $n = if (Test-Path $p) { @((Get-Item $p).GetValueNames()).Count } else { 'key missing' }; "$p : $n" }
    "user startup folder: $([Environment]::GetFolderPath('Startup') -replace $env:USERNAME,'student')"
    "all-users startup folder: $([Environment]::GetFolderPath('CommonStartup'))"
    $sc = @(Get-CimInstance Win32_StartupCommand); "Win32_StartupCommand entries: $($sc.Count)"
    $sc | Group-Object { $_.Location -replace 'HKU\\S-1-5-[0-9-]+', 'HKU\<SID>' } | Format-Table Count, Name -AutoSize | Out-String -Width 200
    "services set Automatic: $(@(Get-Service -ErrorAction SilentlyContinue | Where-Object StartType -eq 'Automatic').Count)"
    "scheduled tasks with a logon or boot trigger: $(@(Get-ScheduledTask | Where-Object { $_.Triggers | Where-Object { $_.CimClass.CimClassName -match 'Logon|Boot' } }).Count)"

    Section 'volumes'
    Try-It 'Get-Volume' { Get-Volume | Sort-Object DriveLetter | Format-Table DriveLetter, FileSystemType, DriveType, HealthStatus, @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}}, @{n='FreeGB';e={[math]::Round($_.SizeRemaining/1GB,1)}} -AutoSize }
    Try-It 'Get-PSDrive' { Get-PSDrive C | Format-Table Name, @{n='UsedGB';e={[math]::Round($_.Used/1GB,1)}}, @{n='FreeGB';e={[math]::Round($_.Free/1GB,1)}} -AutoSize }
    Try-It 'Get-Disk' { Get-Disk | Format-Table Number, PartitionStyle, OperationalStatus, @{n='SizeGB';e={[math]::Round($_.Size/1GB)}} -AutoSize }
    Try-It 'Get-Partition' { Get-Partition | Format-Table DiskNumber, PartitionNumber, DriveLetter, Type, @{n='SizeGB';e={[math]::Round($_.Size/1GB,2)}} -AutoSize }
    'fsutil volume diskfree C:'; fsutil.exe volume diskfree C: 2>&1; "exit $LASTEXITCODE"
    'chkdsk (no switches) as standard user'; chkdsk.exe C: 2>&1 | Select-Object -First 6; "exit $LASTEXITCODE"

    Section 'size of each top folder (test tree)'
    $t = "$work\tree"
    New-Item -ItemType Directory "$t\logs", "$t\data\old", "$t\empty" | Out-Null
    [IO.File]::WriteAllBytes("$t\logs\app.log", (New-Object byte[] 3MB))
    [IO.File]::WriteAllBytes("$t\data\db.bak", (New-Object byte[] 5MB))
    [IO.File]::WriteAllBytes("$t\data\old\db-old.bak", (New-Object byte[] 4MB))
    [IO.File]::WriteAllBytes("$t\data\small.txt", (New-Object byte[] 10))
    Get-ChildItem $t -Directory | ForEach-Object {
        $sum = (Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        [pscustomobject]@{ Folder = $_.Name; MB = [math]::Round($sum / 1MB, 1) } } | Sort-Object MB -Descending | Format-Table -AutoSize | Out-String
    Section 'largest files'
    Get-ChildItem $t -Recurse -File -Force | Sort-Object Length -Descending | Select-Object -First 3 @{n='MB';e={[math]::Round($_.Length/1MB,1)}}, @{n='Path';e={$_.FullName.Substring($t.Length)}} | Format-Table -AutoSize | Out-String

    Section 'links as a standard user'
    New-Item -ItemType Directory "$work\target" | Out-Null; Set-Content "$work\target\keep.txt" 'important'
    cmd.exe /d /c "mklink /J `"$work\junction`" `"$work\target`"" 2>&1; "exit $LASTEXITCODE"
    cmd.exe /d /c "mklink /D `"$work\symdir`" `"$work\target`"" 2>&1; "exit $LASTEXITCODE"
    cmd.exe /d /c "mklink /H `"$work\hard.txt`" `"$work\target\keep.txt`"" 2>&1; "exit $LASTEXITCODE"
    Get-ChildItem $work | Format-Table Mode, LinkType, Name -AutoSize | Out-String
    "through the junction: $(Get-Content "$work\junction\keep.txt")"
    Set-Content "$work\hard.txt" 'changed through the hard link'; "target now reads: $(Get-Content "$work\target\keep.txt")"
    fsutil.exe reparsepoint query "$work\junction" 2>&1 | Select-Object -First 3
    Section 'counting through a junction'
    New-Item -ItemType Directory "$work\count\real", "$work\count\view" | Out-Null
    [IO.File]::WriteAllBytes("$work\count\real\one.bin", (New-Object byte[] 1MB))
    cmd.exe /d /c "mklink /J `"$work\count\view\again`" `"$work\count\real`"" | Out-Null
    "files found by -Recurse from count: $(@(Get-ChildItem "$work\count" -Recurse -File).Count)  (real files: 1)"

    Section 'removing a junction: rmdir'
    cmd.exe /d /c "rmdir `"$work\junction`""; "junction exists: $(Test-Path "$work\junction")  target file exists: $(Test-Path "$work\target\keep.txt")"
    Section 'removing a junction: Remove-Item -Recurse -Force on the link itself'
    New-Item -ItemType Directory "$work\t2" | Out-Null; Set-Content "$work\t2\victim.txt" 'x'
    cmd.exe /d /c "mklink /J `"$work\j2`" `"$work\t2`"" | Out-Null
    Try-It 'Remove-Item link' { Remove-Item "$work\j2" -Recurse -Force }
    "link exists: $(Test-Path "$work\j2")  target file exists: $(Test-Path "$work\t2\victim.txt")"
    Section 'removing a PARENT folder that contains a junction'
    New-Item -ItemType Directory "$work\t3", "$work\parent" | Out-Null; Set-Content "$work\t3\victim.txt" 'x'
    cmd.exe /d /c "mklink /J `"$work\parent\j3`" `"$work\t3`"" | Out-Null
    Try-It 'Remove-Item parent' { Remove-Item "$work\parent" -Recurse -Force }
    "parent exists: $(Test-Path "$work\parent")  target file exists: $(Test-Path "$work\t3\victim.txt")"

    Section 'hidden and system attributes'
    New-Item -ItemType Directory "$work\attr" | Out-Null; Set-Content "$work\attr\secret.txt" 'readable'
    attrib.exe +h "$work\attr\secret.txt"
    "Get-ChildItem: $(@(Get-ChildItem "$work\attr").Count)   with -Force: $(@(Get-ChildItem "$work\attr" -Force).Count)"
    "content still readable: $(Get-Content "$work\attr\secret.txt" -Force)"
    attrib.exe "$work\attr\secret.txt" | ForEach-Object { $_.Replace($work, '<work>') }
    Section 'long file larger than FAT32 limit'; 'FAT32 limit not tested (no FAT32 volume)'
}
finally {
    if (Test-Path $demo) { Remove-Item $demo -Recurse -Force }
    # remove links first so nothing is followed
    Get-ChildItem $work -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.LinkType -in 'Junction', 'SymbolicLink' } | ForEach-Object { cmd.exe /d /c "rmdir `"$($_.FullName)`"" }
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    "`ncleaned up: key=$(-not (Test-Path $demo)) folder=$(-not (Test-Path $work))"
}
