'--- basic and call syntax trap'
function Add-Two { param([int]$A, [int]$B) $A + $B }
Add-Two 1 2
Add-Two -A 3 -B 4
"comma form:"; try { Add-Two 1, 2 } catch { $_.Exception.Message.Split("`n")[0] }
'--- output pollution'
function Bad { $al = [System.Collections.ArrayList]::new(); $al.Add('x'); $al.Add('y'); 'result' }
(Bad) -join ','
function Good { $al = [System.Collections.ArrayList]::new(); $null = $al.Add('x'); [void]$al.Add('y'); 'result' }
(Good) -join ','
'--- return semantic'
function R { 'first'; return 'second'; 'never' }
(R) -join '|'
'--- advanced function: validation, mandatory, pipeline'
function Get-Size {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Path,
        [ValidateSet('B','KB','MB')]
        [string]$Unit = 'KB',
        [ValidateRange(0,3)]
        [int]$Digits = 1,
        [switch]$Quiet
    )
    begin   { $div = @{ B=1; KB=1KB; MB=1MB }[$Unit]; Write-Verbose "unit $Unit" }
    process {
        foreach ($p in $Path) {
            $len = (Get-Item -LiteralPath $p).Length
            [pscustomobject]@{ Path = (Split-Path -Leaf $p); Size = [math]::Round($len / $div, $Digits); Unit = $Unit }
        }
    }
    end { if (-not $Quiet) { Write-Verbose 'done' } }
}
$d = Join-Path $env:TEMP 'wl-ps-demo'
Set-Content "$d\f1.txt" ('x' * 2048) -NoNewline
Set-Content "$d\f2.txt" ('y' * 1048576) -NoNewline
"$d\f1.txt","$d\f2.txt" | Get-Size -Unit KB -Digits 0 | Format-Table -AutoSize | Out-String -Width 120
Get-Size "$d\f2.txt" -Unit MB -Verbose 4>&1 | ForEach-Object { "$_" }
"validate set error:"; try { Get-Size "$d\f1.txt" -Unit GB } catch { $_.Exception.Message.Split("`n")[0] }
"validate range error:"; try { Get-Size "$d\f1.txt" -Digits 9 } catch { $_.Exception.Message.Split("`n")[0] }
'--- splatting'
$args1 = @{ Path = "$d\f1.txt"; Unit = 'B'; Digits = 0 }
(Get-Size @args1).Size
'--- ShouldProcess'
function Remove-Demo { [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')] param([string]$Name) if ($PSCmdlet.ShouldProcess($Name, 'Remove')) { "removed $Name" } }
Remove-Demo A -WhatIf; Remove-Demo B
'--- PSBoundParameters and defaults'
function Show { [CmdletBinding()] param($X = 'dflt', $Y) "bound: " + (($PSBoundParameters.Keys | Sort-Object) -join ',') + "; X=$X" }
Show -Y 1
'--- parameter sets'
function Ps { [CmdletBinding(DefaultParameterSetName='ByName')] param([Parameter(ParameterSetName='ByName')][string]$Name, [Parameter(ParameterSetName='ById')][int]$Id) $PSCmdlet.ParameterSetName }
Ps -Name a; Ps -Id 5
"conflict:"; try { Ps -Name a -Id 5 } catch { $_.Exception.Message.Split("`n")[0] }
'--- scope of functions and dot-sourcing'
$lib = Join-Path $d 'lib.ps1'
Set-Content $lib 'function Hello { "hello from lib" }; $libvar = 42'
& $lib
"after call: " + [bool](Get-Command Hello -ErrorAction SilentlyContinue)
. $lib
"after dot-source: " + (Hello) + " libvar=$libvar"
'--- script with param and exit code'
$sc = Join-Path $d 'tool.ps1'
Set-Content $sc @(
  '#Requires -Version 5.1',
  '[CmdletBinding()]',
  'param([Parameter(Mandatory)][string]$Name, [int]$Count = 2)',
  '"Hello $Name x$Count from $(Split-Path -Leaf $PSCommandPath)"',
  'exit 3'
)
pwsh -NoProfile -File $sc -Name Ada
"exit=$LASTEXITCODE"
"missing mandatory (non-interactive):"
pwsh -NoProfile -NonInteractive -File $sc -Count 5 2>&1 | Select-Object -First 2
