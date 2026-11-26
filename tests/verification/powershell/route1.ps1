# Battery for networking.routing-and-gateways. THROWAWAY VM ONLY, elevated. Adds routes only to single test
# addresses and to 203.0.113.0/24 (a documentation range), and removes them. Never touches the default route.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
function Section($t) { "`n=== $t" }
function Show($x) { ($x | Out-String -Width 150).Trim("`r", "`n") }
"PowerShell $($PSVersionTable.PSVersion)"
$if = (Get-NetIPConfiguration | Where-Object IPv4DefaultGateway).InterfaceAlias
Section 'route print -4'
route.exe print -4
Section 'Get-NetRoute with both metrics'
Show (Get-NetRoute -AddressFamily IPv4 | Where-Object { $_.DestinationPrefix -in '0.0.0.0/0', '10.0.2.0/24' } |
    Format-Table DestinationPrefix, NextHop, RouteMetric, @{n = 'IfMetric'; e = { (Get-NetIPInterface -InterfaceIndex $_.ifIndex -AddressFamily IPv4).InterfaceMetric } }, InterfaceAlias -AutoSize)
Section 'which route would be used: Find-NetRoute'
foreach ($d in '10.0.2.3', '1.1.1.1') {
    "to ${d}:"
    Show (Find-NetRoute -RemoteIPAddress $d | Select-Object IPAddress, DestinationPrefix, NextHop, InterfaceAlias | Format-Table -AutoSize)
}
Section 'a gateway that is not on any local subnet'
route.exe add 203.0.113.0 mask 255.255.255.0 192.168.1.3
"exit $LASTEXITCODE"
try { New-NetRoute -DestinationPrefix 203.0.113.0/24 -NextHop 192.168.1.3 -InterfaceAlias $if -ErrorAction Stop | Out-String } catch { "New-NetRoute: $($_.Exception.Message)" }
Show (Get-NetRoute -DestinationPrefix 203.0.113.0/24 -ErrorAction SilentlyContinue | Format-Table DestinationPrefix, NextHop, PolicyStore -AutoSize)
Remove-NetRoute -DestinationPrefix 203.0.113.0/24 -Confirm:$false -ErrorAction SilentlyContinue
route.exe delete 203.0.113.0 | Out-Null
Section 'a gateway on the subnet that does not exist (one test address only)'
ping.exe -n 2 -w 2000 1.1.1.1
route.exe add 1.1.1.1 mask 255.255.255.255 10.0.2.50
Show (Find-NetRoute -RemoteIPAddress 1.1.1.1 | Where-Object NextHop | Select-Object DestinationPrefix, NextHop | Format-Table -AutoSize)
ping.exe -n 2 -w 2000 1.1.1.1
arp.exe -a | Select-String '10\.0\.2\.(2|50) '
'another address still works:'; ping.exe -n 1 -w 2000 1.0.0.1 | Select-String 'Reply|timed|unreachable'
route.exe delete 1.1.1.1
Section 'where does a new route get stored?'
New-NetRoute -DestinationPrefix 203.0.113.0/24 -NextHop 10.0.2.2 -InterfaceAlias $if | Out-Null
"New-NetRoute: Active=$(@(Get-NetRoute -DestinationPrefix 203.0.113.0/24 -PolicyStore ActiveStore -ErrorAction SilentlyContinue).Count) Persistent=$(@(Get-NetRoute -DestinationPrefix 203.0.113.0/24 -PolicyStore PersistentStore -ErrorAction SilentlyContinue).Count)"
Remove-NetRoute -DestinationPrefix 203.0.113.0/24 -Confirm:$false
"after Remove-NetRoute: Active=$(@(Get-NetRoute -DestinationPrefix 203.0.113.0/24 -PolicyStore ActiveStore -ErrorAction SilentlyContinue).Count) Persistent=$(@(Get-NetRoute -DestinationPrefix 203.0.113.0/24 -PolicyStore PersistentStore -ErrorAction SilentlyContinue).Count)"
route.exe add 203.0.113.0 mask 255.255.255.0 10.0.2.2 | Out-Null
"route add: Persistent=$(@(Get-NetRoute -DestinationPrefix 203.0.113.0/24 -PolicyStore PersistentStore -ErrorAction SilentlyContinue).Count)"
route.exe delete 203.0.113.0 | Out-Null
route.exe -p add 203.0.113.0 mask 255.255.255.0 10.0.2.2 | Out-Null
"route -p add: Persistent=$(@(Get-NetRoute -DestinationPrefix 203.0.113.0/24 -PolicyStore PersistentStore -ErrorAction SilentlyContinue).Count)"
route.exe print -4 | Select-String -Context 0,4 'Persistent Routes'
route.exe delete 203.0.113.0 | Out-Null
Section 'longest prefix beats a lower metric'
New-NetRoute -DestinationPrefix 203.0.113.0/24 -NextHop 10.0.2.2 -InterfaceAlias $if -RouteMetric 1 -PolicyStore ActiveStore | Out-Null
New-NetRoute -DestinationPrefix 203.0.113.77/32 -NextHop 10.0.2.3 -InterfaceAlias $if -RouteMetric 500 -PolicyStore ActiveStore | Out-Null
foreach ($d in '203.0.113.77', '203.0.113.78') { "${d}: " + ((Find-NetRoute -RemoteIPAddress $d | Where-Object NextHop | ForEach-Object { "$($_.DestinationPrefix) via $($_.NextHop)" })) }
Remove-NetRoute -DestinationPrefix 203.0.113.0/24, 203.0.113.77/32 -Confirm:$false
"left over: $(@(Get-NetRoute -DestinationPrefix 203.0.113.0/24, 203.0.113.77/32, 1.1.1.1/32 -ErrorAction SilentlyContinue).Count)"
