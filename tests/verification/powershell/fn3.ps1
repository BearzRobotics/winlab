function Get-Total {
    param($Numbers)
    $list = [System.Collections.ArrayList]::new()
    foreach ($n in $Numbers) { $list.Add($n * 2) }
    $sum = 0
    foreach ($v in $list) { $sum += $v }
    Write-Host "Total: $sum"
    return $sum
}
$t = Get-Total 1,2,3
"t = " + ($t -join ',') + " (count " + @($t).Count + ")"
function Get-Last { param($x) "got $x" }
"no process block, piped:"
1..3 | Get-Last
function Get-Last2 { [CmdletBinding()] param([Parameter(ValueFromPipeline)]$x) "got $x" }
1..3 | Get-Last2
