$d = Join-Path ([IO.Path]::GetTempPath()) 'wl-data'
Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $d | Out-Null
'edition: ' + $PSVersionTable.PSEdition + ' ' + $PSVersionTable.PSVersion
'--- default encodings and BOM of writers'
function Get-Head([string]$p) { $b = [IO.File]::ReadAllBytes($p); ($b[0..([Math]::Min(3,$b.Length-1))] | ForEach-Object { '{0:X2}' -f $_ }) -join ' ' }
'hi' | Out-File "$d\outfile.txt"
Set-Content "$d\setcontent.txt" 'hi'
'hi' | Add-Content "$d\addcontent.txt"
'hi' > "$d\redirect.txt"
foreach ($n in 'outfile','setcontent','addcontent','redirect') { '{0,-11} bytes: {1}  size={2}' -f $n, (Get-Head "$d\$n.txt"), (Get-Item "$d\$n.txt").Length }
'--- explicit UTF-8 choices'
'hi' | Set-Content "$d\u8.txt" -Encoding UTF8
'hi' | Set-Content "$d\u8nobom.txt" -Encoding $(if ($PSVersionTable.PSEdition -eq 'Core') { 'utf8NoBOM' } else { 'ASCII' })
foreach ($n in 'u8','u8nobom') { '{0,-8} bytes: {1}' -f $n, (Get-Head "$d\$n.txt") }
'--- Get-Content forms'
1..5 | ForEach-Object { "line $_" } | Set-Content "$d\five.txt"
(Get-Content "$d\five.txt" -TotalCount 2) -join '|'
(Get-Content "$d\five.txt" -Tail 2) -join '|'
(Get-Content "$d\five.txt" -Raw).GetType().Name + ' length ' + (Get-Content "$d\five.txt" -Raw).Length
(Get-Content "$d\five.txt").GetType().Name + ' count ' + (Get-Content "$d\five.txt").Count
Set-Content "$d\one.txt" 'x'
'one line file type: ' + (Get-Content "$d\one.txt").GetType().Name
'--- LiteralPath vs Path with brackets'
Set-Content -LiteralPath "$d\data[1].txt" 'bracket'
'-Path    : ' + [bool](Get-Content "$d\data[1].txt" -ErrorAction SilentlyContinue)
'-Literal : ' + [bool](Get-Content -LiteralPath "$d\data[1].txt" -ErrorAction SilentlyContinue)
'--- Select-String'
Set-Content "$d\log.txt" @('2026-11-20 INFO start','2026-11-20 ERROR disk full code=507','2026-11-21 ERROR timeout code=408','2026-11-21 INFO done')
$m = Select-String -Path "$d\log.txt" -Pattern 'ERROR (\w+ \w+|\w+) code=(\d+)'
$m.Count; $m[0].LineNumber; $m[0].Matches[0].Groups[1].Value; $m[1].Matches[0].Groups[2].Value
(Select-String "$d\log.txt" -Pattern 'ERROR' -Context 0,1 | ForEach-Object { $_.Context.PostContext }) -join '|'
(Select-String "$d\log.txt" -Pattern 'INFO' -NotMatch).Count
(Select-String "$d\log.txt" -Pattern 'o' -AllMatches | Select-Object -First 1).Matches.Count
'--- CSV'
@'
Name,Dept,Salary,Start
Ann,IT,5000,2020-01-15
Bob,HR,4200,2019-06-01
Cy,IT,6100,2021-09-30
'@ | Set-Content "$d\emp.csv"
$emp = Import-Csv "$d\emp.csv"
$emp[0].Salary.GetType().Name + ' (Import-Csv values are strings)'
'sum as strings concatenates: ' + ($emp[0].Salary + $emp[2].Salary)
'sum cast: ' + ([int]$emp[0].Salary + [int]$emp[2].Salary)
($emp | Group-Object Dept | ForEach-Object { '{0}: n={1} total={2}' -f $_.Name, $_.Count, ($_.Group | Measure-Object Salary -Sum).Sum }) -join ' ; '
$emp | Select-Object Name, @{n='Annual';e={[int]$_.Salary * 12}}, @{n='Start';e={[datetime]$_.Start}} | Sort-Object Annual -Descending | ForEach-Object { '{0} {1} {2:yyyy-MM-dd}' -f $_.Name, $_.Annual, $_.Start }
$emp | Export-Csv "$d\out.csv" -NoTypeInformation
(Get-Content "$d\out.csv" -TotalCount 2) -join ' // '
$emp | Export-Csv "$d\out2.csv"
'default export first line: ' + (Get-Content "$d\out2.csv" -TotalCount 1)
'semicolon: ' + ((Import-Csv -Delimiter ';' -InputObject $null -ErrorAction SilentlyContinue) -eq $null)
('a;b','1;2' | ConvertFrom-Csv -Delimiter ';' | ForEach-Object { $_.b })
'headerless: ' + (('x,y','z,w' | ConvertFrom-Csv -Header 'First','Second')[1].Second)
'--- JSON'
$obj = [pscustomobject]@{ name='x'; list=@(1,2,3); nested=[pscustomobject]@{ a=[pscustomobject]@{ b=[pscustomobject]@{ c=1 } } }; one=@(5) }
'default depth: ' + ($obj | ConvertTo-Json -Compress)
'depth 5     : ' + ($obj | ConvertTo-Json -Compress -Depth 5)
$j = '{"a":1,"items":[{"n":"x"},{"n":"y"}],"single":[7],"when":"2026-11-21T10:30:00Z"}' | ConvertFrom-Json
$j.items.Count; $j.items.n -join ','; $j.single.GetType().Name; $j.when.GetType().Name
'one-element array roundtrip: ' + ([pscustomobject]@{ x = @(7) } | ConvertTo-Json -Compress)
'array alone with one item: ' + (ConvertTo-Json @(7) -Compress) + ' ; piped: ' + (@(7) | ConvertTo-Json -Compress)
'--- XML'
$x = [xml]'<cfg><server name="a" port="80"/><server name="b" port="8080"/><opt>on</opt></cfg>'
$x.cfg.server.Count; $x.cfg.server[1].port; $x.cfg.opt
(Select-Xml -Xml $x -XPath '//server[@port="8080"]').Node.name
$x.cfg.opt = 'off'; $x.OuterXml
Get-Process -Id $PID | Select-Object Id,ProcessName | Export-Clixml "$d\p.xml"; (Import-Clixml "$d\p.xml").ProcessName
'--- Compare-Object and hashes'
Set-Content "$d\a1.txt" @('a','b','c'); Set-Content "$d\a2.txt" @('a','x','c')
(Compare-Object (Get-Content "$d\a1.txt") (Get-Content "$d\a2.txt") | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join ' | '
(Get-FileHash "$d\a1.txt" -Algorithm SHA256).Hash.Length
'--- ConvertFrom-StringData'
(ConvertFrom-StringData -StringData "a=1`nb=two").b
Remove-Item $d -Recurse -Force
