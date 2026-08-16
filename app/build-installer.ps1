# build-installer.ps1 -- produce the setup exe.
#
#     .\build-installer.ps1
#
# Builds the tray app first, then compiles the Inno Setup script. Output lands
# in .\dist\Cyberwise-Setup-<version>.exe.
#
# Inno Setup itself is not a build dependency anyone should have to hunt for:
#     winget install --id JRSoftware.InnoSetup
# It installs per-user by default, which is why the search below looks in
# LocalAppData as well as the Program Files locations.

[CmdletBinding()]
param(
    [string] $Iscc,
    [switch] $SkipAppBuild
)

$ErrorActionPreference = 'Stop'

if (-not $SkipAppBuild) {
    Write-Host 'building the tray app...' -ForegroundColor DarkGray
    & (Join-Path $PSScriptRoot 'build.ps1') | Write-Host
}

if (-not $Iscc) {
    $Iscc = @(
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $Iscc) {
    throw "Inno Setup not found. Install it with:  winget install --id JRSoftware.InnoSetup"
}

$iss = Join-Path $PSScriptRoot 'installer\cyberwise.iss'
$out = Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Path $out -Force | Out-Null

Write-Host "compiling $iss" -ForegroundColor DarkGray
$log = & $Iscc $iss 2>&1
if ($LASTEXITCODE -ne 0) {
    $log | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkRed }
    throw "ISCC failed (exit $LASTEXITCODE)"
}

$exe = Get-ChildItem -LiteralPath $out -Filter 'Cyberwise-Setup-*.exe' |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $exe) { throw "ISCC reported success but no setup exe is in $out" }

Write-Host ("built {0}  ({1} MB)" -f $exe.FullName, [math]::Round($exe.Length / 1MB, 2)) -ForegroundColor Green
Write-Host ''
Write-Host 'It is NOT code-signed, so SmartScreen will warn on first run.' -ForegroundColor Yellow
Write-Host 'It installs per-user and never asks for admin.' -ForegroundColor DarkGray
