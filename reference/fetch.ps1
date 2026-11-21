<#
.SYNOPSIS
  Verifies the documents stored in reference/ against MANIFEST.tsv and downloads any that are missing.

.DESCRIPTION
    fetch.ps1            verify; download what is missing; report mismatches
    fetch.ps1 -Force     also re-download files whose checksum differs
    fetch.ps1 -Check     verify only, never download (exit code 1 on a problem)

  A mismatch usually means the publisher changed the document under the same URL. The stored copy is what the
  lessons were written against, so by default it is kept and a warning is printed.
#>
param([switch]$Force, [switch]$Check)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ok = 0; $got = 0; $bad = 0; $failed = 0

foreach ($line in Get-Content (Join-Path $here 'MANIFEST.tsv')) {
    if ($line -eq '' -or $line.StartsWith('#')) { continue }
    $f = $line -split "`t"
    $dest = $f[2]; $sha = $f[3]; $url = $f[5]
    if (-not $sha) { continue }   # entries that never downloaded have no checksum
    $path = Join-Path $here ($dest -replace '/', '\')
    if ((Test-Path $path) -and ((Get-FileHash -Algorithm SHA256 $path).Hash.ToLower() -eq $sha)) { $ok++; continue }
    if ((Test-Path $path) -and -not $Force) {
        Write-Host "MISMATCH $dest (upstream may have changed; kept the stored copy; -Force to replace)"; $bad++; continue
    }
    if ($Check) { Write-Host "MISSING  $dest"; $failed++; continue }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    try {
        Invoke-WebRequest -Uri $url -Headers @{ 'User-Agent' = 'winlab-reference-fetch' } -OutFile "$path.part" -TimeoutSec 300
        Move-Item -Force "$path.part" $path
        if ((Get-FileHash -Algorithm SHA256 $path).Hash.ToLower() -eq $sha) { Write-Host "fetched  $dest"; $got++ }
        else { Write-Host "MISMATCH $dest (downloaded, but the checksum differs from the manifest)"; $bad++ }
    }
    catch {
        Remove-Item -Force "$path.part" -ErrorAction SilentlyContinue
        Write-Host "FAILED   $dest <- $url"; $failed++
    }
}
Write-Host "verified $ok, downloaded $got, mismatched $bad, failed $failed"
if ($bad -ne 0 -or $failed -ne 0) { exit 1 }
