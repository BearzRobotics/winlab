'--- return semantic'
function Get-Ret { 'first'; return 'second'; 'never' }
(Get-Ret) -join '|'
'--- parameter sets'
function Find-Thing { [CmdletBinding(DefaultParameterSetName='ByName')] param([Parameter(ParameterSetName='ByName')][string]$Name, [Parameter(ParameterSetName='ById')][int]$Id) $PSCmdlet.ParameterSetName }
Find-Thing -Name a
Find-Thing -Id 5
"conflict:"; try { Find-Thing -Name a -Id 5 } catch { $_.Exception.Message.Split("`n")[0] }
'--- command precedence'
function ls { 'my function ls' }
ls | Select-Object -First 1
Get-Command ls | Select-Object -ExpandProperty CommandType
Remove-Item Alias:ls -ErrorAction SilentlyContinue
ls
'--- pipeline function: process block count'
function Count-Items { [CmdletBinding()] param([Parameter(ValueFromPipeline)]$Item) begin { $n = 0 } process { $n++ } end { "saw $n" } }
1..5 | Count-Items
'--- filter keyword and $input'
function Double-It { process { $_ * 2 } }
1..3 | Double-It
'--- Get-Help from comment-based help'
function Get-Greeting {
    <#
    .SYNOPSIS
    Builds a greeting.
    .PARAMETER Name
    Who to greet.
    .EXAMPLE
    Get-Greeting -Name Ada
    #>
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Name) "Hello, $Name"
}
(Get-Help Get-Greeting).Synopsis
(Get-Help Get-Greeting -Examples).examples.example[0].code
'--- default parameter value from expression and typed array'
function Nums { param([int[]]$N = 1..3) ($N | Measure-Object -Sum).Sum }
Nums; Nums -N 10,20
'--- unnamed args'
function Old { "args: " + ($args -join ',') + " count=" + $args.Count }
Old a b c
'--- Write-Output vs Write-Host'
function Out1 { Write-Output 'to pipeline'; Write-Host 'to host only' }
$x = Out1; "captured: [$x]"
'--- returning an array unrolls'
function Arr { return @(1,2,3) }
(Arr).GetType().Name; function Arr2 { return ,@(1,2,3) }; (Arr2).GetType().Name; (Arr2).Count
'--- closure of function scope: variable modification'
$counter = 0; function Inc { $counter++; $counter }; Inc; "outer counter still $counter"; function Inc2 { $script:counter++ }; Inc2; "after script: $counter"
