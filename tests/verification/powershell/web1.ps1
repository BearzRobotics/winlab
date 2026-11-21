$b = 'http://localhost:8766'
'edition: ' + $PSVersionTable.PSEdition
'--- Invoke-RestMethod parses JSON'
$r = Invoke-RestMethod "$b/json"
$r.GetType().Name + ' name=' + $r.name + ' items=' + ($r.items -join ',') + ' when type=' + $r.when.GetType().Name
'--- Invoke-WebRequest gives a response object'
$w = Invoke-WebRequest "$b/json" -UseBasicParsing
$w.StatusCode.ToString() + ' ' + $w.Headers['Content-Type'] + ' content-length=' + $w.RawContentLength
'content is: ' + $w.Content.GetType().Name
'--- 404 behaviour'
try { Invoke-WebRequest "$b/missing" -UseBasicParsing -ErrorAction Stop | Out-Null; 'no error?' } catch { 'caught: ' + $_.Exception.GetType().Name + ' status=' + [int]$_.Exception.Response.StatusCode }
'--- POST JSON with a header'
$body = @{ id = 7; tags = @('a','b') } | ConvertTo-Json -Compress
$e = Invoke-RestMethod "$b/echo" -Method Post -Body $body -ContentType 'application/json' -Headers @{ 'X-Token' = 'abc123' }
'echo: method=' + $e.method + ' auth=' + $e.auth + ' body.id=' + $e.body.id + ' tags=' + ($e.body.tags -join ',')
'--- download to a file'
$out = Join-Path ([IO.Path]::GetTempPath()) 'wl-dl.txt'
Invoke-WebRequest "$b/file" -OutFile $out -UseBasicParsing
(Get-Content $out) -join '|'
Remove-Item $out
if ($PSVersionTable.PSEdition -eq 'Core') {
  '--- 7 only: -SkipHttpErrorCheck'
  $x = Invoke-WebRequest "$b/missing" -SkipHttpErrorCheck
  'status without exception: ' + [int]$x.StatusCode
}
'--- TLS setting (5.1)'
if ($PSVersionTable.PSEdition -eq 'Desktop') { [Net.ServicePointManager]::SecurityProtocol.ToString() }
