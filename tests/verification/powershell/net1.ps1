# Battery for networking.addressing-and-names. THROWAWAY VM ONLY, elevated: adds one hosts-file line and
# removes it. Needs no internet access, though it tries one outside address to show what that looks like.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
function Section($t) { "`n=== $t" }
function Show($x) { ($x | Out-String -Width 150).Trim("`r", "`n") }
"PowerShell $($PSVersionTable.PSVersion)  $((Get-CimInstance Win32_OperatingSystem).Caption)"
Section 'ipconfig /all'
ipconfig.exe /all
Section 'Get-NetIPAddress'
Show (Get-NetIPAddress -AddressFamily IPv4 | Format-Table InterfaceAlias, IPAddress, PrefixLength, PrefixOrigin -AutoSize)
Section 'Get-NetIPConfiguration'
Show (Get-NetIPConfiguration)
$gw = (Get-NetIPConfiguration | Where-Object IPv4DefaultGateway).IPv4DefaultGateway.NextHop
Section "ping the gateway $gw"
ping.exe -n 2 $gw
Section 'ping an outside address'
ping.exe -n 2 -w 2000 1.1.1.1
Section 'TCP to the same outside address'
Show (Test-NetConnection 1.1.1.1 -Port 443 -WarningVariable w)
"warnings: $w"
Section 'a port where something listens'
Show (Test-NetConnection 127.0.0.1 -Port 22)
Section 'a port where nothing listens'
$t = [Diagnostics.Stopwatch]::StartNew(); $r = Test-NetConnection 127.0.0.1 -Port 8999 -WarningVariable w2; "after $([math]::Round($t.Elapsed.TotalSeconds,1)) s"; Show $r; "warnings: $w2"
Section 'an address that never answers'
$t = [Diagnostics.Stopwatch]::StartNew(); $r = Test-NetConnection 10.255.255.1 -Port 80 -WarningVariable w3; "after $([math]::Round($t.Elapsed.TotalSeconds,1)) s"; Show $r; "warnings: $w3"
Section 'the .NET exception tells refused from timed out'
foreach ($target in @(@('127.0.0.1', 8999), @('10.255.255.1', 80), @('127.0.0.1', 22))) {
    $c = New-Object Net.Sockets.TcpClient; $sw = [Diagnostics.Stopwatch]::StartNew()
    try { $c.Connect($target[0], $target[1]); $res = 'connected' }
    catch { $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }; $res = "$($e.SocketErrorCode)" }
    finally { $c.Close() }
    "$($target[0]):$($target[1])  $res  ($([math]::Round($sw.Elapsed.TotalSeconds,1)) s)"
}
Section 'a hosts-file line: who obeys it'
$hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
$backup = Get-Content $hosts -Raw
try {
    Add-Content $hosts "`r`n192.0.2.77 wl-test.example"
    ipconfig.exe /flushdns | Out-Null
    '--- Resolve-DnsName'; Resolve-DnsName wl-test.example -ErrorAction SilentlyContinue -ErrorVariable e4 | Format-Table Name, Type, IPAddress -AutoSize | Out-String; if ($e4) { $e4[0].Exception.Message }
    '--- Resolve-DnsName -NoHostsFile'; try { Resolve-DnsName wl-test.example -NoHostsFile -ErrorAction Stop | Out-String } catch { $_.Exception.Message }
    '--- nslookup'; cmd.exe /d /c 'nslookup wl-test.example 2>&1'
    '--- ping'; ping.exe -n 1 -w 500 wl-test.example
}
finally { Set-Content $hosts $backup -NoNewline; ipconfig.exe /flushdns | Out-Null }
"hosts restored: $((Get-Content $hosts -Raw) -eq $backup)"
Section 'a name that does not exist'
try { Resolve-DnsName no-such-name.invalid -ErrorAction Stop } catch { $_.Exception.Message }
Section 'a DNS server that does not answer'
$sw = [Diagnostics.Stopwatch]::StartNew(); try { Resolve-DnsName example.com -Server 10.255.255.1 -QuickTimeout -ErrorAction Stop | Out-String } catch { $_.Exception.Message }; "after $([math]::Round($sw.Elapsed.TotalSeconds,1)) s"
