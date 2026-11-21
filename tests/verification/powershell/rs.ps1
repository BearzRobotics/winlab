$files = @(
    [pscustomobject]@{ Name = 'report.LOG'; Size = 5MB },
    [pscustomobject]@{ Name = 'notes.txt';  Size = 2KB }
)
foreach ($f in $files) {
    switch -Wildcard ($f.Name) {
        '*.log' { "log: $($f.Name)" }
        '*.txt' { "text: $($f.Name)" }
    }
    if ($f.Size = 5MB) { "big" }
}
$files | ForEach-Object { "{0} {1}" -f $_.Name, $_.Size }
