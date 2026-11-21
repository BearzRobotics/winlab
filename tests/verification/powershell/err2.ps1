Set-Location $PSScriptRoot
$files = 'a-missing.txt', 'b.txt'
Set-Content b.txt 'hello'
foreach ($f in $files) {
    try {
        $text = Get-Content $f
        "read $f"
    } catch {
        "failed $f"
    }
}
