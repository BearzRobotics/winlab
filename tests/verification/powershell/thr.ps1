try { Get-Item C:\nope -ErrorAction Stop } catch { Write-Error $_; exit 4 }
