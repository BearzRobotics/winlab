'edition: ' + $PSVersionTable.PSEdition + ' ' + $PSVersionTable.PSVersion
'--- PSModulePath'
$env:PSModulePath.Split([IO.Path]::PathSeparator) | ForEach-Object { '  ' + $_ }
'--- build a module'
$root = Join-Path ([IO.Path]::GetTempPath()) 'wl-mods'
Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
$mdir = Join-Path $root 'WlTools\1.0.0'
New-Item -ItemType Directory $mdir -Force | Out-Null
Set-Content (Join-Path $mdir 'WlTools.psm1') @'
$script:Greeting = 'Hello'
function Get-Hidden { 'private helper' }
function Get-Greeting {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Name)
    "$script:Greeting, $Name (helper says: $(Get-Hidden))"
}
function Set-Greeting { param([string]$Text) $script:Greeting = $Text }
Export-ModuleMember -Function Get-Greeting, Set-Greeting
'@
New-ModuleManifest -Path (Join-Path $mdir 'WlTools.psd1') -RootModule 'WlTools.psm1' -ModuleVersion '1.0.0' -FunctionsToExport 'Get-Greeting','Set-Greeting' -Author 'student' -Description 'demo'
$env:PSModulePath = $root + [IO.Path]::PathSeparator + $env:PSModulePath
'available: ' + (Get-Module WlTools -ListAvailable | ForEach-Object { "$($_.Name) $($_.Version)" })
'before import, command found by auto-load: ' + [bool](Get-Command Get-Greeting -ErrorAction SilentlyContinue)
'loaded now? ' + [bool](Get-Module WlTools)
Get-Greeting -Name Ada
'loaded after autoload: ' + [bool](Get-Module WlTools)
'exported: ' + ((Get-Module WlTools).ExportedFunctions.Keys -join ',')
'private visible outside? ' + [bool](Get-Command Get-Hidden -ErrorAction SilentlyContinue)
Set-Greeting 'Hi'; Get-Greeting -Name Bob
Remove-Module WlTools
'after Remove-Module: ' + [bool](Get-Command Get-Greeting -ErrorAction SilentlyContinue) + ' (auto-load will bring it back on next call)'
'--- side by side versions'
$m2 = Join-Path $root 'WlTools\2.0.0'; New-Item -ItemType Directory $m2 -Force | Out-Null
Copy-Item "$mdir\WlTools.psm1" $m2
New-ModuleManifest -Path (Join-Path $m2 'WlTools.psd1') -RootModule 'WlTools.psm1' -ModuleVersion '2.0.0' -FunctionsToExport 'Get-Greeting','Set-Greeting'
(Get-Module WlTools -ListAvailable | ForEach-Object { $_.Version.ToString() }) -join ','
Import-Module WlTools -RequiredVersion 1.0.0 -Force
'imported: ' + (Get-Module WlTools).Version
'--- jobs and serialization'
$job = Start-Job { [pscustomobject]@{ N = 5; Date = Get-Date '2026-11-21' } }
$res = $job | Wait-Job | Receive-Job
'job result type: ' + $res.GetType().Name + '; N=' + $res.N + '; has PSComputerName: ' + [bool]$res.PSComputerName
$job | Remove-Job
$proc = Start-Job { Get-Process -Id $PID }
$p = $proc | Wait-Job | Receive-Job
'deserialized process type: ' + $p.GetType().FullName + '; Kill() method present: ' + [bool]($p | Get-Member -Name Kill -MemberType Method)
$proc | Remove-Job
'ThreadJob available: ' + [bool](Get-Command Start-ThreadJob -ErrorAction SilentlyContinue)
'--- signature on a Microsoft file'
$f = (Get-Module Microsoft.PowerShell.Utility -ListAvailable | Select-Object -First 1).Path
if ($f -and (Get-Command Get-AuthenticodeSignature -ErrorAction SilentlyContinue)) { $s = Get-AuthenticodeSignature $f; 'signature status: ' + $s.Status + ' signer: ' + ($s.SignerCertificate.Subject -split ',')[0] } else { 'Get-AuthenticodeSignature not available here' }
'--- SecureString and credential'
$ss = ConvertTo-SecureString 'p@ss' -AsPlainText -Force
'securestring type: ' + $ss.GetType().Name + ' length=' + $ss.Length
$cred = [pscredential]::new('user', $ss)
'credential user=' + $cred.UserName + ' ; password shown as: ' + $cred.Password
'plain via GetNetworkCredential (avoid): ' + $cred.GetNetworkCredential().Password
'--- remoting prerequisites'
if (Get-Command Test-WSMan -ErrorAction SilentlyContinue) { try { Test-WSMan localhost -ErrorAction Stop | Out-Null; 'WinRM answers on localhost' } catch { 'WinRM not available on localhost: ' + $_.Exception.Message.Split("`n")[0] } } else { 'Test-WSMan not present on this platform' }
'WinRM service: ' + $(if (Get-Command Get-Service -ErrorAction SilentlyContinue) { (Get-Service WinRM -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Status) / $($_.StartType)" }) } else { 'n/a' })
'--- Find-Module available (needs network, not run)'
[bool](Get-Command Find-Module -ErrorAction SilentlyContinue)
[bool](Get-Command Find-PSResource -ErrorAction SilentlyContinue)
Remove-Item $root -Recurse -Force
