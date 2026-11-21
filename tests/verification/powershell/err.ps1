'--- non-terminating continues'
Get-Item 'C:\nope1','C:\Windows' -ErrorAction Continue 2>&1 | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { 'ERR: ' + $_.Exception.Message } else { 'OK: ' + $_.Name } }
'--- try/catch needs terminating'
try { Get-Item 'C:\nope' } catch { 'caught A' }; 'after A (not caught, continued)'
try { Get-Item 'C:\nope' -ErrorAction Stop } catch { 'caught B: ' + $_.Exception.GetType().Name }
'--- error record anatomy'
try { Get-Item 'C:\nope' -ErrorAction Stop } catch {
  'message : ' + $_.Exception.Message
  'category: ' + $_.CategoryInfo.Category
  'target  : ' + $_.TargetObject
  'fqid    : ' + $_.FullyQualifiedErrorId
  'line    : ' + $_.InvocationInfo.ScriptLineNumber
}
'--- typed catch order'
try { [int]'x' } catch [System.Management.Automation.RuntimeException] { 'runtime-exception' } catch { 'other' }
try { Get-Content 'C:\nope.txt' -ErrorAction Stop } catch [System.Management.Automation.ItemNotFoundException] { 'not-found' } catch { 'other: ' + $_.Exception.GetType().FullName }
try { 1/0 } catch [System.DivideByZeroException] { 'div-zero' } catch { 'other: ' + $_.Exception.GetType().Name }
'--- finally always runs'
function T { try { 'in try'; return 'ret' } finally { 'finally ran' } }
T
'--- throw vs Write-Error'
function ThrowIt { throw 'boom' }
try { ThrowIt } catch { 'caught throw: ' + $_.Exception.Message }
function WriteErr { [CmdletBinding()] param() Write-Error 'soft error'; 'continued after Write-Error' }
WriteErr 2>&1 | ForEach-Object { "$_" }
try { WriteErr -ErrorAction Stop } catch { 'caught with Stop: ' + $_.Exception.Message }
'--- ErrorActionPreference'
$ErrorActionPreference = 'Stop'
try { Get-Item 'C:\nope'; 'not reached' } catch { 'global Stop caught' }
$ErrorActionPreference = 'Continue'
'--- SilentlyContinue vs Ignore and $Error'
$Error.Clear()
Get-Item 'C:\nope' -ErrorAction SilentlyContinue; 'silent: errors recorded = ' + $Error.Count
$Error.Clear()
Get-Item 'C:\nope' -ErrorAction Ignore; 'ignore: errors recorded = ' + $Error.Count
'--- ErrorVariable'
Get-Item 'C:\nope' -ErrorAction SilentlyContinue -ErrorVariable ev; 'ev count=' + $ev.Count + ' msg=' + $ev[0].Exception.Message
'--- $? and native exit codes'
cmd /c exit 5; '$LASTEXITCODE=' + $LASTEXITCODE + '  $?=' + $?
cmd /c exit 0; '$LASTEXITCODE=' + $LASTEXITCODE + '  $?=' + $?
Get-Item 'C:\nope' -ErrorAction SilentlyContinue; '$? after failed cmdlet=' + $?
'--- native stderr is not an error record by default'
cmd /c "echo to-stderr 1>&2" 2>&1 | ForEach-Object { $_.GetType().Name + ': ' + $_ }
'--- StrictMode'
try { Set-StrictMode -Version Latest; $undefined + 1 } catch { 'strict: ' + $_.Exception.Message } finally { Set-StrictMode -Off }
'--- streams'
function Streams { Write-Output 'out'; Write-Warning 'warn'; Write-Verbose 'verb' -Verbose; Write-Information 'info' -InformationAction Continue; Write-Debug 'dbg' -Debug:$false }
Streams 3>&1 4>&1 6>&1 | ForEach-Object { $_.GetType().Name + ': ' + $_ }
'--- throw in script gives exit code'
$s = Join-Path $env:TEMP 'wl-ps-demo\thr.ps1'; Set-Content $s 'throw "script failed"'
pwsh -NoProfile -File $s 2>$null; 'exit after throw (-File) = ' + $LASTEXITCODE
Set-Content $s 'try { Get-Item C:\nope -ErrorAction Stop } catch { Write-Error $_; exit 4 }'
pwsh -NoProfile -File $s 2>$null; 'exit after explicit exit 4 = ' + $LASTEXITCODE
'--- Pester available?'
(Get-Module Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1 | ForEach-Object { 'Pester ' + $_.Version })
'--- PSScriptAnalyzer available?'
[bool](Get-Module PSScriptAnalyzer -ListAvailable)
