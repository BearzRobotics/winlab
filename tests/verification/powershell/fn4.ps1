# Battery for foundations.ps-functions-and-scripts: parameter binding. Computes only; one temp script, removed.
#   Run with powershell.exe and pwsh.
function Section($t) { "`n=== $t" }
"PowerShell $($PSVersionTable.PSVersion)"
Section 'pipeline binding by property name'
function Show-Target { [CmdletBinding()] param([Parameter(ValueFromPipelineByPropertyName)][string]$Name, [Parameter(ValueFromPipelineByPropertyName)][Alias('Id')][int]$Number)
    process { "Name=$Name Number=$Number" } }
[pscustomobject]@{ Name = 'web01'; Id = 7 }, [pscustomobject]@{ Name = 'db01'; Number = 9 } | Show-Target
[pscustomobject]@{ ComputerName = 'x'; Port = 1 } | Show-Target
Section 'by value and by name on one parameter'
function Show-Value { [CmdletBinding()] param([Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)][string]$Name) process { "[$Name]" } }
'plain string' | Show-Value
[pscustomobject]@{ Name = 'from property' } | Show-Value
[pscustomobject]@{ Other = 'no Name property' } | Show-Value
Section 'a string parameter given an array'
function Take-String { param([string]$Value) "got [$Value]" }
Take-String -Value @('a', 'b', 'c')
Section 'an int parameter given text or fractions'
function Take-Int { param([int]$N) "N=$N" }
Take-Int 2.5; Take-Int 3.5; Take-Int '42'
Section 'a bool is not a switch'
function Flags { param([bool]$Enabled, [switch]$Force) "Enabled=$Enabled Force=$Force" }
Flags
Flags -Force
Flags -Force:$false -Enabled $true
try { Flags -Enabled 'False' } catch { "Enabled 'False': $($_.Exception.Message.Split('.')[0])" }
Section 'validation is not applied to the default value'
function Defaulted { param([ValidateRange(1, 10)][int]$Count = 0) "Count=$Count" }
Defaulted
try { Defaulted -Count 0 } catch { "passed explicitly: rejected" }
Section 'but a later assignment is validated'
function Later { param([ValidateRange(1, 10)][int]$Count = 5) try { $Count = 99; "after: $Count" } catch { "assigning 99 failed: $($_.Exception.GetType().Name)" } }
Later
Section 'a typo in a parameter name'
function Simple { param($Name) "Name=[$Name] args=[$($args -join ',')]" }
Simple -Nmae bob
function Advanced { [CmdletBinding()] param($Name) "Name=[$Name]" }
try { Advanced -Nmae bob } catch { "advanced: $($_.Exception.Message)" }
Section 'extra unnamed arguments'
Simple a b c
try { Advanced a b } catch { "advanced: $($_.Exception.Message)" }
Section 'calling a function before it is defined, in a script file'
$t = Join-Path $env:TEMP "wl-fn-$PID.ps1"
Set-Content $t "Say-It`r`nfunction Say-It { 'said' }`r`nSay-It"
& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $t 2>&1 | ForEach-Object { "$_" } | Select-Object -First 3
"..."
& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $t 2>$null | Select-Object -Last 1
Remove-Item $t
