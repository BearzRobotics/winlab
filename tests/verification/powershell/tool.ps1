#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Name, [int]$Count = 2)
"Hello $Name x$Count from $(Split-Path -Leaf $PSCommandPath)"
exit 3
