<#
.SYNOPSIS
  Installs WinLab for the current user. No administrator rights needed.
.DESCRIPTION
  Unpacks payload.zip (next to this script) into the install folder, adds a Start menu shortcut and an
  "Apps > Installed apps" entry (HKCU). It never installs QEMU or anything else; WinLab's first-run
  setup window explains how to get QEMU if you want the hands-on labs.
.PARAMETER InstallDir  Default: %LOCALAPPDATA%\Programs\WinLab
.PARAMETER Quiet       No message boxes (for scripted installs). Exit code 0 means success.
.PARAMETER NoShortcut  Skip the Start menu shortcut.
#>
param(
  [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\WinLab'),
  [switch]$Quiet,
  [switch]$NoShortcut
)
$ErrorActionPreference = 'Stop'
# A session with no desktop (a remote shell, a service) cannot show message boxes: behave as -Quiet there.
if (-not [Environment]::UserInteractive) { $Quiet = $true }
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$zip = Join-Path $here 'payload.zip'
$keyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\WinLab'
function Say($m, $title = 'WinLab setup', $icon = 'Information') {
  if ($Quiet) { Write-Output $m; return }
  Add-Type -AssemblyName System.Windows.Forms
  [void][Windows.Forms.MessageBox]::Show($m, $title, 'OK', $icon)
}
try {
  if ($PSVersionTable.PSVersion.Major -lt 5) { throw 'Windows PowerShell 5.1 or newer is required.' }
  if (-not [Environment]::Is64BitOperatingSystem) { throw 'WinLab needs 64-bit Windows.' }
  if (-not (Test-Path $zip)) { throw "payload.zip was not found next to the installer ($here)." }

  # Stop a running copy so its files can be replaced.
  Get-Process winlab -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$InstallDir\*" } | Stop-Process -Force

  # Replace the program and content folders; leave anything else in the folder alone.
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  foreach ($d in 'course', 'labs', 'paths', 'quizzes', 'certs', 'images', 'docs') {
    $p = Join-Path $InstallDir $d
    if (Test-Path $p) { Remove-Item -LiteralPath $p -Recurse -Force }
  }
  Expand-Archive -LiteralPath $zip -DestinationPath $InstallDir -Force
  Copy-Item -LiteralPath (Join-Path $here 'Uninstall-WinLab.ps1') -Destination $InstallDir -Force

  $exe = Join-Path $InstallDir 'winlab.exe'
  if (-not (Test-Path $exe)) { throw 'winlab.exe is missing after unpacking.' }
  $version = (Get-Content (Join-Path $InstallDir 'VERSION.txt') -ErrorAction SilentlyContinue | Select-Object -First 1)
  if (-not $version) { $version = '0' }

  if (-not $NoShortcut) {
    $lnk = Join-Path ([Environment]::GetFolderPath('Programs')) 'WinLab.lnk'
    $sh = New-Object -ComObject WScript.Shell
    $s = $sh.CreateShortcut($lnk)
    $s.TargetPath = $exe; $s.WorkingDirectory = $InstallDir; $s.Description = 'WinLab: offline administration course'
    $s.Save()
  }

  $size = [int]((Get-ChildItem $InstallDir -Recurse -File | Measure-Object Length -Sum).Sum / 1KB)
  New-Item -Path $keyPath -Force | Out-Null
  $props = @{
    DisplayName = 'WinLab'; DisplayVersion = $version; Publisher = 'WinLab'; InstallLocation = $InstallDir
    DisplayIcon = $exe
    UninstallString = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$InstallDir\Uninstall-WinLab.ps1`""
    EstimatedSize = $size
  }
  foreach ($k in $props.Keys) { Set-ItemProperty -Path $keyPath -Name $k -Value $props[$k] }
  New-ItemProperty -Path $keyPath -Name NoModify -Value 1 -PropertyType DWord -Force | Out-Null
  New-ItemProperty -Path $keyPath -Name NoRepair -Value 1 -PropertyType DWord -Force | Out-Null

  if ($Quiet) { "Installed WinLab $version to $InstallDir"; exit 0 }
  Add-Type -AssemblyName System.Windows.Forms
  $r = [Windows.Forms.MessageBox]::Show("WinLab $version is installed in:`n$InstallDir`n`nStart it now? (Later: Start menu > WinLab.)", 'WinLab setup', 'YesNo', 'Information')
  if ($r -eq 'Yes') { Start-Process -FilePath $exe -WorkingDirectory $InstallDir }
  exit 0
} catch {
  Say ("WinLab could not be installed:`n" + $_.Exception.Message) 'WinLab setup' 'Error'
  exit 1
}
