'--- platform'
$PSVersionTable.PSVersion.ToString()
$PSVersionTable.PSEdition
$PSVersionTable.OS
"IsLinux=$IsLinux IsWindows=$IsWindows IsMacOS=$IsMacOS"
'--- which common aliases exist'
foreach ($n in 'ls','dir','cat','cp','mv','rm','mkdir','ps','kill','sleep','sort','curl','wget','man','echo','pwd','cd','clear','gci','gc','select','where','foreach','%','?') {
    $a = Get-Alias $n -ErrorAction SilentlyContinue
    $c = Get-Command $n -ErrorAction SilentlyContinue | Select-Object -First 1
    '{0,-8} alias={1,-14} resolves-to={2}' -f $n, $(if ($a) { $a.Definition } else { '-' }), $(if ($c) { "$($c.CommandType): $($c.Source ?? $c.Name)" } else { '-' })
}
'--- total aliases'
(Get-Alias).Count
'--- providers'
(Get-PSProvider).Name -join ','
'--- execution policy'
Get-ExecutionPolicy
'--- paths and env'
[IO.Path]::DirectorySeparatorChar
$env:HOME
$env:USERPROFILE
$HOME
(Get-Location).Path
$env:PATH.Split([IO.Path]::PathSeparator).Count
'--- windows-only cmdlets present?'
foreach ($c in 'Get-Service','Get-EventLog','Get-WinEvent','Get-CimInstance','Get-Process','Get-ChildItem','Get-NetIPAddress','Get-LocalUser','Get-HotFix','Test-NetConnection','Get-Acl') {
    '{0,-20} {1}' -f $c, [bool](Get-Command $c -ErrorAction SilentlyContinue)
}
'--- file system case sensitivity'
$d = Join-Path ([IO.Path]::GetTempPath()) 'wl-case'; New-Item -ItemType Directory $d -Force | Out-Null
Set-Content (Join-Path $d 'A.txt') 'upper'; Set-Content (Join-Path $d 'a.txt') 'lower'
(Get-ChildItem $d).Name -join ','
'--- running native commands and path expressions'
ls -l /etc/os-release | Select-Object -First 1
(uname -s)
'--- line ending / encoding defaults'
[Console]::OutputEncoding.WebName
$PSDefaultParameterValues.Count
'--- Join-Path and separators'
Join-Path 'a' 'b'
'--- shebang script test'
$s = Join-Path $d 'hello.ps1'; Set-Content $s "#!/usr/bin/env pwsh`n'hello from shebang'"; chmod +x $s; & $s
Remove-Item $d -Recurse -Force
