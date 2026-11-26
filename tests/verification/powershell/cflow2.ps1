# Battery 2 for foundations.powershell-control-flow. Writes only temp files it removes. Run in 5.1 and 7.
$work = Join-Path $env:TEMP "wl-cf-$PID"; New-Item -ItemType Directory $work | Out-Null
function Section($t) { "`n=== $t" }
try {
    "PowerShell $($PSVersionTable.PSVersion)"
    Section 'break in switch over a collection stops the WHOLE switch'
    switch (1, 2, 3, 4) { 2 { 'two: break'; break } default { "saw $_" } }
    Section 'continue goes to the next input'
    switch (1, 2, 3, 4) { 2 { 'two: continue'; continue } default { "saw $_" } }
    Section 'switch on null and on an empty array'
    $r = switch ($null) { default { 'default ran for $null' } }; "null: [$r]"
    $r = switch (@()) { default { 'default ran for @()' } }; "empty array: [$r]"
    Section 'switch -File'
    Set-Content "$work\x.log" 'INFO start', 'ERROR disk full', 'WARN slow', 'ERROR timeout'
    $errors = 0; switch -Regex -File "$work\x.log" { '^ERROR (.+)' { $errors++; "error: $($Matches[1])" } '^WARN' { 'warning' } }; "errors: $errors"

    Section 'order of work: foreach statement collects first'
    function Get-Slowly { foreach ($i in 1..3) { Write-Host "  produced $i"; $i } }
    foreach ($x in Get-Slowly) { Write-Host "  handled $x" }
    Section 'order of work: ForEach-Object streams'
    Get-Slowly | ForEach-Object { Write-Host "  handled $_" }
    Section 'Select-Object -First stops the producer'
    Get-Slowly | Select-Object -First 1 | ForEach-Object { Write-Host "  got $_" }

    Section 'break inside ForEach-Object, no enclosing loop (runs in a child script so we can see what survives)'
    Set-Content "$work\b1.ps1" '"before"', '1..4 | ForEach-Object { if ($_ -eq 2) { break }; "item $_" }', '"AFTER the pipeline"'
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File "$work\b1.ps1"
    Section 'break inside ForEach-Object inside a for loop'
    Set-Content "$work\b2.ps1" 'foreach ($round in 1..3) { "round $round"; 1..4 | ForEach-Object { if ($_ -eq 2) { break }; "  item $_" }; "  end of round $round" }', '"after the loop"'
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File "$work\b2.ps1"

    Section 'speed: 200000 items'
    $data = 1..200000
    $a = (Measure-Command { $s = 0; foreach ($d in $data) { $s += $d } }).TotalMilliseconds
    $b = (Measure-Command { $script:s2 = 0; $data | ForEach-Object { $script:s2 += $_ } }).TotalMilliseconds
    "foreach statement: {0:N0} ms    ForEach-Object: {1:N0} ms" -f $a, $b

    Section 'for loop off by one on an array'
    $arr = 'a', 'b', 'c'
    for ($i = 0; $i -le $arr.Count; $i++) { "i=$i value=[$($arr[$i])]" }
    Section 'foreach over a single string and over a hashtable'
    foreach ($c in 'abc') { "item: $c" }
    $h = [ordered]@{ a = 1; b = 2 }
    foreach ($x in $h) { "foreach over a hashtable gives one item of type $($x.GetType().Name)" }
    foreach ($k in $h.Keys) { "$k = $($h[$k])" }
}
finally { Remove-Item $work -Recurse -Force }
