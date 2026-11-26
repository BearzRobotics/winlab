# Battery for foundations.ps-working-with-data: more silent traps. Writes only a temp folder it removes.
$work = Join-Path $env:TEMP "wl-data3-$PID"; New-Item -ItemType Directory $work | Out-Null
function Section($t) { "`n=== $t" }
function Show($x) { ($x | Out-String -Width 100).Trim("`r", "`n") }
try {
    "PowerShell $($PSVersionTable.PSVersion)"
    Section 'Compare-Object on the same lines in a different order'
    $a = 'one', 'two', 'three'; $b = 'three', 'one', 'two'
    $d = @(Compare-Object $a $b); "differences reported: $($d.Count)"
    Section 'with -SyncWindow 0'
    Show (Compare-Object $a $b -SyncWindow 0)
    Section 'Compare-Object ignores case by default'
    "case differences: $(@(Compare-Object 'ABC' 'abc').Count)  with -CaseSensitive: $(@(Compare-Object 'ABC' 'abc' -CaseSensitive).Count)"
    Section 'Compare-Object of objects without -Property'
    $x = [pscustomobject]@{ Name = 'a'; Size = 1 }; $y = [pscustomobject]@{ Name = 'a'; Size = 2 }
    "without -Property: $(@(Compare-Object $x $y).Count) differences   with -Property Name,Size: $(@(Compare-Object $x $y -Property Name, Size).Count)"
    Section 'CSV with a short row and a misspelled column name'
    Set-Content "$work\s.csv" 'Name,Dept,Salary', 'Ann,IT,5000', 'Bo,HR', 'Cy,IT,4000,extra'
    Show (Import-Csv "$work\s.csv" | Format-Table -AutoSize)
    "a misspelled column: [$((Import-Csv "$work\s.csv")[0].Salery)]"
    "sum of Salery: $((Import-Csv "$work\s.csv" | Measure-Object Salery -Sum -ErrorAction SilentlyContinue -ErrorVariable ev).Sum)  errors: $(@($ev).Count)"
    try { Import-Csv "$work\s.csv" | Measure-Object Salery -Sum -ErrorAction Stop } catch { "with Stop: $($_.Exception.Message)" }
    Section 'CSV with a repeated header'
    Set-Content "$work\d.csv" 'Name,Name', 'a,b'
    try { Import-Csv "$work\d.csv" -ErrorAction Stop } catch { "repeated header: $($_.Exception.Message)" }
    Section 'numbers sorted as text and as numbers'
    "text: $((('100', '9', '25') | Sort-Object) -join ' ')   numeric: $((('100', '9', '25') | Sort-Object { [int]$_ }) -join ' ')"
    Section 'Select-String result at the prompt'
    Set-Content "$work\app.log" 'start', 'ERROR disk full code=507', 'ok', 'ERROR timeout code=408'
    Push-Location $work; try { Show (Select-String -Path app.log -Pattern 'ERROR') } finally { Pop-Location }
    Section 'Group-Object table'
    Show ('IT', 'HR', 'IT', 'IT' | Group-Object)
    Section 'Get-Content then Set-Content on the same file'
    Set-Content "$work\same.txt" 'keep me', 'and me'
    try { Get-Content "$work\same.txt" -ErrorAction Stop | Set-Content "$work\same.txt" -ErrorAction Stop; "no error" } catch { "error: $($_.Exception.Message.Replace($work,'<work>'))" }
    "after: $((Get-Content "$work\same.txt") -join ' / ')"
    (Get-Content "$work\same.txt") | Set-Content "$work\same.txt"; "with parentheses: $((Get-Content "$work\same.txt") -join ' / ')"
    Set-Content "$work\clob.txt" 'important'; try { Get-Content "$work\clob.txt" | Out-File "$work\clob.txt" -ErrorAction Stop } catch { "Out-File same file: error" }; "clob after Out-File: [$((Get-Content "$work\clob.txt") -join ' / ')]"
}
finally { Remove-Item $work -Recurse -Force }
