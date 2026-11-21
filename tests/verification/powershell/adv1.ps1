# Battery for ps-advanced. Portable part: run in 5.1, 7 (Windows) and 7 (Linux). Writes nothing outside memory.
"PSVersion: $($PSVersionTable.PSVersion)  Edition: $($PSVersionTable.PSEdition)  OS: $([Environment]::OSVersion.Platform)"

'--- Classes'
class Point {
    [int]$X
    [int]$Y
    hidden [string]$Secret = 'h'
    static [int]$Count = 0
    Point([int]$x, [int]$y) { $this.X = $x; $this.Y = $y; [Point]::Count++ }
    Point() { $this.X = 0; $this.Y = 0; [Point]::Count++ }
    [double] Length() { return [math]::Sqrt($this.X * $this.X + $this.Y * $this.Y) }
    [string] ToString() { return "($($this.X), $($this.Y))" }
    static [Point] Origin() { return [Point]::new() }
}
$p = [Point]::new(3, 4)
$p.Length()
"$p"
[Point]::Count
[Point]::Origin().ToString()
$p | Get-Member -MemberType Property, Method | Select-Object Name, MemberType | Format-Table -AutoSize
'-- type enforced'
try { $p.X = 'abc' } catch { $_.Exception.GetType().Name; $_.Exception.Message }
$p.X = '7'; $p.X.GetType().Name
'-- missing return trap'
try { Invoke-Expression 'class Bad { [int] Get() { 5 } }; [Bad]::new().Get()' } catch { $_.Exception.GetType().Name; $_.Exception.Message }
'-- a method does NOT output stray pipeline values; but a statement that returns does not leak either'
class Leak { [int] Run() { $list = [System.Collections.ArrayList]::new(); $list.Add(1); return 5 } }
[Leak]::new().Run()
'-- redefine class in same session'
try { Invoke-Expression 'class Point { [int]$Z }'; 'redefined'; [Point]::new(1,2) } catch { $_.Exception.Message }
$p.GetType().Name; $p.X

'-- inheritance and override'
class Animal { [string] Speak() { return '...' } }
class Dog : Animal { [string] Speak() { return 'Woof' } }
([Dog]::new()).Speak()
([Animal]$([Dog]::new())).Speak()
'-- enum'
enum Level { Low = 1; Mid; High }
[Level]::Mid
[int][Level]::High
[Level]'High'
try { [Level]'Nope' } catch { $_.Exception.Message }

'--- .NET interop'
[math]::Round(2.5)
[math]::Round(2.5, [MidpointRounding]::AwayFromZero)
[System.IO.Path]::Combine('a', 'b', 'c.txt')
[System.IO.Path]::GetExtension('x.tar.gz')
[guid]::NewGuid().ToString().Length
[Environment]::MachineName.Length -gt 0
[string]::Join(',', 1..3)
[System.Text.Encoding]::UTF8.GetBytes('é').Count
$sb = [System.Text.StringBuilder]::new()
[void]$sb.Append('a').Append('b')
$sb.ToString()
'-- generic list'
$l = [System.Collections.Generic.List[string]]::new()
$l.Add('x'); $l.Count
try { $l.Add(5) ; $l[1].GetType().Name } catch { $_.Exception.Message }
'-- hashtable accumulate vs +='
$h = [System.Collections.Generic.Dictionary[string,int]]::new()
$h['a'] = 1; $h.ContainsKey('a'); $h.ContainsKey('A')
'-- static method call needs ::, instance with .'
try { [math].Round(2.5) } catch { $_.Exception.GetType().Name }
'-- Add-Type C#'
Add-Type -TypeDefinition 'public static class WlMath { public static int Twice(int n) { return n * 2; } }'
[WlMath]::Twice(21)
'-- Add-Type twice'
try { Add-Type -TypeDefinition 'public static class WlMath { public static int Twice(int n) { return n * 2; } }' -ErrorAction Stop } catch { $_.Exception.Message.Split("`n")[0] }
'-- assemblies and type accelerators'
[psobject].Assembly.GetName().Name
([type]'int').FullName
[System.Management.Automation.PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')::Get.Keys.Count -gt 20

'--- Performance'
$n = 20000
$t1 = (Measure-Command { $a = @(); foreach ($i in 1..$n) { $a += $i } }).TotalMilliseconds
$t2 = (Measure-Command { $l = [System.Collections.Generic.List[int]]::new(); foreach ($i in 1..$n) { $l.Add($i) } }).TotalMilliseconds
$t3 = (Measure-Command { $r = foreach ($i in 1..$n) { $i } }).TotalMilliseconds
"array += : $([int]$t1) ms   List.Add : $([int]$t2) ms   foreach-assign : $([int]$t3) ms"
$t4 = (Measure-Command { 1..100000 | ForEach-Object { $_ * 2 } | Out-Null }).TotalMilliseconds
$t5 = (Measure-Command { foreach ($i in 1..100000) { $i * 2 } }).TotalMilliseconds
"pipeline ForEach-Object 100k: $([int]$t4) ms   foreach statement 100k: $([int]$t5) ms"
$t6 = (Measure-Command { $s = ''; foreach ($i in 1..5000) { $s += 'x' } }).TotalMilliseconds
$t7 = (Measure-Command { $sb = [System.Text.StringBuilder]::new(); foreach ($i in 1..5000) { [void]$sb.Append('x') } }).TotalMilliseconds
"string += 5000: $([int]$t6) ms   StringBuilder: $([int]$t7) ms"
'-- Where-Object vs .Where() vs foreach'
$nums = 1..200000
"Where-Object: $([int](Measure-Command { $nums | Where-Object { $_ % 2 -eq 0 } | Out-Null }).TotalMilliseconds) ms; .Where(): $([int](Measure-Command { $null = $nums.Where({ $_ % 2 -eq 0 }) }).TotalMilliseconds) ms"
'-- Select-Object -First stops early?'
"first 1 from 1..1e6 via pipeline: $([int](Measure-Command { 1..1000000 | Select-Object -First 1 | Out-Null }).TotalMilliseconds) ms"
'-- Measure-Command output suppressed'
(Measure-Command { Write-Output 'hi' }).GetType().Name
'-- Stopwatch'
$sw = [System.Diagnostics.Stopwatch]::StartNew(); Start-Sleep -Milliseconds 50; $sw.Stop(); $sw.ElapsedMilliseconds -ge 50

'--- ForEach-Object -Parallel (7 only)'
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $outer = 10
    (1..4 | ForEach-Object -Parallel { $_ * $using:outer } -ThrottleLimit 2 | Sort-Object) -join ','
    try { 1..2 | ForEach-Object -Parallel { $outer } | Out-String } catch { $_.Exception.Message }
    '-- null-coalescing, ternary, pipeline chain, ?.'
    Invoke-Expression '$null ?? "default"'
    Invoke-Expression '(5 -gt 3) ? "yes" : "no"'
    Invoke-Expression '$u = $null; $u?.Length; "safe nav ok"'
    Invoke-Expression 'Get-Item $PSHOME && "chain ok"' | Select-Object -Last 1
}
else { 'PS5.1: no -Parallel, no ??, no ternary, no &&' }

'--- Language mode'
$ExecutionContext.SessionState.LanguageMode
'-- switch in-session to ConstrainedLanguage'
$ExecutionContext.SessionState.LanguageMode = 'ConstrainedLanguage'
$ExecutionContext.SessionState.LanguageMode
try { [System.Math]::Sqrt(4) } catch { "[Math]: $($_.Exception.Message)" }
try { [System.IO.File]::Exists('C:\nonexistent') } catch { "[File]: $($_.Exception.Message)" }
try { Add-Type -TypeDefinition 'public class Q {}' -ErrorAction Stop } catch { "Add-Type: $($_.Exception.Message.Split("`n")[0])" }
try { Invoke-Expression '1+1' } catch { "iex: $($_.Exception.Message)" }
try { New-Object -ComObject WScript.Shell | Out-Null; 'COM ok' } catch { "COM: $($_.Exception.Message.Split("`n")[0])" }
try { [Point]::new(1,2) } catch { "class: $($_.Exception.Message.Split("`n")[0])" }
'basic cmdlets still work:'; Get-Date -Format yyyy | Out-Null; 'Get-Date ok'
try { $ExecutionContext.SessionState.LanguageMode = 'FullLanguage'; "back: $($ExecutionContext.SessionState.LanguageMode)" } catch { "cannot go back: $($_.Exception.Message)" }
