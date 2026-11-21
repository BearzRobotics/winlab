$d = [IO.Path]::GetTempPath()
$f = Join-Path $d 'wl-one.txt'; Set-Content $f 'hello'
$g = Get-Content $f
'type=' + $g.GetType().Name + ' Count=' + $g.Count + ' Length=' + $g.Length + ' [0]=' + $g[0] + ' @()[0]=' + @(Get-Content $f)[0]
$f2 = Join-Path $d 'wl-two.txt'; Set-Content $f2 @('hello','world')
$h = Get-Content $f2; 'two lines: Count=' + $h.Count + ' [0]=' + $h[0]
Remove-Item $f,$f2
$t = 0; $t += '5000'; $t += '4200'; 'int-left: ' + $t + ' (' + $t.GetType().Name + ')'
$s = '5000'; $s += 0; 'string-left: ' + $s + ' (' + $s.GetType().Name + ')'
$m = [pscustomobject]@{ A = '12.5' }; $x = 0; $x += $m.A; 'decimal text: ' + $x + ' (' + $x.GetType().Name + ')'
'ms sum of text: ' + (('5000','4200' | ForEach-Object { [pscustomobject]@{ V = $_ } }) | Measure-Object V -Sum).Sum
