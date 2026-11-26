# Battery for windows-admin.registry-and-filesystems: the behaviours that differ or could, in PowerShell 7.
# Writes only a new %TEMP% folder and HKCU:\Software\WinLabDemo7, and removes both.
#   pwsh -NoProfile -File tests\verification\powershell\regfs3.ps1
$work = Join-Path $env:TEMP "wl-regfs3-$PID"; $demo = 'HKCU:\Software\WinLabDemo7'
if (Test-Path $demo) { throw "$demo already exists; not touching it" }
New-Item -ItemType Directory -Path $work | Out-Null
try {
    "PowerShell $($PSVersionTable.PSVersion)"
    New-Item $demo | Out-Null; New-ItemProperty $demo -Name A -Value 1 | Out-Null; New-Item "$demo\Child" | Out-Null
    New-Item $demo -Force | Out-Null
    "after New-Item -Force on an existing key: values=[$((Get-Item $demo).GetValueNames() -join ',')] child=$(Test-Path "$demo\Child")"
    New-Item -ItemType Directory "$work\count\real", "$work\count\view", "$work\t3", "$work\parent" | Out-Null
    [IO.File]::WriteAllBytes("$work\count\real\one.bin", [byte[]]::new(1MB))
    cmd.exe /d /c "mklink /J `"$work\count\view\again`" `"$work\count\real`"" | Out-Null
    "-Recurse file count through a junction: $(@(Get-ChildItem "$work\count" -Recurse -File).Count) (real files: 1)"
    "with -FollowSymlink: $(@(Get-ChildItem "$work\count" -Recurse -File -FollowSymlink).Count)"
    Set-Content "$work\t3\victim.txt" 'x'; cmd.exe /d /c "mklink /J `"$work\parent\j3`" `"$work\t3`"" | Out-Null
    Remove-Item "$work\parent" -Recurse -Force
    "removing a parent that holds a junction: parent=$(Test-Path "$work\parent") target file=$(Test-Path "$work\t3\victim.txt")"
    $dev = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue
    "Developer Mode value AllowDevelopmentWithoutDevLicense: $($dev.AllowDevelopmentWithoutDevLicense)"
}
finally {
    if (Test-Path $demo) { Remove-Item $demo -Recurse -Force }
    Get-ChildItem $work -Recurse -Force | Where-Object LinkType -in 'Junction', 'SymbolicLink' | ForEach-Object { cmd.exe /d /c "rmdir `"$($_.FullName)`"" }
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    "cleaned up: key=$(-not (Test-Path $demo)) folder=$(-not (Test-Path $work))"
}
