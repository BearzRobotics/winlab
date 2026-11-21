$pw = ConvertTo-SecureString $env:WLPW -AsPlainText -Force
$cred = [pscredential]::new("$env:COMPUTERNAME\Administrator", $pw)
$so = New-PSSessionOption -OpenTimeout 20000 -OperationTimeout 20000
'WinRM service: ' + (Get-Service WinRM).Status
'listeners:'; Get-ChildItem WSMan:\localhost\Listener | ForEach-Object { '  ' + $_.Name + ' ' + (($_ | Get-ChildItem | Where-Object { $_.Name -in 'Transport','Port','Address' } | ForEach-Object { $_.Name + '=' + $_.Value }) -join ' ') }
'firewall rules for WinRM (enabled/profile):'; Get-NetFirewallRule -DisplayGroup 'Windows Remote Management' -ErrorAction SilentlyContinue | Select-Object -First 3 | ForEach-Object { '  ' + $_.DisplayName + ' enabled=' + $_.Enabled + ' profile=' + $_.Profile }
'AllowUnencrypted / auth basics:'; '  Negotiate=' + (Get-Item WSMan:\localhost\Service\Auth\Negotiate).Value + ' Kerberos=' + (Get-Item WSMan:\localhost\Service\Auth\Kerberos).Value
foreach ($target in 'localhost', $env:COMPUTERNAME) {
  "--- Invoke-Command -ComputerName $target (credential, 20s timeouts)"
  $sw = [Diagnostics.Stopwatch]::StartNew()
  try { Invoke-Command -ComputerName $target -Credential $cred -SessionOption $so -ScriptBlock { 'ran on ' + $env:COMPUTERNAME + ' as ' + [Environment]::UserName } -ErrorAction Stop }
  catch { 'FAILED after ' + [int]$sw.Elapsed.TotalSeconds + 's: ' + ($_.Exception.Message -split "`n")[0].Substring(0, [Math]::Min(300, ($_.Exception.Message -split "`n")[0].Length)) }
}
