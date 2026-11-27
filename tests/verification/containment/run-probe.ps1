# Host side of the containment probe. Listens on loopback only, runs probe.sh in a lab VM with -Runner,
# then says which listeners were actually reached. -Runner is a script that takes -Script -Vm -Lab.
param([Parameter(Mandatory)][string]$Runner, [Parameter(Mandatory)][string]$Vm, [Parameter(Mandatory)][string]$Lab)
$ErrorActionPreference = 'Stop'
$l4 = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0); $l4.Start()
$l6 = [Net.Sockets.TcpListener]::new([Net.IPAddress]::IPv6Loopback, 0); $l6.Start()
$u4 = [Net.Sockets.UdpClient]::new([Net.IPEndPoint]::new([Net.IPAddress]::Loopback, 0))
try {
    $lan = @(Get-NetIPConfiguration | Where-Object IPv4DefaultGateway | ForEach-Object { $_.IPv4Address.IPAddress }) -join ' '
    $head = "TCP4=$($l4.LocalEndpoint.Port) TCP6=$($l6.LocalEndpoint.Port) UDP4=$($u4.Client.LocalEndPoint.Port) LANIPS='$lan'"
    $tmp = Join-Path ([IO.Path]::GetTempPath()) 'wl-containment-probe.sh'
    $body = (Get-Content (Join-Path $PSScriptRoot 'probe.sh') -Raw) -replace "`r", ''
    [IO.File]::WriteAllText($tmp, $body.Replace("#!/bin/bash`n", "#!/bin/bash`n$head`n"))
    & $Runner -Script $tmp -Vm $Vm -Lab $Lab
    "host side: tcp4 listener reached = $($l4.Pending())"
    "host side: tcp6 listener reached = $($l6.Pending())"
    "host side: udp4 datagram arrived = $($u4.Available -gt 0)"
}
finally { $l4.Stop(); $l6.Stop(); $u4.Dispose() }
