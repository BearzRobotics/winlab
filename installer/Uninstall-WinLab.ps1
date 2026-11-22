<#
.SYNOPSIS
  Removes WinLab for the current user.
.PARAMETER RemoveUserData  Also delete %APPDATA%\WinLab (settings, progress, notes). Lab VMs and downloaded
                           images in %LOCALAPPDATA%\WinLab are NEVER deleted here: they are large and yours;
                           remove them with `winlab vm remove <id>` first, or delete that folder by hand.
.PARAMETER Quiet           No message boxes.
.PARAMETER FromDir         Internal: the install folder, passed when the script continues from a temp copy.
#>
param([switch]$RemoveUserData, [switch]$Quiet, [string]$FromDir = '')
$ErrorActionPreference = 'Stop'
if (-not [Environment]::UserInteractive) { $Quiet = $true }
$keyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\WinLab'
$me = $MyInvocation.MyCommand.Path

# A script cannot delete the folder it runs from, so continue from a copy in %TEMP%.
if (-not $FromDir) {
  $dir = Split-Path -Parent $me
  $copy = Join-Path $env:TEMP 'Uninstall-WinLab-copy.ps1'
  Copy-Item -LiteralPath $me -Destination $copy -Force
  $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $copy, '-FromDir', $dir)
  if ($RemoveUserData) { $a += '-RemoveUserData' }
  if ($Quiet) { $a += '-Quiet' }
  $p = Start-Process powershell.exe -ArgumentList $a -WindowStyle Hidden -PassThru
  if ($Quiet) { $p.WaitForExit(); exit $p.ExitCode }
  exit 0
}

function Say($m, $icon = 'Information') {
  if ($Quiet) { Write-Output $m; return }
  Add-Type -AssemblyName System.Windows.Forms
  [void][Windows.Forms.MessageBox]::Show($m, 'WinLab uninstall', 'OK', $icon)
}
try {
  Get-Process winlab -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$FromDir\*" } | Stop-Process -Force
  Start-Sleep -Milliseconds 500
  # Only delete a folder that really is a WinLab install.
  if ((Test-Path (Join-Path $FromDir 'winlab.exe')) -and (Test-Path (Join-Path $FromDir 'Uninstall-WinLab.ps1'))) {
    Remove-Item -LiteralPath $FromDir -Recurse -Force
  } else {
    throw "Refusing to delete '$FromDir': it does not look like a WinLab install folder."
  }
  $lnk = Join-Path ([Environment]::GetFolderPath('Programs')) 'WinLab.lnk'
  if (Test-Path $lnk) { Remove-Item -LiteralPath $lnk -Force }
  if (Test-Path $keyPath) { Remove-Item -Path $keyPath -Recurse -Force }
  $note = ''
  if ($RemoveUserData) {
    $ud = Join-Path $env:APPDATA 'WinLab'
    if (Test-Path $ud) { Remove-Item -LiteralPath $ud -Recurse -Force }
  } else {
    $note = "`nYour settings and progress in $env:APPDATA\WinLab were kept."
  }
  if (Test-Path (Join-Path $env:LOCALAPPDATA 'WinLab\vms')) {
    $note += "`nLab VMs and images in $env:LOCALAPPDATA\WinLab were kept (they are large; delete that folder if you no longer want them)."
  }
  Say ("WinLab was removed." + $note)
  exit 0
} catch {
  Say ("WinLab could not be fully removed:`n" + $_.Exception.Message) 'Error'
  exit 1
}
