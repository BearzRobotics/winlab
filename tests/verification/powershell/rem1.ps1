'edition: ' + $PSVersionTable.PSEdition
'elevated: ' + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
'--- Test-WSMan'
try { $t = Test-WSMan localhost -ErrorAction Stop; 'ProductVersion: ' + $t.ProductVersion } catch { 'Test-WSMan failed: ' + $_.Exception.Message.Split("`n")[0] }
'--- Invoke-Command to localhost (default endpoint, current credentials)'
try { Invoke-Command -ComputerName localhost -ScriptBlock { 'ran on ' + $env:COMPUTERNAME + ' as ' + [Environment]::UserName } -ErrorAction Stop }
catch { 'Invoke-Command failed: ' + ($_.Exception.Message -split "`n")[0].Substring(0, [Math]::Min(230, ($_.Exception.Message -split "`n")[0].Length)) }
'--- session configurations (needs admin)'
try { (Get-PSSessionConfiguration -ErrorAction Stop | ForEach-Object { $_.Name }) -join ',' } catch { 'Get-PSSessionConfiguration: ' + $_.Exception.Message.Split("`n")[0] }
'--- TrustedHosts'
try { 'TrustedHosts=[' + (Get-Item WSMan:\localhost\Client\TrustedHosts -ErrorAction Stop).Value + ']' } catch { 'TrustedHosts: ' + $_.Exception.Message.Split("`n")[0] }
'--- PSModulePath (first 4)'
($env:PSModulePath -split ';' | Select-Object -First 4) -join "`n  "
'--- Start-Job result in 5.1'
$job = Start-Job { 'job output' }; ($job | Wait-Job | Receive-Job); $job | Remove-Job
'ThreadJob in 5.1: ' + [bool](Get-Command Start-ThreadJob -ErrorAction SilentlyContinue)
'Find-Module in 5.1: ' + [bool](Get-Command Find-Module -ErrorAction SilentlyContinue)
