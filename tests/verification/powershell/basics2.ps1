# Battery 2 for foundations.powershell-basics: how to read what PowerShell prints. Reads only.
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\verification\powershell\basics2.ps1
#   pwsh -NoProfile -File tests\verification\powershell\basics2.ps1
$ErrorActionPreference = 'Continue'
function Section($t) { "`n=== $t" }
function Show($x) { ($x | Out-String -Width 110).Trim("`r", "`n") }
"PowerShell $($PSVersionTable.PSVersion) $($PSVersionTable.PSEdition)"
Section 'default table of Get-Process'; Show (Get-Process -Id $PID)
Section 'Format-List *  (a few of the properties)'; Show (Get-Process -Id $PID | Format-List Name, Id, WorkingSet64, WS, CPU, StartTime, Path)
$p = Get-Process -Id $PID
"properties: $(@($p | Get-Member -MemberType Properties).Count)  methods: $(@($p | Get-Member -MemberType Methods).Count)"
Section 'Get-Member (first lines)'; Show ($p | Get-Member | Select-Object -First 9)
Section 'Get-Member for chosen members'; Show ($p | Get-Member -Name Id, Name, WorkingSet64, Kill, StartTime)
Section 'type name'; $p.GetType().FullName
Section 'syntax: Get-ChildItem'; Show (Get-Command Get-ChildItem -Syntax)
Section 'syntax: Stop-Process'; Show (Get-Command Stop-Process -Syntax)
Section 'parameter detail: Stop-Process -Name and -Id'
foreach ($n in 'Name', 'Id', 'Force') {
    $c = Get-Command Stop-Process
    foreach ($set in $c.ParameterSets) { $q = $set.Parameters | Where-Object Name -eq $n; if ($q) { "{0,-6} set={1,-12} mandatory={2,-5} position={3,-12} byValue={4,-5} byPropertyName={5} type={6}" -f $n, $set.Name, $q.IsMandatory, $q.Position, $q.ValueFromPipeline, $q.ValueFromPipelineByPropertyName, $q.ParameterType.Name } }
}
Section 'wrong parameter set'
try { Stop-Process -Name notepad -Id 1 -WhatIf } catch { $_.Exception.Message }
Section 'pipeline step by step'
"all processes: $(@(Get-Process).Count)"
"over 100MB:    $(@(Get-Process | Where-Object { $_.WorkingSet64 -gt 100MB }).Count)"
Show (Get-Process | Where-Object { $_.WorkingSet64 -gt 100MB } | Sort-Object WorkingSet64 -Descending | Select-Object -First 3 Name, Id, @{n = 'MB'; e = { [int]($_.WorkingSet64 / 1MB) } })
Section 'what type comes out of Select-Object with properties'
(Get-Process -Id $PID | Select-Object Name, Id).GetType().Name
((Get-Process -Id $PID | Select-Object Name, Id) | Get-Member | Select-Object -First 1).TypeName
Section 'Format-Table in the middle'
$f = Get-Process | Select-Object -First 3 | Format-Table Name, Id
"objects after Format-Table are: $(($f | ForEach-Object { $_.GetType().Name } | Select-Object -Unique) -join ', ')"
try { Get-Process | Select-Object -First 3 | Format-Table Name, Id | Sort-Object Id -ErrorAction Stop | Out-String } catch { "Sort after Format-Table: $($_.Exception.Message)" }
$tmp = Join-Path $env:TEMP "wl-ps2-$PID.csv"
Get-Process | Select-Object -First 2 | Format-Table Name, Id | Export-Csv $tmp -NoTypeInformation
Section 'CSV of Format-Table output'; Get-Content $tmp | Select-Object -First 3 | ForEach-Object { if ($_.Length -gt 100) { $_.Substring(0, 100) + '...' } else { $_ } }
Get-Process | Select-Object -First 2 Name, Id | Export-Csv $tmp -NoTypeInformation
Section 'CSV of Select-Object output'; Get-Content $tmp
Remove-Item $tmp
Section 'Measure-Object'; Show (Get-ChildItem $env:SystemRoot\System32 -Filter *.exe -File | Measure-Object Length -Sum -Average -Maximum)
Section 'comparison against a string and a number'
"'10' -gt 9      : $('10' -gt 9)"
"10 -gt '9'      : $(10 -gt '9')"
"'10' -gt '9'    : $('10' -gt '9')"
Section 'Get-Command result'; Show (Get-Command -Verb Stop)
Section 'a misspelled property is silent'
"[$((Get-Process -Id $PID).WorkingSte)]"
"count of processes with WorkingSte over 1: $(@(Get-Process | Where-Object { $_.WorkingSte -gt 1 }).Count)"
