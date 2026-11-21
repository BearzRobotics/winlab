<#
.SYNOPSIS
  Downloads the documents listed below into reference/, computes checksums, reads the licence evidence
  out of the stored files, finds which lessons cite each one, and rewrites MANIFEST.md and MANIFEST.tsv.

.DESCRIPTION
  This is the one place to add a document. Add an Add-Doc call, run the script, read the new entry in
  MANIFEST.md. Nothing in MANIFEST.* is edited by hand. Works in Windows PowerShell 5.1 and PowerShell 7.

    pwsh -NoProfile -File reference/gen_manifest.ps1

  Files are stored verbatim (a mirror of the original bytes), never edited.
#>
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$utf8 = New-Object System.Text.UTF8Encoding($false)
$agent = @{ 'User-Agent' = 'winlab-reference-fetch' }

$docs = New-Object System.Collections.Generic.List[object]

# kind: 'rfc' (licence read from the RFC text), 'fixed' (licence given here with quoted evidence)
function Add-Doc {
    param([string]$Id, [string]$Title, [string]$Dest, [string]$Url, [string[]]$Cite = @(),
          [ValidateSet('rfc', 'fixed')][string]$Kind = 'fixed', [string]$Licence = '', [string]$Evidence = '',
          [ValidateSet('permissive', 'unstated')][string]$Class = 'permissive')
    $docs.Add([pscustomobject]@{ Id = $Id; Title = $Title; Dest = $Dest; Url = $Url; Cite = $Cite; Kind = $Kind; Licence = $Licence; Evidence = $Evidence; Class = $Class })
}

# ----------------------------------------------------------------------------------------------------------
# Licence texts shared by many files
# ----------------------------------------------------------------------------------------------------------
$msDocsEvidence = "The source repository's LICENSE file (stored as microsoft/LICENSE-CC-BY-4.0.txt) is 'Attribution 4.0 International'; GitHub reports the repository licence as CC-BY-4.0. Code samples in the same repository are under the MIT licence (LICENSE-CODE, stored as microsoft/LICENSE-CODE-MIT.txt). Attribution: Microsoft Corporation, via the MicrosoftDocs repository named in the source URL."
$ianaEvidence = "IANA licensing terms (https://www.iana.org/help/licensing-terms): 'IANA and IETF affirm that any applicable rights that they may have in the Protocol Registries are subject to the Creative Commons CC0 1.0 dedication'."

# ----------------------------------------------------------------------------------------------------------
# Licence files
# ----------------------------------------------------------------------------------------------------------
$msw = 'https://raw.githubusercontent.com/MicrosoftDocs/windows-powershell-docs/HEAD'
$mss = 'https://raw.githubusercontent.com/MicrosoftDocs/windowsserverdocs/HEAD'
Add-Doc 'ms-license-docs' 'Microsoft docs repositories: LICENSE (CC BY 4.0)' 'microsoft/LICENSE-CC-BY-4.0.txt' "$mss/LICENSE" -Licence 'CC-BY-4.0' -Evidence "Licence text of the MicrosoftDocs/windowsserverdocs repository; the windows-powershell-docs repository carries the same text."
Add-Doc 'ms-license-code' 'Microsoft docs repositories: LICENSE-CODE (MIT)' 'microsoft/LICENSE-CODE-MIT.txt' "$mss/LICENSE-CODE" -Licence 'MIT' -Evidence "Licence text for the code samples in the MicrosoftDocs/windowsserverdocs repository."
Add-Doc 'iproute2-copying' 'iproute2: COPYING (GNU GPL v2)' 'linux/iproute2/COPYING-GPL-2.0.txt' 'https://git.kernel.org/pub/scm/network/iproute2/iproute2.git/plain/COPYING' -Licence 'GPL-2.0' -Evidence "Licence text of the iproute2 repository (GNU General Public License, version 2, June 1991)."

# ----------------------------------------------------------------------------------------------------------
# Microsoft Learn: Windows command reference (windowsserverdocs)
# ----------------------------------------------------------------------------------------------------------
foreach ($c in @(
    @('arp', 'arp'), @('ipconfig', 'ipconfig'), @('netstat', 'netstat'), @('nslookup', 'nslookup'), @('pathping', 'pathping'),
    @('ping', 'ping'), @('route_ws2008', 'route'), @('tracert', 'tracert'), @('netsh-advfirewall', 'netsh advfirewall'))) {
    Add-Doc "ms-cmd-$($c[0])" "Windows command: $($c[1]) (Microsoft Learn source)" "microsoft/windows-commands/$($c[0]).md" "$mss/WindowsServerDocs/administration/windows-commands/$($c[0]).md" `
        -Cite "https://learn.microsoft.com/windows-server/administration/windows-commands/$($c[0])" -Licence 'CC-BY-4.0' -Evidence $msDocsEvidence
}
Add-Doc 'ms-dhcp-top' 'DHCP overview (Microsoft Learn source)' 'microsoft/windows-server-networking/dhcp-top.md' "$mss/WindowsServerDocs/networking/technologies/dhcp/dhcp-top.md" `
    -Cite 'https://learn.microsoft.com/windows-server/networking/technologies/dhcp/dhcp-top' -Licence 'CC-BY-4.0' -Evidence $msDocsEvidence
Add-Doc 'ms-dns-overview' 'DNS overview (Microsoft Learn source)' 'microsoft/windows-server-networking/dns-overview.md' "$mss/WindowsServerDocs/networking/dns/dns-overview.md" `
    -Cite 'https://learn.microsoft.com/windows-server/networking/dns/dns-overview' -Licence 'CC-BY-4.0' -Evidence $msDocsEvidence

# ----------------------------------------------------------------------------------------------------------
# Microsoft Learn: PowerShell networking cmdlets (windows-powershell-docs)
# ----------------------------------------------------------------------------------------------------------
foreach ($m in @(
    @('NetTCPIP', 'nettcpip', @('Test-NetConnection', 'Get-NetTCPConnection', 'Get-NetNeighbor', 'Get-NetIPAddress', 'Get-NetRoute', 'New-NetRoute', 'Get-NetIPConfiguration')),
    @('DnsClient', 'dnsclient', @('Resolve-DnsName', 'Get-DnsClientCache', 'Get-DnsClientServerAddress', 'Clear-DnsClientCache')),
    @('NetSecurity', 'netsecurity', @('New-NetFirewallRule', 'Get-NetFirewallRule')))) {
    foreach ($c in $m[2]) {
        Add-Doc "ms-ps-$($c.ToLower())" "PowerShell: $c (Microsoft Learn source)" "microsoft/powershell/$($m[0])/$c.md" "$msw/docset/winserver2022-ps/$($m[0])/$c.md" `
            -Cite "https://learn.microsoft.com/powershell/module/$($m[1])/$($c.ToLower())" -Licence 'CC-BY-4.0' -Evidence $msDocsEvidence
    }
}

# ----------------------------------------------------------------------------------------------------------
# Linux manual pages from iproute2
# ----------------------------------------------------------------------------------------------------------
$ip2 = 'https://git.kernel.org/pub/scm/network/iproute2/iproute2.git/plain/man/man8'
$ip2Evidence = "Stored from the iproute2 repository, whose COPYING (stored as linux/iproute2/COPYING-GPL-2.0.txt) is the GNU General Public License v2. The man page file carries no separate licence notice, so the repository licence is the evidence."
Add-Doc 'iproute2-ip' 'ip(8) manual page (iproute2 source)' 'linux/iproute2/ip.8' "$ip2/ip.8" -Cite 'https://man7.org/linux/man-pages/man8/ip.8.html' -Licence 'GPL-2.0' -Evidence $ip2Evidence
Add-Doc 'iproute2-ip-neighbour' 'ip-neighbour(8) manual page (iproute2 source)' 'linux/iproute2/ip-neighbour.8' "$ip2/ip-neighbour.8" -Cite 'https://man7.org/linux/man-pages/man8/ip-neighbour.8.html' -Licence 'GPL-2.0' -Evidence $ip2Evidence
Add-Doc 'iproute2-ss' 'ss(8) manual page (iproute2 source)' 'linux/iproute2/ss.8' "$ip2/ss.8" -Cite 'https://man7.org/linux/man-pages/man8/ss.8.html' -Licence 'GPL-2.0' -Evidence $ip2Evidence

# ----------------------------------------------------------------------------------------------------------
# IANA registries (CC0)
# ----------------------------------------------------------------------------------------------------------
Add-Doc 'iana-ports' 'IANA service name and transport protocol port number registry (CSV)' 'iana/service-names-port-numbers.csv' 'https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.csv' `
    -Cite 'https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.xhtml' -Licence 'CC0-1.0' -Evidence $ianaEvidence
Add-Doc 'iana-ipv4-special' 'IANA IPv4 special-purpose address registry (CSV)' 'iana/iana-ipv4-special-registry-1.csv' 'https://www.iana.org/assignments/iana-ipv4-special-registry/iana-ipv4-special-registry-1.csv' `
    -Cite 'https://www.iana.org/assignments/iana-ipv4-special-registry/iana-ipv4-special-registry.xhtml' -Licence 'CC0-1.0' -Evidence $ianaEvidence

# ----------------------------------------------------------------------------------------------------------
# RFCs (plain text). Licence is read from each document.
# ----------------------------------------------------------------------------------------------------------
$rfcs = [ordered]@{
    768 = 'User Datagram Protocol'; 791 = 'Internet Protocol'; 792 = 'Internet Control Message Protocol'; 826 = 'An Ethernet Address Resolution Protocol';
    1034 = 'Domain names: concepts and facilities'; 1035 = 'Domain names: implementation and specification'; 1122 = 'Requirements for Internet Hosts: communication layers';
    1812 = 'Requirements for IP Version 4 Routers'; 1918 = 'Address Allocation for Private Internets'; 2131 = 'Dynamic Host Configuration Protocol';
    2132 = 'DHCP Options and BOOTP Vendor Extensions'; 2308 = 'Negative Caching of DNS Queries (DNS NCACHE)'; 3021 = 'Using 31-Bit Prefixes on IPv4 Point-to-Point Links';
    3022 = 'Traditional IP Network Address Translator (Traditional NAT)'; 3849 = 'IPv6 Address Prefix Reserved for Documentation';
    3927 = 'Dynamic Configuration of IPv4 Link-Local Addresses'; 4193 = 'Unique Local IPv6 Unicast Addresses'; 4291 = 'IP Version 6 Addressing Architecture';
    4632 = 'Classless Inter-domain Routing (CIDR)'; 4861 = 'Neighbor Discovery for IP version 6 (IPv6)'; 4862 = 'IPv6 Stateless Address Autoconfiguration';
    5737 = 'IPv4 Address Blocks Reserved for Documentation'; 8200 = 'Internet Protocol, Version 6 (IPv6) Specification'; 9293 = 'Transmission Control Protocol (TCP)'
}
foreach ($entry in $rfcs.GetEnumerator()) {
    $n = $entry.Key; $title = $entry.Value
    Add-Doc "rfc$n" "RFC $n`: $title" "rfc/rfc$n.txt" "https://www.rfc-editor.org/rfc/rfc$n.txt" -Cite "https://www.rfc-editor.org/rfc/rfc$n" -Kind 'rfc'
}

# ----------------------------------------------------------------------------------------------------------
# Cited but not stored (reason per URL pattern). Anything else cited in the course and not stored is listed
# as "not stored yet".
# ----------------------------------------------------------------------------------------------------------
$notStored = @(
    @('https://man7.org/linux/man-pages/man8/ip-address.8.html', 'upstream source is a template (ip-address.8.in with build-time placeholders); a rendered copy would be a derived file'),
    @('https://man7.org/linux/man-pages/man8/ip-route.8.html', 'upstream source is a template (ip-route.8.in with build-time placeholders); a rendered copy would be a derived file'),
    @('https://networkmanager.dev/docs/api/latest/nmcli.html', 'rendered from the NetworkManager source (man/nmcli.xml); licence not yet read'),
    @('https://learn.microsoft.com/windows-server/networking/dns/dns-top', 'the Learn page name differs from its repository file; cite dns-overview (stored) instead'),
    @('https://learn.microsoft.com/windows/security/operating-system-security/network-security/windows-firewall/', 'source repository for Windows security docs not yet identified and its licence not yet read')
)

# ==========================================================================================================
# Download and measure
# ==========================================================================================================
$rows = foreach ($d in $docs) {
    $path = Join-Path $here ($d.Dest -replace '/', '\')
    $status = 'ok'
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
        try { Invoke-WebRequest -Uri $d.Url -Headers $agent -OutFile "$path.part" -TimeoutSec 300; Move-Item -Force "$path.part" $path }
        catch { $status = "FAILED: $($_.Exception.Message)"; Remove-Item -Force "$path.part" -ErrorAction SilentlyContinue }
    }
    $sha = ''; $size = 0
    if (Test-Path $path) { $sha = (Get-FileHash -Algorithm SHA256 $path).Hash.ToLower(); $size = (Get-Item $path).Length }
    # The licence of an RFC is whatever its own text says.
    if ($d.Kind -eq 'rfc' -and $sha) {
        $text = [IO.File]::ReadAllText($path) -replace '\s+', ' '
        $copy = [regex]::Match($text, '(Copyright[^.]{0,120}(?:\d{4})[^.]{0,120}\.)')
        $d.Evidence = ''
        if ($text -match 'subject to BCP 78 and the IETF Trust') {
            $d.Licence = 'IETF Trust Legal Provisions (TLP-5 grants copying in full and without modification)'
            $i = $text.IndexOf('This document is subject to BCP 78')
            $d.Evidence = "The RFC's Copyright Notice: '$($copy.Value.Trim())' and '$($text.Substring($i, [Math]::Min(150, $text.Length - $i)).Trim())'. The IETF Trust Legal Provisions 5 (https://trustee.ietf.org/documents/trust-legal-provisions/tlp-5/), section 'Licenses For Use Outside the IETF Standards Process', state: 'the IETF Trust hereby grants to each person who wishes to exercise such rights ... a non-exclusive, royalty-free, worldwide right and license ... to copy, publish, display and distribute IETF Contributions and IETF Documents in full and without modification'."
        }
        elseif ($text -match 'may be copied and furnished to others') {
            $i = $text.IndexOf('This document and translations of it may be copied')
            $d.Licence = 'ISOC copyright statement (copying permitted with the notice kept)'
            $d.Evidence = "The RFC's own Full Copyright Statement: '$($copy.Value.Trim())' then '$($text.Substring($i, [Math]::Min(420, $text.Length - $i)).Trim())'."
        }
        elseif ($text -match 'subject to the rights, licenses and restrictions contained in BCP 78') {
            $i = $text.IndexOf('This document is subject to the rights, licenses and restrictions contained in BCP 78')
            $d.Licence = 'BCP 78 notice: authors retain their rights; no redistribution licence stated in the document'
            $d.Class = 'unstated'
            $d.Evidence = "The RFC's Full Copyright Statement: '$($copy.Value.Trim())' then '$($text.Substring($i, [Math]::Min(160, $text.Length - $i)).Trim())'. The document itself does not grant copying; BCP 78 (RFC 3978 and successors) is the framework it points to."
        }        elseif ($copy.Success) {
            $d.Licence = 'copyright notice present; permission wording not matched'
            $d.Class = 'unstated'
            $d.Evidence = "The RFC states '$($copy.Value.Trim())' but the permission wording was not found by this script; read the document's own copyright section."
        }
        else {
            $d.Licence = 'no licence statement in the document'
            $d.Class = 'unstated'
            $d.Evidence = 'The text carries no copyright or licence notice (an early RFC). Freely downloadable from the RFC Editor; redistribution is not explicitly granted in the document itself.'
        }
    }
    [pscustomobject]@{ Doc = $d; Sha = $sha; Size = $size; Status = $status }
}

# ==========================================================================================================
# Which lessons cite each document
# ==========================================================================================================
$courseFiles = Get-ChildItem (Join-Path $root 'course') -Recurse -File -Include *.md, *.toml -ErrorAction SilentlyContinue
$citeMap = @{}
$allUrls = New-Object System.Collections.Generic.HashSet[string]
foreach ($f in $courseFiles) {
    $t = [IO.File]::ReadAllText($f.FullName)
    $lesson = ($f.Directory.Name + '.' + [IO.Path]::GetFileNameWithoutExtension($f.Name))
    foreach ($m in [regex]::Matches($t, 'https?://[^\s)\]"''>`]+')) {
        $u = $m.Value.TrimEnd('.', ',', ';')
        [void]$allUrls.Add($u)
        if (-not $citeMap.ContainsKey($u)) { $citeMap[$u] = New-Object System.Collections.Generic.HashSet[string] }
        [void]$citeMap[$u].Add($lesson)
    }
}
function Get-CitedBy($doc) {
    $set = New-Object System.Collections.Generic.HashSet[string]
    foreach ($c in $doc.Cite) {
        foreach ($u in $citeMap.Keys) { if ($u -eq $c -or $u -like "$c*") { foreach ($l in $citeMap[$u]) { [void]$set.Add($l) } } }
    }
    return ($set | Sort-Object)
}
$storedCites = @($docs | ForEach-Object { $_.Cite } | ForEach-Object { $_ })

# ==========================================================================================================
# Write MANIFEST.tsv and MANIFEST.md
# ==========================================================================================================
$tsv = New-Object System.Text.StringBuilder
[void]$tsv.Append("# id`tmode`tdest`tsha256`tsize`turl`tstatus`n")
foreach ($r in $rows) { [void]$tsv.Append("$($r.Doc.Id)`tcommit`t$($r.Doc.Dest)`t$($r.Sha)`t$($r.Size)`t$($r.Doc.Url)`t$($r.Status)`n") }
[IO.File]::WriteAllText((Join-Path $here 'MANIFEST.tsv'), $tsv.ToString(), $utf8)

$a = @($rows | Where-Object { $_.Doc.Class -eq 'permissive' -and $_.Sha })
$b = @($rows | Where-Object { $_.Doc.Class -eq 'unstated' -and $_.Sha })
$failed = @($rows | Where-Object { -not $_.Sha })
$total = ($rows | Measure-Object Size -Sum).Sum
$md = New-Object System.Text.StringBuilder
function W([string]$s) { [void]$md.Append($s + "`n") }
function Entry($r) {
    $d = $r.Doc
    W "### $($d.Title)"
    W "- file: ``$($d.Dest)`` ($('{0:N0}' -f $r.Size) bytes), sha256 ``$($r.Sha)``"
    W "- source: <$($d.Url)>"
    if ($d.Cite.Count -gt 0) { W "- official page cited in lessons: <$($d.Cite[0])>" }
    W "- licence status: **$($d.Licence)**"
    W "- evidence: $($d.Evidence)"
    $by = @(Get-CitedBy $d)
    $tick = [string][char]96
    $citedText = 'no lesson yet'
    if ($by.Count -gt 0) { $citedText = (($by | ForEach-Object { $tick + $_ + $tick }) -join ', ') }
    W ('- cited by: ' + $citedText)
    W "- fetch status: $($r.Status)"
    W ''
}
W '# Reference manifest'
W ''
W 'Generated by `gen_manifest.ps1` (do not edit by hand). Policy: [README.md](README.md). `MANIFEST.tsv` is the machine-readable copy that `fetch.ps1` reads.'
W ''
W "All $($rows.Count - $failed.Count) stored files: $('{0:N1}' -f ($total / 1MB)) MB. Each entry states its licence status in one line, with the evidence quoted from the document or its repository."
W ''
W "## A. Permissive licence ($($a.Count) files)"
W ''
foreach ($r in $a) { Entry $r }
W "## B. Free download; redistribution not explicitly granted ($($b.Count) files)"
W ''
W 'Kept on the project owner''s rule: the document is public and nothing prohibits redistribution. If a rights holder asks, the file is removed (see README.md).'
W ''
foreach ($r in $b) { Entry $r }
if ($failed.Count) {
    W "## Failed downloads ($($failed.Count))"
    W ''
    foreach ($r in $failed) { W "- $($r.Doc.Title): <$($r.Doc.Url)> $($r.Status)" }
    W ''
}
W '## C. Cited but not stored'
W ''
W 'Documents the lessons link to that this folder does not hold, with the reason. A URL with no stated reason has not been stored yet.'
W ''
$reasons = @{}
foreach ($n in $notStored) { $reasons[$n[0]] = $n[1] }
$pending = New-Object System.Collections.Generic.List[string]
foreach ($u in ($allUrls | Sort-Object)) {
    $isStored = $false
    foreach ($c in $storedCites) { if ($u -eq $c -or $u -like "$c*") { $isStored = $true; break } }
    if ($isStored) { continue }
    $tk = [string][char]96
    $by = (($citeMap[$u] | Sort-Object | ForEach-Object { $tk + $_ + $tk }) -join ', ')
    $why = if ($reasons.ContainsKey($u)) { $reasons[$u] } else { 'not stored yet' }
    $pending.Add("- <$u>: $why. Cited by $by.")
}
foreach ($p in $pending) { W $p }
[IO.File]::WriteAllText((Join-Path $here 'MANIFEST.md'), $md.ToString(), $utf8)

"stored $($rows.Count - $failed.Count) of $($rows.Count); permissive $($a.Count), not-explicit $($b.Count), failed $($failed.Count); not stored $($pending.Count); total $('{0:N1}' -f ($total / 1MB)) MB"
if ($failed.Count) { $failed | ForEach-Object { "FAILED $($_.Doc.Id) $($_.Status)" } }
