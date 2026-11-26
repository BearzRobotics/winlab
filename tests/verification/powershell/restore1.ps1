# Battery for operations.operational-procedures: a backup that looks fine and a restore test that finds out.
# Works only in a temporary folder that it removes.
$ErrorActionPreference = 'Continue'
$work = Join-Path $env:TEMP "wl-restore-$PID"
$src = Join-Path $work 'data'; $out = Join-Path $work 'restored'; $zip = Join-Path $work 'backup.zip'
New-Item -ItemType Directory "$src\sub", "$src\empty" -Force | Out-Null
try {
    "PowerShell $($PSVersionTable.PSVersion)"
    Set-Content "$src\report.txt" 'quarterly report'
    Set-Content "$src\sub\notes.txt" 'notes'
    Set-Content "$src\.settings" 'dot file'
    Set-Content "$src\secret.cfg" 'hidden file'; (Get-Item "$src\secret.cfg").Attributes = 'Hidden'
    '=== the backup'
    Compress-Archive -Path "$src\*" -DestinationPath $zip
    "succeeded: $?   archive exists: $(Test-Path $zip)"
    Expand-Archive -Path $zip -DestinationPath $out
    '=== the restore test'
    function Get-Manifest($root) {
        Get-ChildItem -LiteralPath $root -Recurse -File -Force | ForEach-Object {
            [pscustomobject]@{ Path = $_.FullName.Substring($root.Length + 1); Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
        }
    }
    $a = @(Get-Manifest $src); $b = @(Get-Manifest $out)
    "source files: $($a.Count)   restored files: $($b.Count)"
    (Compare-Object $a $b -Property Path, Hash | Sort-Object Path | ForEach-Object { "$($_.SideIndicator) $($_.Path)" })
    "empty folder restored: $(Test-Path "$out\empty")"
    '=== a file in use while backing up'
    Remove-Item $zip
    $lock = [IO.File]::Open("$src\report.txt", 'Open', 'ReadWrite', 'None')
    try { Compress-Archive -Path "$src\*" -DestinationPath $zip -ErrorAction Stop; "succeeded" }
    catch { "error: $($_.Exception.Message.Replace($work,'<work>'))" }
    finally { $lock.Close() }
    "archive left behind: $(Test-Path $zip)"
}
finally { Remove-Item $work -Recurse -Force }
