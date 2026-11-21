# ps-advanced elevated battery (lab VM, 5.1): script block logging, transcription, module logging.
$k = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
'-- before: policy key exists?'; Test-Path $k
'-- log enabled by default?'; (Get-WinEvent -ListLog 'Microsoft-Windows-PowerShell/Operational').IsEnabled
New-Item -Path $k -Force | Out-Null
New-ItemProperty -Path $k -Name EnableScriptBlockLogging -Value 1 -PropertyType DWord -Force | Out-Null
$mark = 'WLMARK' + (Get-Random)
# run in a NEW process so policy is read at startup
powershell.exe -NoProfile -Command "`$x = '$mark'; `$secret = 'p@ss-' + `$x; Write-Output done"
Start-Sleep 2
$ev = Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-PowerShell/Operational'; Id=4104 } -MaxEvents 20 | Where-Object { $_.Message -like "*$mark*" }
"events containing marker: $(@($ev).Count)"
$ev | Select-Object -First 1 | ForEach-Object { $_.Id; $_.LevelDisplayName; $_.Message }
'-- obfuscated: encoded command is logged decoded?'
$enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("`$m = '$mark-ENC'; Write-Output `$m"))
powershell.exe -NoProfile -EncodedCommand $enc
Start-Sleep 2
$ev2 = Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-PowerShell/Operational'; Id=4104 } -MaxEvents 20 | Where-Object { $_.Message -like "*$mark-ENC*" }
"decoded text logged: $(@($ev2).Count -gt 0)"
$ev2 | Select-Object -First 1 | ForEach-Object { $_.Message.Substring(0, [math]::Min(200, $_.Message.Length)) }
'-- off again: no new events'
Set-ItemProperty -Path $k -Name EnableScriptBlockLogging -Value 0
$mark2 = 'WLOFF' + (Get-Random)
powershell.exe -NoProfile -Command "Write-Output '$mark2'"
Start-Sleep 2
"events with off-marker: $(@(Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-PowerShell/Operational'; Id=4104 } -MaxEvents 30 | Where-Object { $_.Message -like "*$mark2*" }).Count)"
Remove-Item -Path $k -Recurse
'-- Transcription via Start-Transcript'
$tf = "$env:TEMP\wl-tr.txt"; Start-Transcript -Path $tf | Out-Null; Get-Date -Format yyyy | Out-Null; Stop-Transcript | Out-Null
(Get-Content $tf | Select-Object -First 12) -join "`n"
Remove-Item $tf
'-- default PSVersion table, 7 availability'
$PSVersionTable.PSVersion.ToString(); Test-Path 'C:\Program Files\PowerShell\7\pwsh.exe'; Test-Path C:\pwsh7\pwsh.exe
