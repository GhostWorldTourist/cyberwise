<#
.SYNOPSIS
    Generate a readable manifest of an installed Cyberpunk 2077 mod list.

.DESCRIPTION
    Answers "what is all this stuff and what does it do", which no mod manager
    shows you in one place.

    Works in two tiers:

      Tier 1 (always, offline)
        Mod name, Nexus ID and URL, version, install date, and what the mod
        actually deploys - archives, redscript, CET, tweaks, REDmod, ASI, input.
        All of this comes from the staging folder name and layout, so it needs
        no credentials and no network.

      Tier 2 (optional, -NexusApiKey)
        Adds the one-line summary, category, author and the adult-content flag
        straight from Nexus. Responses are cached to disk, so a second run costs
        nothing and you can re-render the report freely.

    Why the folder name is enough for tier 1: managers encode
    <Display Name>-<NexusID>-<version>-<timestamp> when they install from Nexus.
    That single convention yields the name, a working URL and the install date.

.PARAMETER NexusApiKey
    Personal API key from nexusmods.com/users/myaccount?tab=api. Without it the
    manifest still generates; it just has no descriptions and NSFW filtering
    falls back to a name heuristic that is clearly labelled as approximate.

.PARAMETER HideNSFW
    Omit adult-flagged mods entirely. With an API key this uses Nexus's own
    contains_adult_content flag. Without one it uses a keyword heuristic, which
    WILL miss things - the report says so rather than implying certainty.

.EXAMPLE
    .\New-ModManifest.ps1
    .\New-ModManifest.ps1 -NexusApiKey abc123 -HideNSFW -Out manifest.md
#>

[CmdletBinding()]
param(
    [string] $StagingRoot,
    [string] $GameRoot,
    [string] $Game        = 'cyberpunk2077',
    [string] $NexusApiKey,
    [switch] $HideNSFW,
    [string] $Out         = "$PSScriptRoot\mod-manifest.md",
    [string] $CachePath   = "$PSScriptRoot\.nexus-cache.json",
    [string] $OverridePath = (Join-Path $PSScriptRoot 'nsfw-overrides.json'),
    [int]    $ThrottleMs  = 120
)

# ---------------------------------------------------------------- discovery --

if (-not $StagingRoot) {
    $guess = Join-Path $env:APPDATA "Vortex\$Game\mods"
    if (Test-Path $guess) { $StagingRoot = $guess }
}
if (-not $StagingRoot -or -not (Test-Path $StagingRoot)) {
    throw "Could not find a staging root. Pass -StagingRoot explicitly. (MO2 users: point this at MO2's mods folder.)"
}

Write-Host "staging: $StagingRoot" -ForegroundColor DarkGray

# ------------------------------------------------------------------ parsing --

# <Display Name>-<NexusID>-<version>-<unix timestamp>
# The version segment is NOT always numeric - real examples include "2k",
# "1-0-beta", "v2". Anchor on the trailing 10-digit unix timestamp and the
# numeric id instead, and let the version be anything between them.
$namePattern = '^(?<name>.+?)-(?<id>\d+)-(?<ver>.*?)-(?<ts>\d{10})$'

# Where a mod deploys tells you what kind of mod it is - more reliably than its
# name does. Order matters: first match wins for the primary label.
$footprintMap = [ordered]@{
    'archive\pc\mod'                              = 'archive'
    'archive\pc\patch'                             = 'archive'
    'mods'                                         = 'REDmod'
    'r6\scripts'                                   = 'redscript'
    'r6\tweaks'                                    = 'tweak'
    'r6\input'                                     = 'input'
    'bin\x64\plugins\cyber_engine_tweaks\mods'     = 'CET'
    'red4ext\plugins'                              = 'RED4ext'
    'bin\x64\plugins'                              = 'ASI'
}

function Get-Footprint {
    param([string]$Dir)
    $hits = New-Object System.Collections.Generic.List[string]
    foreach ($rel in $footprintMap.Keys) {
        $p = Join-Path $Dir $rel
        if (-not (Test-Path -LiteralPath $p)) { continue }

        # bin\x64\plugins is an ANCESTOR of the CET mods path, so a plain
        # Test-Path tags every CET mod as an ASI plugin too. Only call it ASI if
        # something lives there that is not the cyber_engine_tweaks subtree.
        if ($rel -eq 'bin\x64\plugins') {
            $other = Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -ne 'cyber_engine_tweaks' }
            if (-not $other) { continue }
        }

        $label = $footprintMap[$rel]
        if (-not $hits.Contains($label)) { $hits.Add($label) }
    }
    if ($hits.Count -eq 0) { $hits.Add('other') }
    return $hits
}

$mods = New-Object System.Collections.Generic.List[object]

foreach ($d in (Get-ChildItem -LiteralPath $StagingRoot -Directory)) {
    $entry = [ordered]@{
        Folder    = $d.Name
        Name      = $d.Name
        NexusId   = $null
        Version   = $null
        Installed = $null
        Footprint = (Get-Footprint $d.FullName)
        Files     = (Get-ChildItem -LiteralPath $d.FullName -Recurse -File -ErrorAction SilentlyContinue).Count
        Summary   = $null
        Category  = $null
        Author    = $null
        Adult     = $null
    }
    if ($d.Name -match $namePattern) {
        $entry.Name      = $matches['name']
        $entry.NexusId   = [int]$matches['id']
        $entry.Version   = ($matches['ver'] -replace '-', '.')
        $entry.Installed = [DateTimeOffset]::FromUnixTimeSeconds([int64]$matches['ts']).LocalDateTime
    }
    $mods.Add([pscustomobject]$entry)
}

Write-Host "found $($mods.Count) mods; $(($mods | Where-Object NexusId).Count) carry a Nexus ID" -ForegroundColor DarkGray

# -------------------------------------------------------------- enrichment --

$cache = @{}
if (Test-Path $CachePath) {
    try {
        (Get-Content $CachePath -Raw | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { $cache[$_.Name] = $_.Value }
        Write-Host "cache: $($cache.Count) entries" -ForegroundColor DarkGray
    } catch { Write-Warning "cache unreadable, starting fresh" }
}

if ($NexusApiKey) {
    $ids = $mods | Where-Object NexusId | Select-Object -ExpandProperty NexusId -Unique
    $todo = $ids | Where-Object { -not $cache.ContainsKey("$_") }
    Write-Host "Nexus: $($ids.Count) unique ids, $($todo.Count) to fetch" -ForegroundColor DarkGray

    $n = 0
    foreach ($id in $todo) {
        $n++
        Write-Progress -Activity 'Fetching from Nexus' -Status "$n / $($todo.Count)" -PercentComplete (100 * $n / [Math]::Max(1, $todo.Count))
        $url = "https://api.nexusmods.com/v1/games/$Game/mods/$id.json"
        try {
            $r = Invoke-RestMethod -Uri $url -Headers @{ APIKEY = $NexusApiKey } -TimeoutSec 20
            $cache["$id"] = [pscustomobject]@{
                name     = $r.name
                summary  = $r.summary
                author   = $r.author
                category = $r.category_id
                adult    = [bool]$r.contains_adult_content
                status   = 'ok'
            }
        } catch {
            $code = $_.Exception.Response.StatusCode.value__
            if ($code -eq 429) { Write-Warning "rate limited at id $id - stopping early, re-run later"; break }
            $cache["$id"] = [pscustomobject]@{ status = "error $code" }
        }
        Start-Sleep -Milliseconds $ThrottleMs
    }
    Write-Progress -Activity 'Fetching from Nexus' -Completed
    $cache | ConvertTo-Json -Depth 4 | Set-Content $CachePath -Encoding UTF8
}

# Apply whatever the cache holds, whether fetched now or previously.
foreach ($m in $mods) {
    if ($m.NexusId -and $cache.ContainsKey("$($m.NexusId)")) {
        $c = $cache["$($m.NexusId)"]
        if ($c.status -eq 'ok') {
            $m.Summary  = $c.summary
            $m.Author   = $c.author
            $m.Category = $c.category
            $m.Adult    = $c.adult
        }
    }
}

# ------------------------------------------------------------------- NSFW ----

# Fallback only. Deliberately conservative in what it claims: it is a name
# match, it will miss mods whose names are innocuous, and the report says so.
#
# Two lessons are baked into this list. Adult mods are often named for a place
# or a character rather than for their content - a venue, a club, a braindance -
# so location and euphemism terms matter as much as anatomy. And the list will
# still be wrong in both directions, which is what the override file is for.
$nsfwWords = @(
    # explicit
    'nude','nudity','naked','nsfw','sex','sexual','erotic','porn','lewd',
    'hentai','xxx','fetish','bdsm','orgasm',
    # anatomy
    'genital','penis','vagina','breast','nipple','boob','dick','cock',
    'pubic','titty','areola',
    # garments that in practice mark adult mods
    'lingerie','panties','topless','underwear',
    # sex work, venues and euphemism - the category keywords miss most often
    'joytoy','brothel','strip','escort','stripper','pleasures','pleasure',
    'jig jig','jigjig','licks club','clouds','cloud - ','braindance',
    'hotscenes','shower','milk','tongue',
    # body-mod shorthand
    'busty','thicc','curvy','jiggle','onlyfans','adult'
)
function Test-NsfwByName { param([string]$Name)
    $l = $Name.ToLower()
    foreach ($w in $nsfwWords) { if ($l -match [regex]::Escape($w)) { return $true } }
    return $false
}

# Overrides, because no keyword list gets both directions right. Tactical
# clothing mods legitimately contain "underwear"; adult mods legitimately have
# innocuous names. A small hand-maintained file beats endlessly tuning regexes.
#
# Format (all fields optional):
#   { "forceAdult": { "ids": [123], "names": ["exact or *wildcard*"] },
#     "forceSafe":  { "ids": [456], "names": ["Zenitex Underwear*"] } }
$override = $null
if (Test-Path $OverridePath) {
    try { $override = Get-Content $OverridePath -Raw | ConvertFrom-Json }
    catch { Write-Warning "override file unreadable: $OverridePath" }
}
function Test-Override {
    param($Mod, $Rule)
    if (-not $Rule) { return $false }
    if ($Rule.ids -and $Mod.NexusId -and ($Rule.ids -contains $Mod.NexusId)) { return $true }
    if ($Rule.names) {
        foreach ($pat in $Rule.names) { if ($Mod.Name -like $pat) { return $true } }
    }
    return $false
}

$heuristicUsed = -not $NexusApiKey
foreach ($m in $mods) {
    if ($null -eq $m.Adult) { $m.Adult = Test-NsfwByName $m.Name }
}

# Propagate the flag across a shared Nexus ID. One Nexus page carries one adult
# flag, but a page can ship many separately-named files - and those file names
# are frequently innocuous. Without this, an adult mod's optional add-ons sail
# straight past the filter: a set of character plugins whose parent page is
# adult-flagged were each named only for the character.
$flaggedIds = @{}
foreach ($m in $mods) { if ($m.NexusId -and $m.Adult) { $flaggedIds["$($m.NexusId)"] = $true } }
# Propagation cuts both ways. It catches an adult mod's innocuously-named
# add-ons, but it also drags in genuinely safe siblings that merely share a
# Nexus page - a base skin texture sharing an ID with an adult edition of
# itself, for instance. So record who was caught this way and print the list:
# hiding is the safer default for this feature, but the user needs to be able
# to audit it and exempt the mistakes.
$propagatedNames = New-Object System.Collections.Generic.List[string]
foreach ($m in $mods) {
    if ($m.NexusId -and -not $m.Adult -and $flaggedIds.ContainsKey("$($m.NexusId)")) {
        $m.Adult = $true
        $propagatedNames.Add($m.Name)
    }
}
$propagated = $propagatedNames.Count

# Overrides win over everything, including the API flag - they are the user's
# explicit judgement about their own install.
$forcedAdult = 0; $forcedSafe = 0
foreach ($m in $mods) {
    if (Test-Override $m $override.forceAdult) { if (-not $m.Adult) { $forcedAdult++ }; $m.Adult = $true }
    elseif (Test-Override $m $override.forceSafe) { if ($m.Adult) { $forcedSafe++ }; $m.Adult = $false }
}

$hidden = 0
if ($HideNSFW) {
    $before = $mods.Count
    $mods = @($mods | Where-Object { -not $_.Adult })
    $hidden = $before - $mods.Count
}

# ------------------------------------------------------------------ report ---

$sb = New-Object System.Text.StringBuilder
function W($t = '') { [void]$sb.AppendLine($t) }

W "# Cyberpunk 2077 mod manifest"
W ""
W "Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') from ``$StagingRoot``."
W ""
W "- **$($mods.Count)** mods listed"
if ($NexusApiKey) {
    $desc = ($mods | Where-Object Summary).Count
    W "- **$desc** enriched with Nexus descriptions"
} else {
    W "- No API key supplied, so there are no descriptions. Pass ``-NexusApiKey`` to add them."
}
if ($HideNSFW) {
    $how = if ($heuristicUsed) {
        "by **name heuristic plus shared-Nexus-ID propagation**. This is approximate and *will* miss mods whose names give nothing away - supply ``-NexusApiKey`` to filter on Nexus's own flag instead"
    } else {
        "using Nexus's own ``contains_adult_content`` flag"
    }
    W "- **$hidden** adult-flagged mods omitted, $how"
    if ($propagated -gt 0) {
        W "- of those, **$propagated** were caught only by sharing a Nexus ID with a flagged mod:"
        W ""
        foreach ($n in ($propagatedNames | Sort-Object)) { W "  - $n" }
        W ""
        W "  Check that list. A safe mod sharing a Nexus page with an adult one gets"
        W "  hidden too; add any mistakes to ``forceSafe`` in the override file."
    }
    if ($forcedAdult -gt 0) { W "- **$forcedAdult** added by override file" }
    if ($forcedSafe -gt 0) { W "- **$forcedSafe** exempted by override file (false positives)" }
}
W ""

$order = @('archive','redscript','CET','tweak','REDmod','RED4ext','ASI','input','other')
$byKind = @{}
foreach ($m in $mods) {
    $primary = ($order | Where-Object { $m.Footprint -contains $_ } | Select-Object -First 1)
    if (-not $primary) { $primary = 'other' }
    if (-not $byKind.ContainsKey($primary)) { $byKind[$primary] = New-Object System.Collections.Generic.List[object] }
    $byKind[$primary].Add($m)
}

foreach ($kind in $order) {
    if (-not $byKind.ContainsKey($kind)) { continue }
    $list = $byKind[$kind] | Sort-Object Name
    W "## $kind  ($($list.Count))"
    W ""
    foreach ($m in $list) {
        $title = $m.Name
        if ($m.NexusId) {
            $title = "[$($m.Name)](https://www.nexusmods.com/$Game/mods/$($m.NexusId))"
        }
        $bits = @()
        if ($m.Version)   { $bits += "v$($m.Version)" }
        if ($m.Installed) { $bits += $m.Installed.ToString('yyyy-MM-dd') }
        if ($m.Footprint.Count -gt 1) { $bits += ($m.Footprint -join '+') }
        $bits += "$($m.Files) files"
        $meta = ($bits -join ' · ')

        W "**$title**"
        W "<sub>$meta</sub>"
        if ($m.Summary) {
            $s = ($m.Summary -replace '\s+', ' ').Trim()
            if ($s.Length -gt 300) { $s = $s.Substring(0, 297) + '...' }
            W ""
            W $s
        }
        W ""
    }
}

W "---"
W ""
W "Tier 1 data (name, id, version, install date, footprint) is read from staging"
W "folder names and layout. Tier 2 (summary, author, adult flag) comes from the"
W "Nexus v1 API and is cached in ``$(Split-Path $CachePath -Leaf)`` so re-runs are free."

Set-Content -LiteralPath $Out -Value $sb.ToString() -Encoding UTF8
Write-Host "wrote $Out" -ForegroundColor Green
