$limit = 3; $name = 'Ada'
'--- without $using: the job cannot see local variables'
$j1 = Start-Job { "limit inside job = [$limit]" }; ($j1 | Wait-Job | Receive-Job); $j1 | Remove-Job
'--- with $using:'
$j2 = Start-Job { "limit inside job = [$using:limit] name=[$using:name]" }; ($j2 | Wait-Job | Receive-Job); $j2 | Remove-Job
'--- with -ArgumentList and param'
$j3 = Start-Job -ScriptBlock { param($a, $b) "args: $a $b" } -ArgumentList 'x', 7; ($j3 | Wait-Job | Receive-Job); $j3 | Remove-Job
'--- job state, errors and output streams'
$j4 = Start-Job { Write-Output 'out'; Write-Warning 'warn'; Get-Item C:\nope-nope -ErrorAction Stop }
$j4 | Wait-Job | Out-Null
'state=' + $j4.State + ' HasMoreData=' + $j4.HasMoreData
$r = Receive-Job $j4 -ErrorAction SilentlyContinue -ErrorVariable je -WarningVariable jw
'output=' + ($r -join ',') + ' ; warnings=' + ($jw -join ',') + ' ; error=' + ($je[0].Exception.Message -split "`n")[0]
$j4 | Remove-Job
'--- job in a different working directory'
$here = (Get-Location).Path
$j5 = Start-Job { (Get-Location).Path }; $loc = $j5 | Wait-Job | Receive-Job; $j5 | Remove-Job
'job cwd same as caller? ' + ($loc -eq $here) + ' (job: ' + $loc + ')'
'--- ThreadJob shares process, Job does not'
if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) {
  $tj = Start-ThreadJob { $PID }; $pidT = $tj | Wait-Job | Receive-Job; $tj | Remove-Job
  $pj = Start-Job { $PID }; $pidJ = $pj | Wait-Job | Receive-Job; $pj | Remove-Job
  'caller PID=' + $PID + ' ThreadJob PID=' + $pidT + ' Job PID=' + $pidJ
}
