'--- what does a bare name resolve to?'
foreach ($n in 'where','sort','sc','curl','tar','find','ping','more') {
    $all = Get-Command $n -All -ErrorAction SilentlyContinue
    '{0,-6} -> {1}' -f $n, (($all | ForEach-Object { if ($_.CommandType -eq 'Application') { "Application $($_.Source)" } else { "$($_.CommandType) $($_.Definition)" } }) -join ' | ')
}
'--- the same names with .exe'
foreach ($n in 'where.exe','sort.exe','sc.exe','curl.exe','tar.exe','find.exe') {
    $c = Get-Command $n -ErrorAction SilentlyContinue | Select-Object -First 1
    '{0,-10} -> {1}' -f $n, $(if ($c) { "$($c.CommandType) $($c.Source)" } else { 'not found' })
}
'--- where vs where.exe in practice'
'bare "where notepad" in PowerShell:'
try { (where notepad) 2>&1 | Select-Object -First 2 | ForEach-Object { "$_" } } catch { "  " + $_.Exception.Message }
'where.exe notepad:'
where.exe notepad | Select-Object -First 1
'--- sort vs sort.exe on text'
'10','9','100' | sort
'-- sort.exe (text, ordinal):'
'10','9','100' | sort.exe
'--- an alias or function can hijack a bare name'
function find { 'my function find (NOT the program)' }
find /?
find.exe /? 2>&1 | Select-Object -First 1
Remove-Item Function:\find
'--- call by full path with the call operator'
& "$env:SystemRoot\System32\where.exe" cmd | Select-Object -First 1
