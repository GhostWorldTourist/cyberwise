# New-ReleasePackage.ps1 -- build the zip a Nexus user downloads.
#
# Cyberwise is a set of agent skills, not a game mod: nothing here goes into
# archive\pc\mod and Vortex has no idea what to do with it. So the package is
# what somebody needs to INSTALL the skills and nothing else - the skills
# themselves, the installer that links them, the licence, and a readme that
# opens with what to run.
#
# WHAT IS DELIBERATELY LEFT OUT
#
#   tests/         a user cannot run them and they are a third of the repo
#   docs/images    screenshots for the GitHub page
#   .git*          history, hooks, CI
#   app/           the tray build, which needs a toolchain
#
# The upstream manifest IS included, because the guard that reads it runs on
# every tool and a package without it reports itself as unverifiable.

[CmdletBinding()]
param(
    # NOT defaulted from $PSScriptRoot: that is EMPTY inside a param block on
    # PowerShell 5.1 when the script is run with -File, so the default would
    # silently resolve to the wrong place. Resolved in the body instead.
    [string] $Root,
    [string] $OutDir,
    # Defaults to the newest tag, so a release built after tagging is labelled
    # to match it rather than to match today.
    [string] $Version
)

$ErrorActionPreference = 'Stop'

if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }

if (-not $Version) {
    Push-Location $Root
    try { $Version = (git describe --tags --abbrev=0 2>$null) } catch { }
    Pop-Location
}
if (-not $Version) { $Version = (Get-Date -Format 'yyyy.MM.dd') }
if (-not $OutDir)  { $OutDir  = Join-Path $Root 'build' }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("cyberwise-pkg-" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $stage | Out-Null

try {
    Copy-Item -LiteralPath (Join-Path $Root 'skills')     -Destination $stage -Recurse
    foreach ($f in 'install.ps1', 'LICENSE', 'README.md') {
        $p = Join-Path $Root $f
        if (Test-Path -LiteralPath $p) { Copy-Item -LiteralPath $p -Destination $stage }
    }

    # A Nexus user lands in an unzipped folder with no context. This is the
    # first thing they see, and it says the one command that matters.
    $install = @"
Cyberwise $Version
==================

A set of skills that teach an AI coding agent - Claude Code, or Codex - how to
diagnose and repair a modded Cyberpunk 2077 install.

This is NOT a game mod. Nothing here is installed with Vortex or MO2, and
nothing goes into the game folder. It installs into your agent.

INSTALL
-------

Open PowerShell in this folder and run:

    .\install.ps1

That links every skill into your agent's skills directory. Then start a new
session and ask it something about your install - it will load what it needs.

To remove:

    .\install.ps1 -Remove

WHAT YOU GET
------------

$( (Get-ChildItem (Join-Path $Root 'skills') -Directory | Sort-Object Name | ForEach-Object { "  $($_.Name)" }) -join "`r`n" )

Start with `cyberwise` - it is the front door and routes to the rest.

REQUIREMENTS
------------

Windows, PowerShell 5.1 or later (7+ preferred), and an agent that reads
skills from a skills directory. Some tools want WolvenKit CLI; each one says
so when it needs it.

README.md has the full description.
"@
    Set-Content -LiteralPath (Join-Path $stage 'INSTALL.txt') -Value $install -Encoding UTF8

    $zip = Join-Path $OutDir ("Cyberwise-$Version.zip")
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip

    $mb = [math]::Round((Get-Item $zip).Length / 1MB, 2)
    $skills = (Get-ChildItem (Join-Path $stage 'skills') -Directory).Count
    $tools  = (Get-ChildItem (Join-Path $stage 'skills') -Recurse -Filter '*.ps1').Count
    Write-Host ""
    Write-Host "built  $zip"
    Write-Host ("       {0} skills, {1} tools, {2} MB" -f $skills, $tools, $mb)
    Write-Host ""
    Write-Host "Upload that to Nexus. It contains no game files and touches no game folder."
}
finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}
