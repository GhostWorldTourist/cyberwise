# Get-ModInventory.ps1 -- every mod actually deployed, what layers it touches,
# and its Nexus id where one can be derived.
#
#     .\Get-ModInventory.ps1 -GameRoot '<path>'
#     .\Get-ModInventory.ps1 -GameRoot '<path>' -Json -OutFile inventory.json
#
# WHY THE DEPLOYMENT MANIFEST AND NOT THE STAGING FOLDER
#
# Staging holds everything ever installed, enabled or not. The manifest at
# <GameRoot>\vortex.deployment.json holds what is on disk RIGHT NOW, file by
# file, each stamped with the staging mod it came from. That is the same
# distinction that makes a suspect list worthless when it names an uninstalled
# mod: staged is not deployed, and only one of the two is a fact about the
# running game.
#
# The manifest is also the only source that maps a deployed file back to its
# owner. Nothing on disk in archive\pc\mod says which mod put a file there.
#
# NEXUS IDS ARE DERIVED, NOT LOOKED UP
#
# Vortex names staging folders after the download, and two conventions appear
# here:
#
#   Immersive Bullet Holes-15309-2k-1718581479      <- Name-<id>-<version>-<stamp>
#   0-Engine Pure CET 27967 0.18.6 2026-06-29T14-25Z <- Name <id> <version> <date>
#
# Both are conventions, not guarantees. A mod installed from a local zip or
# built by hand has no id at all - CETMonkey is one. So the id is reported as
# DERIVED with the pattern that produced it, and an absent id is reported as
# absent rather than guessed. An id guessed wrong points every later lookup at
# somebody else's mod page, which is worse than having none.

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $GameRoot,
    [switch] $Json,
    [string] $OutFile
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $GameRoot)) { throw "no such game root: $GameRoot" }

$manifestPath = Join-Path $GameRoot 'vortex.deployment.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "no vortex.deployment.json at $manifestPath - this install is not Vortex-deployed, or has never been deployed"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$files = @($manifest.files)
if ($files.Count -eq 0) { throw 'the deployment manifest lists no files' }

# Which layer a relative path belongs to. Kept in step with the "Know where each
# kind of mod lives" table in the cyberwise front door - a path that falls
# through to 'other' is a layer nobody has taught this tool about yet, and is
# reported as such rather than silently dropped.
function Get-Layer([string] $relPath) {
    $p = $relPath.ToLower() -replace '/', '\'
    if ($p -like 'archive\pc\mod\*') { return 'archive' }
    if ($p -like 'mods\*') { return 'REDmod' }
    if ($p -like 'bin\x64\plugins\cyber_engine_tweaks\mods\*') { return 'CET' }
    if ($p -like 'red4ext\plugins\*') { return 'RED4ext' }
    if ($p -like 'r6\scripts\*') { return 'redscript' }
    if ($p -like 'r6\tweaks\*') { return 'tweak' }
    if ($p -like 'r6\input\*') { return 'input' }
    if ($p -like 'r6\config\*') { return 'config' }
    if ($p -like 'bin\x64\plugins\*') { return 'ASI' }
    if ($p -like 'engine\*') { return 'engine' }
    return 'other'
}

# Derive the Nexus mod id from the staging folder name. Returns a pair of
# (id, pattern) so a later reader can judge the claim rather than trust it.
function Get-NexusId([string] $source) {
    if ([string]::IsNullOrWhiteSpace($source)) { return @($null, 'none') }

    # Name-<id>-<version parts>-<10-digit unix stamp>
    if ($source -match '-(\d{2,7})-[0-9][0-9a-zA-Z\-\.]*-(\d{10})$') {
        return @([int]$Matches[1], 'dash-stamp')
    }
    # Name <id> <version> <ISO date> - the collection/installer convention
    if ($source -match '\s(\d{3,7})\s+[0-9][\w\.\-]*\s+\d{4}-\d{2}-\d{2}') {
        return @([int]$Matches[1], 'space-iso')
    }
    # Name-<id>-<anything>-<stamp>, looser: still anchored on the trailing stamp
    if ($source -match '-(\d{2,7})-.*-(\d{10})$') {
        return @([int]$Matches[1], 'dash-stamp-loose')
    }
    return @($null, 'none')
}

$bySource = @{}
$unowned = 0

foreach ($f in $files) {
    $src = [string]$f.source
    if ([string]::IsNullOrWhiteSpace($src)) { $unowned++; continue }
    if (-not $bySource.ContainsKey($src)) {
        $bySource[$src] = [pscustomobject]@{
            Source    = $src
            FileCount = 0
            Layers    = New-Object System.Collections.Generic.HashSet[string]
            Archives  = New-Object System.Collections.Generic.List[string]
            Configs   = New-Object System.Collections.Generic.List[string]
            Roots     = New-Object System.Collections.Generic.HashSet[string]
        }
    }
    $entry = $bySource[$src]
    $entry.FileCount++
    $rel = [string]$f.relPath
    $layer = Get-Layer $rel
    [void]$entry.Layers.Add($layer)

    $leaf = Split-Path $rel -Leaf
    if ($leaf -like '*.archive') { $entry.Archives.Add($leaf) }

    # Files a settings question would actually be answered from.
    if ($leaf -match '\.(yaml|yml|json|ini|xml|reds|lua)$' -and $layer -notin @('archive')) {
        if ($entry.Configs.Count -lt 40) { $entry.Configs.Add($rel) }
    }

    # The mod's own folder under a layer root, which is how it is named on disk.
    $parts = ($rel -replace '/', '\') -split '\\'
    if ($layer -eq 'CET' -and $parts.Count -ge 6) { [void]$entry.Roots.Add($parts[5]) }
    elseif ($layer -eq 'redscript' -and $parts.Count -ge 3) { [void]$entry.Roots.Add($parts[2]) }
    elseif ($layer -eq 'RED4ext' -and $parts.Count -ge 3) { [void]$entry.Roots.Add($parts[2]) }
    elseif ($layer -eq 'tweak' -and $parts.Count -ge 3) { [void]$entry.Roots.Add($parts[2]) }
}

$rows = foreach ($src in ($bySource.Keys | Sort-Object)) {
    $e = $bySource[$src]
    $idPair = Get-NexusId $src
    [pscustomobject]@{
        Source      = $e.Source
        NexusModId  = $idPair[0]
        IdPattern   = $idPair[1]
        FileCount   = $e.FileCount
        Layers      = @($e.Layers | Sort-Object)
        Archives    = @($e.Archives)
        ConfigFiles = @($e.Configs)
        ModFolders  = @($e.Roots | Sort-Object)
    }
}

$rows = @($rows)
$withId = @($rows | Where-Object { $null -ne $_.NexusModId })

if ($OutFile) {
    $rows | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutFile -Encoding utf8NoBOM
}

if ($Json) {
    $rows | ConvertTo-Json -Depth 6
    exit 0
}

Write-Host ('deployed mods: ' + $rows.Count) -ForegroundColor Cyan
Write-Host ('  from ' + $files.Count + ' deployed file(s), manifest written ' + $manifest.deploymentTime) -ForegroundColor DarkGray
Write-Host ('  Nexus id derived for ' + $withId.Count + ' of ' + $rows.Count) -ForegroundColor DarkGray
if ($unowned -gt 0) {
    Write-Host ('  ' + $unowned + ' file(s) have no source and belong to no mod') -ForegroundColor Yellow
}
Write-Host ''
Write-Host 'by layer:' -ForegroundColor Cyan
$layerCounts = @{}
foreach ($r in $rows) { foreach ($l in $r.Layers) { $layerCounts[$l] = 1 + ([int]$layerCounts[$l]) } }
foreach ($l in ($layerCounts.Keys | Sort-Object { -$layerCounts[$_] })) {
    Write-Host ('  {0,-12} {1}' -f $l, $layerCounts[$l])
}
Write-Host ''
Write-Host 'id derivation:' -ForegroundColor Cyan
$patCounts = @{}
foreach ($r in $rows) { $patCounts[$r.IdPattern] = 1 + ([int]$patCounts[$r.IdPattern]) }
foreach ($p in ($patCounts.Keys | Sort-Object { -$patCounts[$_] })) {
    Write-Host ('  {0,-18} {1}' -f $p, $patCounts[$p])
}
if ($OutFile) { Write-Host ''; Write-Host ('written: ' + $OutFile) -ForegroundColor Green }
exit 0
