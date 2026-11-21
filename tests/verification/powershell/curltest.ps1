'edition: ' + $PSVersionTable.PSEdition
$c = Get-Command curl | Select-Object -First 1
'curl resolves to: ' + $c.CommandType + ' ' + $(if ($c.CommandType -eq 'Alias') { $c.Definition } else { $c.Source })
$r = curl http://localhost:8765/
'type returned by bare curl: ' + $r.GetType().Name
if ($r -isnot [string] -and $r -isnot [object[]]) { 'StatusCode=' + $r.StatusCode + ' Content=' + $r.Content }
else { 'printed: ' + ($r -join ' ') }
$e = curl.exe -s http://localhost:8765/
'curl.exe -s printed: ' + $e + '  (type ' + $e.GetType().Name + ', exit ' + $LASTEXITCODE + ')'
$w = Invoke-WebRequest http://localhost:8765/ -UseBasicParsing
'Invoke-WebRequest: StatusCode=' + $w.StatusCode + ' Content=' + $w.Content
