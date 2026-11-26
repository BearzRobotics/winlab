# Battery for foundations.ps-variables-types-operators: silent traps. Reads and computes only.
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\verification\powershell\vars3.ps1   (and with pwsh)
function Section($t) { "`n=== $t" }
"PowerShell $($PSVersionTable.PSVersion)"
Section 'two names, one array'
$keep = @('a.log', 'b.log'); $delete = $keep; $delete[0] = 'CHANGED'; "keep: $($keep -join ',')"
$delete += 'c.log'; $delete[1] = 'after-plus'; "keep after += then edit: $($keep -join ',')   delete: $($delete -join ',')"
$copy = $keep.Clone(); $copy[0] = 'only-copy'; "keep after editing a Clone: $($keep -join ',')"
Section 'two names, one hashtable'
$base = @{ Port = 80 }; $other = $base; $other.Port = 8080; "base.Port: $($base.Port)"
$c = $base.Clone(); $c.Port = 1; "after Clone edit, base.Port: $($base.Port)"
$nested = @{ Tags = @('x') }; $c2 = $nested.Clone(); $c2.Tags[0] = 'changed'; "shallow clone, nested original: $($nested.Tags -join ',')"
Section 'numbers and strings are copied'
$n = 5; $m = $n; $m = 6; "n=$n m=$m"
Section 'a variable that was never set'
$total = 10; "typo gives: [$totla]"; "typo + 1 = $($totla + 1)"
"null -gt 0: $($null -gt 0)   null -lt 1: $($null -lt 1)"
Set-StrictMode -Version Latest
try { $x = $totla } catch { "strict mode: $($_.Exception.Message)" }
Set-StrictMode -Off
Section 'regex special characters in -replace and -split'
"'1.2.3' -replace '.', '-'                : $('1.2.3' -replace '.', '-')"
"'1.2.3' -replace [regex]::Escape('.'), '-' : $('1.2.3' -replace [regex]::Escape('.'), '-')"
"'1.2.3'.Replace('.', '-')                 : $('1.2.3'.Replace('.', '-'))"
"'a.b.c' -split '.' gives $(@('a.b.c' -split '.').Count) pieces; -split '\.' gives: $(('a.b.c' -split '\.') -join ' ')"
try { 'C:\temp\new' -match 'C:\temp' } catch { "match with unescaped backslash: $($_.Exception.Message.Split([Environment]::NewLine)[0])" }
"'C:\temp\new' -match [regex]::Escape('C:\temp') : $('C:\temp\new' -match [regex]::Escape('C:\temp'))"
Section '-contains on text'
"'abc' -contains 'a'  : $('abc' -contains 'a')"
"'abc' -like '*a*'    : $('abc' -like '*a*')"
"'abc'.Contains('A')  : $('abc'.Contains('A'))"
"'abc' -match 'A'     : $('abc' -match 'A')"
Section '$Matches is left over after a failed match'
$null = 'port=80' -match 'port=(\d+)'; "after first: $($Matches[1])"
$r = 'host=web01' -match 'port=(\d+)'; "second matched: $r, `$Matches[1] still: $($Matches[1])"
Section '-match on an array filters and sets no new $Matches'
$Matches = $null; $res = @('ab', 'cd', 'ad') -match '^a'; "result: $($res -join ',')  Matches is null: $($null -eq $Matches)"
Section 'one result or many'
function Get-Some($n) { 1..$n }
$one = Get-Some 1; $two = Get-Some 2
"one: type $($one.GetType().Name), index [0]: $($one[0])"
"two: type $($two.GetType().Name)"
$s = 'abc'; "a single string indexed: $($s[0])"
$files = 'report.txt'; "a single name indexed [0]: $($files[0])   count: $($files.Count)"
$wrapped = @($files); "wrapped: [0]=$($wrapped[0]) count=$($wrapped.Count)"
Section 'null comparisons with a collection on the left'
$e = @(); $r1 = ($e -eq $null); "empty -eq `$null returns count $(@($r1).Count)"
"if (@() -eq `$null) is $(if ($e -eq $null) {'true'} else {'false'});  if (`$null -eq @()) is $(if ($null -eq $e) {'true'} else {'false'})"
