# Battery for windows-admin.registry-and-filesystems: the ELEVATED parts. Run only in a throwaway lab VM
# (it writes HKLM\SOFTWARE\WinLabDemo and a folder in C:\Windows\Temp).
$ErrorActionPreference = 'Continue'
function Section($t) { "`n=== $t" }
"PowerShell $($PSVersionTable.PSVersion); elevated: $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators'))"
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' | Select-Object ProductName, EditionID, CurrentBuild | Format-List | Out-String
Section 'HKLM test key, export, import'
New-Item 'HKLM:\SOFTWARE\WinLabDemo' | Out-Null
New-ItemProperty 'HKLM:\SOFTWARE\WinLabDemo' -Name Mode -Value 'old' | Out-Null
cmd.exe /d /c 'reg export HKLM\SOFTWARE\WinLabDemo C:\Windows\Temp\wl.reg /y'
Set-ItemProperty 'HKLM:\SOFTWARE\WinLabDemo' -Name Mode -Value 'new'
cmd.exe /d /c 'reg import C:\Windows\Temp\wl.reg 2>&1'
"Mode after import: $((Get-ItemProperty 'HKLM:\SOFTWARE\WinLabDemo').Mode)"
Section 'delete confirmation'
Remove-Item 'HKLM:\SOFTWARE\WinLabDemo' -Recurse -WhatIf
Remove-Item 'HKLM:\SOFTWARE\WinLabDemo' -Recurse
"exists after: $(Test-Path HKLM:\SOFTWARE\WinLabDemo)"
Remove-Item C:\Windows\Temp\wl.reg
Section 'Policies keys present'
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies' | ForEach-Object PSChildName
Section 'chkdsk with no switches (read only)'
chkdsk.exe C: 2>&1 | Where-Object { $_.Trim() -and $_ -notmatch 'percent' } ; "exit $LASTEXITCODE"
Section 'Repair-Volume -Scan'
Repair-Volume -DriveLetter C -Scan
Section 'fsutil volume diskfree'
fsutil.exe volume diskfree C:
Section 'volumes and partitions'
Get-Volume | Format-Table DriveLetter, FileSystemType, DriveType, HealthStatus, @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}}, @{n='FreeGB';e={[math]::Round($_.SizeRemaining/1GB,1)}} -AutoSize | Out-String
Get-Partition | Format-Table DiskNumber, PartitionNumber, DriveLetter, Type, @{n='SizeGB';e={[math]::Round($_.Size/1GB,2)}} -AutoSize | Out-String
Section 'where the space is: top folders of C:\'
Get-ChildItem C:\ -Directory -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.LinkType } | ForEach-Object {
    $errs = $null
    $sum = (Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue -ErrorVariable errs | Measure-Object Length -Sum).Sum
    [pscustomobject]@{ Folder = $_.Name; GB = [math]::Round($sum / 1GB, 2); Unreadable = @($errs).Count }
} | Sort-Object GB -Descending | Select-Object -First 8 | Format-Table -AutoSize | Out-String
Section 'junctions Windows itself has at the root'
Get-ChildItem C:\ -Force -ErrorAction SilentlyContinue | Where-Object LinkType | Format-Table Mode, LinkType, Name, Target -AutoSize | Out-String -Width 160
Section 'done'
