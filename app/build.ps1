# build.ps1 -- compile CyberwiseTray.exe.
#
#     .\build.ps1              # build to .\bin\CyberwiseTray.exe
#     .\build.ps1 -Run         # build and launch it
#
# NO SDK REQUIRED, on purpose twice over.
#
# 1. It builds with the C# compiler that ships in the .NET Framework, which is
#    already on every Windows box - so anyone can build this without installing
#    a toolchain first.
# 2. It targets .NET Framework 4.8, which ships with Windows 10 1903+ and
#    Windows 11 - so the people who RUN it install no runtime either.
#
# A .NET 8/9 build would be a nicer development experience and would hand every
# user either a runtime prompt or a ~70 MB self-contained binary. For an audience
# whose defining trait is being put off by setup, that trade is the wrong way
# round.

[CmdletBinding()]
param(
    [string] $OutDir,
    [switch] $Run
)

# $PSScriptRoot is EMPTY inside a param default on Windows PowerShell 5.1
# when the script is run with -File or dot-sourced - it is only populated
# under the call operator, and pwsh 7 populates it in every case. So the
# default below is resolved HERE, where it is correct on both engines and
# by every invocation route. See cyberwise/references/environment.md.

if (-not $OutDir) { $OutDir = (Join-Path $PSScriptRoot 'bin') }

$ErrorActionPreference = 'Stop'

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) {
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
if (-not (Test-Path -LiteralPath $csc)) {
    throw "No .NET Framework C# compiler found. Expected csc.exe under $env:WINDIR\Microsoft.NET."
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$exe = Join-Path $OutDir 'CyberwiseTray.exe'

# A running tray holds a lock on its own exe, and csc fails with "the process
# cannot access the file" - which reads like a permissions problem rather than
# "your app is running". Stop only the instance we are about to overwrite,
# matched by path, so a copy running from somewhere else is left alone.
Get-Process CyberwiseTray -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path -eq $exe } |
    ForEach-Object {
        Write-Host "stopping the running tray (pid $($_.Id)) so its exe can be replaced" -ForegroundColor DarkGray
        $_ | Stop-Process -Force
    }
Start-Sleep -Milliseconds 300
$src = Join-Path $PSScriptRoot 'CyberwiseTray.cs'

# /target:winexe = no console window flashing up behind the tray icon.
$refs = @(
    'System.dll', 'System.Core.dll', 'System.Drawing.dll',
    'System.Windows.Forms.dll', 'System.Management.dll'
) | ForEach-Object { "/r:$_" }

Write-Host "compiling $src" -ForegroundColor DarkGray
& $csc /nologo /target:winexe /optimize+ /out:"$exe" $refs "$src"
if ($LASTEXITCODE -ne 0) { throw "compile failed (csc exit $LASTEXITCODE)" }

# Ship the watcher beside the exe so a copied bin\ folder is self-sufficient -
# Config.FillDefaults looks here first.
$watcher = Join-Path $PSScriptRoot '..\skills\cyberwise-crashes\tools\Watch-Crashes.ps1'
if (Test-Path -LiteralPath $watcher) { Copy-Item -LiteralPath $watcher -Destination $OutDir -Force }

$size = [math]::Round((Get-Item -LiteralPath $exe).Length / 1KB, 1)
Write-Host "built $exe  ($size KB)" -ForegroundColor Green

if ($Run) {
    Get-Process CyberwiseTray -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 300
    Start-Process -FilePath $exe
    Write-Host 'launched - look for the icon in the system tray' -ForegroundColor Yellow
}
