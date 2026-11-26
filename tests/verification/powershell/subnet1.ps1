# Battery for networking.subnetting: a subnet calculator, and every answer in the lesson checked with it.
# Pure arithmetic; reads and changes nothing.
function Get-Subnet([string]$Cidr) {
    $address, $prefix = $Cidr -split '/'; $prefix = [int]$prefix
    $b = ([Net.IPAddress]$address).GetAddressBytes(); [array]::Reverse($b)
    $ip = [uint64][BitConverter]::ToUInt32($b, 0)
    $size = [uint64][math]::Pow(2, 32 - $prefix)
    $network = $ip - ($ip % $size); $broadcast = $network + $size - 1
    function Dotted([uint64]$v) { ($(24, 16, 8, 0) | ForEach-Object { [math]::Floor($v / [math]::Pow(2, $_)) % 256 }) -join '.' }
    [pscustomobject]@{ Cidr = $Cidr; Network = Dotted $network; Broadcast = Dotted $broadcast
        First = Dotted ($network + 1); Last = Dotted ($broadcast - 1); Hosts = $size - 2
        Mask = Dotted ([uint64][math]::Pow(2, 32) - $size) }
}
"PowerShell $($PSVersionTable.PSVersion)"
'192.168.1.130/26', '172.16.45.200/21', '10.20.30.40/24', '192.168.5.77/27', '172.31.9.130/25', '192.168.10.62/26', '192.168.10.65/26', '10.0.12.201/22', '192.168.1.200/25' |
    ForEach-Object { Get-Subnet $_ } | Format-Table Cidr, Mask, Network, Broadcast, First, Last, Hosts -AutoSize | Out-String -Width 130
"the lesson's -band example: " + ([IPAddress](([IPAddress]'192.168.1.130').Address -band ([IPAddress]'255.255.255.192').Address)).IPAddressToString
'variable sizes in 192.168.1.0/24, largest first:'
'192.168.1.0/25', '192.168.1.128/26', '192.168.1.192/27', '192.168.1.224/30' | ForEach-Object { Get-Subnet $_ } | Format-Table Cidr, Network, Broadcast, Hosts -AutoSize | Out-String
'a /26 that does not start on a block boundary:'
Get-Subnet '192.168.1.96/26' | Format-List Cidr, Network, Broadcast
