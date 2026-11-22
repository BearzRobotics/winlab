<#
.SYNOPSIS
  Builds the WinLab release: a portable zip and a self-extracting installer, with stock Windows tools only
  (zig for the exe, System.IO.Compression for the zip, IExpress for the installer exe).
.PARAMETER OutDir  Where to put the results (default: dist\ in the repository; it is git-ignored).
.PARAMETER Version Overrides the version read from src\app\version.zig.
.PARAMETER NoBuild Reuse the exe already in <OutDir>\build\bin (skip the zig build).
.NOTES
  The installer exe is NOT code-signed, so Windows SmartScreen will warn on first run until it is signed.
  Its file name deliberately has no "setup" or "install" in it: Windows' installer detection would otherwise
  ask for administrator rights, and this installer is per-user.
#>
param(
  [string]$OutDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'),
  [string]$Version = '',
  [switch]$NoBuild
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not $Version) {
  $m = Select-String -Path (Join-Path $repo 'src\app\version.zig') -Pattern 'app_version = "([^"]+)"'
  $Version = $m.Matches[0].Groups[1].Value
}
"Building WinLab $Version into $OutDir"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$build = Join-Path $OutDir 'build'
$stage = Join-Path $OutDir 'stage\WinLab'
$pack = Join-Path $OutDir 'pack'

if (-not $NoBuild) {
  Push-Location $repo
  try { & zig build -Doptimize=ReleaseSafe --prefix $build; if ($LASTEXITCODE) { throw 'zig build failed' } } finally { Pop-Location }
}
$exe = Join-Path $build 'bin\winlab.exe'
if (-not (Test-Path $exe)) { throw "No exe at $exe" }

# Validate the content that will ship, using the exe that will ship.
& $exe check (Join-Path $repo 'course') | Select-Object -Last 4
if ($LASTEXITCODE) { throw 'winlab check reported problems' }

# Stage: program + content. Nothing else (no VM disks, ISOs, keys or scratch files).
foreach ($p in $stage, $pack) { if (Test-Path $p) { Remove-Item -LiteralPath $p -Recurse -Force } }
New-Item -ItemType Directory -Force -Path $stage, $pack | Out-Null
Copy-Item $exe $stage
foreach ($d in 'course', 'labs', 'paths', 'quizzes', 'certs') { Copy-Item -LiteralPath (Join-Path $repo $d) -Destination $stage -Recurse }
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'images') | Out-Null
Copy-Item (Join-Path $repo 'images\catalog.toml') (Join-Path $stage 'images')
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'docs') | Out-Null
Copy-Item (Join-Path $repo 'docs\learning-paths.md') (Join-Path $stage 'docs')
Copy-Item (Join-Path $repo 'README.md') $stage
Copy-Item (Join-Path $repo 'installer\GETTING-STARTED.md') $stage
Set-Content -Path (Join-Path $stage 'VERSION.txt') -Value $Version -Encoding ASCII
$files = Get-ChildItem $stage -Recurse -File
"Staged {0} files, {1:N1} MB" -f $files.Count, (($files | Measure-Object Length -Sum).Sum / 1MB)

Add-Type -AssemblyName System.IO.Compression.FileSystem
# Portable zip: unzip anywhere and run winlab.exe (it finds course\ next to itself).
$portable = Join-Path $OutDir "WinLab-$Version-portable.zip"
if (Test-Path $portable) { Remove-Item $portable -Force }
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $portable, [IO.Compression.CompressionLevel]::Optimal, $true)

# Installer payload and the self-extracting installer (IExpress).
$payload = Join-Path $pack 'payload.zip'
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $payload, [IO.Compression.CompressionLevel]::Optimal, $false)
Copy-Item (Join-Path $PSScriptRoot 'Install-WinLab.ps1') $pack
Copy-Item (Join-Path $PSScriptRoot 'Uninstall-WinLab.ps1') $pack
$target = Join-Path $OutDir "WinLab-$Version-x64.exe"
if (Test-Path $target) { Remove-Item $target -Force }
$sed = Join-Path $pack 'winlab.sed'
@"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=%AdminQuietInstCmd%
UserQuietInstCmd=%UserQuietInstCmd%
SourceFiles=SourceFiles
[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$target
FriendlyName=WinLab $Version
AppLaunched=cmd /c powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File Install-WinLab.ps1
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
FILE0="payload.zip"
FILE1="Install-WinLab.ps1"
FILE2="Uninstall-WinLab.ps1"
[SourceFiles]
SourceFiles0=$pack\
[SourceFiles0]
%FILE0%=
%FILE1%=
%FILE2%=
"@ | Set-Content -Path $sed -Encoding ASCII
& "$env:SystemRoot\System32\iexpress.exe" /N /Q $sed | Out-Null
# IExpress returns before it finishes writing; wait for the file.
for ($i = 0; $i -lt 60 -and -not (Test-Path $target); $i++) { Start-Sleep 1 }
if (-not (Test-Path $target)) { throw 'IExpress did not produce the installer' }

$hashes = foreach ($f in $target, $portable) { '{0}  {1}' -f (Get-FileHash $f -Algorithm SHA256).Hash.ToLower(), (Split-Path -Leaf $f) }
$hashes | Set-Content (Join-Path $OutDir "WinLab-$Version-SHA256.txt") -Encoding ASCII
Get-ChildItem $OutDir -File | ForEach-Object { '{0,10:N1} MB  {1}' -f ($_.Length / 1MB), $_.Name }
$hashes
