# Battery for endpoints.endpoint-management: inventory, join state and installer exit codes. For a THROWAWAY VM
# (it only reads, and runs msiexec against files that are not real installers, quietly).
$ErrorActionPreference = 'Continue'
function Section($t) { "`n=== $t" }
function Show($x) { ($x | Out-String -Width 150).Trim("`r", "`n") }
"PowerShell $($PSVersionTable.PSVersion)  $((Get-CimInstance Win32_OperatingSystem).Caption)"
Section 'edition and domain membership'
Show (Get-CimInstance Win32_ComputerSystem | Format-List PartOfDomain, Domain, Workgroup)
Section 'dsregcmd /status (state lines only)'
dsregcmd.exe /status | Select-String -Pattern 'AzureAdJoined|EnterpriseJoined|DomainJoined|MdmUrl|WorkplaceJoined'
Section 'inventory from the uninstall registry keys'
$keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
foreach ($k in $keys) { "$k : $(@(Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object DisplayName).Count) entries with a DisplayName" }
Show (Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object DisplayName | Sort-Object DisplayName | Select-Object DisplayName, DisplayVersion, Publisher, PSChildName -First 6 | Format-Table -AutoSize)
Section 'Get-Package'
$all = @(Get-Package -ErrorAction SilentlyContinue)
"Get-Package: $($all.Count) items"
Show ($all | Group-Object ProviderName | Format-Table Count, Name -AutoSize)
Section 'winget present?'
"winget: $([bool](Get-Command winget.exe -ErrorAction SilentlyContinue))"
Section 'msiexec started the plain way'
Set-Content C:\Windows\Temp\bad.msi 'this is not an installer'
$global:LASTEXITCODE = 0
msiexec.exe /i C:\Windows\Temp\missing.msi /qn
"LASTEXITCODE right after: [$LASTEXITCODE]"
Section 'msiexec waited for, with the exit code'
foreach ($case in @(
        @('missing file', '/i C:\Windows\Temp\missing.msi /qn'),
        @('not an MSI', '/i C:\Windows\Temp\bad.msi /qn /l*v C:\Windows\Temp\bad.log'),
        @('uninstall a product that is not installed', '/x {11111111-2222-3333-4444-555555555555} /qn'))) {
    $p = Start-Process msiexec.exe -ArgumentList $case[1] -Wait -PassThru
    "$($case[0]) : exit $($p.ExitCode)  ($([ComponentModel.Win32Exception]::new($p.ExitCode).Message))"
}
"log written: $(Test-Path C:\Windows\Temp\bad.log)"
if (Test-Path C:\Windows\Temp\bad.log) { Get-Content C:\Windows\Temp\bad.log | Select-String -Pattern 'error|return value|status' | Select-Object -Last 4 | ForEach-Object Line }
Section 'what 3010 means to Windows'
[ComponentModel.Win32Exception]::new(3010).Message
Section 'a detection rule as a script'
function Test-Installed([string]$Name, [version]$AtLeast) {
    $hit = Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $Name }
    if (-not $hit) { return 'not installed' }
    $v = $null
    if ([version]::TryParse(@($hit)[0].DisplayVersion, [ref]$v) -and $v -ge $AtLeast) { "installed ($v)" } else { "too old or unreadable ($(@($hit)[0].DisplayVersion))" }
}
$first = Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -and $_.DisplayVersion } | Select-Object -First 1
"checking $($first.DisplayName)"
Test-Installed $first.DisplayName '0.1'
Test-Installed $first.DisplayName '9999.0'
Test-Installed 'No Such Product' '1.0'
Section 'comparing versions as text and as versions'
"text: $('10.0' -gt '9.0')   version: $([version]'10.0' -gt [version]'9.0')"
Remove-Item C:\Windows\Temp\bad.msi, C:\Windows\Temp\bad.log -ErrorAction SilentlyContinue
