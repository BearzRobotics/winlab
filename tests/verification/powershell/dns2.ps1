# Battery for networking.dns. THROWAWAY VM ONLY, elevated: looks up public example names through the
# VM's resolver and reads the local DNS cache. Changes only the cache.
$ErrorActionPreference = 'Continue'
function Section($t) { "`n=== $t" }
function Show($x) { ($x | Out-String -Width 150).Trim("`r", "`n") }
"PowerShell $($PSVersionTable.PSVersion)"
Clear-DnsClientCache
Section 'first lookup'
Show (Resolve-DnsName example.com -Type A | Format-Table Name, Type, TTL, Section, IPAddress -AutoSize)
Section 'cache entry, then again 5 s later'
Show (Get-DnsClientCache -Entry example.com -ErrorAction SilentlyContinue | Format-Table Entry, Type, Status, TimeToLive, Data -AutoSize)
Start-Sleep 5
Show (Get-DnsClientCache -Entry example.com -ErrorAction SilentlyContinue | Format-Table Entry, Type, Status, TimeToLive, Data -AutoSize)
Section 'a name that does not exist, and the cache'
try { Resolve-DnsName wl-nothing-here.example.com -ErrorAction Stop | Out-Null } catch { "error: $($_.Exception.Message)"; "id: $($_.FullyQualifiedErrorId)" }
Show (Get-DnsClientCache -Entry wl-nothing-here.example.com -ErrorAction SilentlyContinue | Format-Table Entry, Type, Status, TimeToLive -AutoSize)
Section 'a name that exists, asking for a type it does not have'
$r = Resolve-DnsName example.com -Type SRV -ErrorAction SilentlyContinue -ErrorVariable e
"errors: $($e.Count)"
Show ($r | Format-Table Name, Type, TTL, Section, PrimaryServer -AutoSize)
"count of SRV answers: $(@($r | Where-Object Type -eq 'SRV').Count)"
Section 'nslookup for the same two cases'
cmd.exe /d /c 'nslookup wl-nothing-here.example.com 2>&1'
cmd.exe /d /c 'nslookup -type=SRV example.com 2>&1'
