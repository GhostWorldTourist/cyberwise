# Get-InstallHistory.ps1 -- reconstruct what changed on a modded install, after
# the fact, from evidence that is already on disk.
#
# THE PROBLEM THIS SOLVES. "It worked in December and it is broken now" is the
# most common bug report a modded install produces, and the snapshot tools
# cannot answer it, because nobody took a snapshot in December. The install
# still remembers, though, in four independent places:
#
#   Vortex staging folder mtime   when that mod was last installed or updated
#   Vortex downloads file mtime   when the archive was fetched
#   Vortex downloads FILE NAME    when Nexus published it - Vortex embeds either
#                                 a unix timestamp or an ISO date in the name
#   deployed file mtime           when it last reached the game folder
#
# The names are the part people miss. Vortex keeps every version you ever
# downloaded, so the downloads folder is a version history you did not know you
# were keeping. A mod with two archives six months apart is a mod that changed
# under you, and the second date is when.
#
# WHY THE FOLDER NAME IS NOT THE VERSION. Vortex updates a mod IN PLACE, keeping
# the original folder name while replacing the files. So a folder ending -1-26-1
# routinely holds 1.27.1. Every version this tool prints comes from the
# downloads FILENAME, never from the staging folder name, and the staging entry
# is reported by its mtime alone. Trusting a folder name for a version is how an
# afternoon gets lost.

[CmdletBinding(DefaultParameterSetName = 'Window')]
param(
    # Vortex's staging and downloads folders for this game. Note there is no
    # -GameRoot: every question this tool answers is answered from Vortex alone,
    # so it never needs to find the install and never guesses at a drive letter.
    [string] $StagingRoot,
    [string] $DownloadsRoot,

    # "It worked on this date." Everything that changed since is a suspect,
    # newest first. This is the question the tool exists for.
    [Parameter(ParameterSetName = 'Since')]
    [datetime] $WorkingOn,

    # An explicit window instead.
    [Parameter(ParameterSetName = 'Window')]
    [datetime] $From,
    [Parameter(ParameterSetName = 'Window')]
    [datetime] $To,

    # Which mod ships this file? Accepts a bare filename or a full path.
    # Vortex offers no way to search inside mods, so this is the only route
    # from a filename in a log back to something you can click.
    [Parameter(ParameterSetName = 'Owns')]
    [string] $Owns,

    # Everything known about one mod, including every version ever downloaded.
    [Parameter(ParameterSetName = 'Mod')]
    [string] $Mod,

    # Only mods that touch behaviour - scripts, tweaks, quests, archive
    # extensions. Skips pure texture and mesh replacements, which are rarely
    # the answer to "why did my game break".
    [switch] $BehaviourOnly,

    # Intersect "what changed" with "what is implicated". Given a symptom you
    # can name - a TweakDB record, a NodeRef, a method, a resource path - this
    # answers the only question that actually narrows a mass-update day: of the
    # mods that changed, which ones touch THIS? Ranking cannot find a culprit
    # among ninety simultaneous updates. Intersection can.
    [string] $Touching,

    # Cap the ranked lists. A mass-update day produces hundreds of events and
    # an uncapped list buries the one that matters.
    [int] $Top = 20,

    # Emit objects instead of a table, for piping.
    [switch] $PassThru
)

$ErrorActionPreference = 'Stop'

# --- upstream guard ---------------------------------------------------------
$cwGuard = Join-Path $PSScriptRoot '..\..\cyberwise\tools\UpstreamGuard.ps1'
if (Test-Path -LiteralPath $cwGuard) { try { . $cwGuard; Invoke-CwStartupGuard } catch { } }

# Path separators as chars, built by code point. Writing a backslash as a
# literal inside a .TrimStart() argument is a reliable way to lose it to
# whichever layer edits the file next, and TrimStart('') throws rather than
# quietly doing nothing.
$script:PathSeps = @([char]0x5C, [char]0x2F)

function Get-RelativePath {
    param([string] $Full, [string] $Root)
    return $Full.Substring($Root.Length).TrimStart($script:PathSeps)
}

# ---------------------------------------------------------------- discovery --

function Resolve-VortexRoot {
    param([string] $Explicit, [string] $Leaf)
    if ($Explicit) {
        if (-not (Test-Path -LiteralPath $Explicit)) { throw "not found: $Explicit" }
        return (Resolve-Path -LiteralPath $Explicit).Path
    }
    $appdata = $env:APPDATA
    if (-not $appdata) { throw "APPDATA is not set; pass -StagingRoot and -DownloadsRoot explicitly" }
    $p = Join-Path $appdata (Join-Path 'Vortex' $Leaf)
    if (-not (Test-Path -LiteralPath $p)) {
        throw "could not find $Leaf under $appdata\Vortex - pass it explicitly"
    }
    return (Resolve-Path -LiteralPath $p).Path
}

if (-not $StagingRoot)   { $StagingRoot   = Resolve-VortexRoot -Leaf 'cyberpunk2077\mods' }
if (-not $DownloadsRoot) { $DownloadsRoot = Resolve-VortexRoot -Leaf 'downloads\cyberpunk2077' }


# ------------------------------------------------------------------ parsing --

# Two naming schemes are in the wild, and both carry the NEXUS PUBLISH time,
# which is not the same as when it was downloaded:
#
#   Name-<modid>-<version-with-dashes>-<unix seconds>.zip
#   Name <modid> <version> <yyyy-MM-ddTHH-mmZ> <hash>.zip
#
# Locally built packages match neither and are reported with no id, which is
# correct - they have no Nexus identity.
function ConvertFrom-VortexName {
    param([string] $Name)

    $stem = $Name -replace '\.(zip|rar|7z)$', ''
    $out  = [pscustomobject]@{ Mod = $stem; ModId = $null; Version = $null; Published = $null }

    # Vortex turns dots into dashes, so a version reassembled from a folder name
    # comes back with whatever prefix the author typed still attached - "V-2-32"
    # becomes "V.2.32". Strip a leading v/V and any leading separator, so the
    # same release is not printed two different ways depending on which scheme
    # named it.
    function Restore-Version([string] $Raw) {
        if (-not $Raw) { return $null }
        $v = $Raw -replace '^[vV][.\-_]?', ''
        $v = $v -replace '^[.\-_]+', '' -replace '[.\-_]+$', ''
        if ($v) { return $v } else { return $Raw }
    }

    # scheme 2: trailing ISO-ish stamp
    if ($stem -match '^(?<n>.+?)\s+(?<id>\d{3,7})\s+(?<v>[\w.\-]+)\s+(?<d>\d{4}-\d{2}-\d{2}T\d{2}-\d{2})Z') {
        $out.Mod   = $Matches['n'].Trim()
        $out.ModId = $Matches['id']
        $out.Version = Restore-Version $Matches['v']
        $iso = $Matches['d'] -replace 'T(\d{2})-(\d{2})$', 'T$1:$2'
        try { $out.Published = [datetime]::Parse("${iso}:00Z").ToLocalTime() } catch { }
        return $out
    }

    # scheme 1: trailing unix seconds
    if ($stem -match '^(?<n>.+?)-(?<id>\d{3,7})-(?<v>.+)-(?<t>\d{9,11})$') {
        $out.Mod   = $Matches['n'].Trim()
        $out.ModId = $Matches['id']
        $out.Version = Restore-Version ($Matches['v'] -replace '-', '.')
        try { $out.Published = [datetimeoffset]::FromUnixTimeSeconds([int64]$Matches['t']).LocalDateTime } catch { }
        return $out
    }

    # a locally built package: Name-1-0 / Name-1.0
    if ($stem -match '^(?<n>.+?)-(?<v>\d[\d.\-]*)$') {
        $out.Mod = $Matches['n'].Trim()
        $out.Version = Restore-Version ($Matches['v'] -replace '-', '.')
    }
    return $out
}

# Which layers does this mod actually touch? Behaviour lives in scripts, tweaks
# and archive extensions; a .archive on its own is usually art.
function Get-ModLayers {
    param([string] $Dir)
    $layers = [ordered]@{}
    foreach ($f in Get-ChildItem -LiteralPath $Dir -Recurse -File -ErrorAction SilentlyContinue) {
        $rel = Get-RelativePath -Full $f.FullName -Root $Dir
        switch -Regex ($rel) {
            '(^|[\\/])r6[\\/]scripts[\\/]'   { $layers['reds']    = $true }
            '(^|[\\/])r6[\\/]tweaks[\\/]'    { $layers['tweak']   = $true }
            '(^|[\\/])r6[\\/]input[\\/]'     { $layers['input']   = $true }
            '(^|[\\/])red4ext[\\/]'          { $layers['red4ext'] = $true }
            'cyber_engine_tweaks[\\/]mods'   { $layers['cet']     = $true }
            '\.xl$'                          { $layers['xl']      = $true }
            '\.archive$'                     { $layers['archive'] = $true }
            '\.questphase$|\.quest$'         { $layers['quest']   = $true }
        }
    }
    return ,@($layers.Keys)
}

$behaviourLayers = @('reds', 'tweak', 'red4ext', 'cet', 'xl', 'quest', 'input')

# ---------------------------------------------------------------- inventory --

Write-Verbose "staging   : $StagingRoot"
Write-Verbose "downloads : $DownloadsRoot"

$downloads = @{}
foreach ($f in Get-ChildItem -LiteralPath $DownloadsRoot -File -ErrorAction SilentlyContinue) {
    if ($f.Extension -notmatch '^\.(zip|rar|7z)$') { continue }
    $p = ConvertFrom-VortexName -Name $f.Name
    $key = if ($p.ModId) { $p.ModId } else { $p.Mod.ToLowerInvariant() }
    if (-not $downloads.ContainsKey($key)) { $downloads[$key] = @() }
    $downloads[$key] += [pscustomobject]@{
        Mod        = $p.Mod
        ModId      = $p.ModId
        Version    = $p.Version
        Published  = $p.Published
        Downloaded = $f.LastWriteTime
        File       = $f.Name
        SizeKB     = [int]($f.Length / 1KB)
    }
}

$mods = foreach ($d in Get-ChildItem -LiteralPath $StagingRoot -Directory -ErrorAction SilentlyContinue) {
    $p = ConvertFrom-VortexName -Name $d.Name
    $key = if ($p.ModId) { $p.ModId } else { $p.Mod.ToLowerInvariant() }
    $hist = @()
    if ($downloads.ContainsKey($key)) { $hist = @($downloads[$key] | Sort-Object Downloaded) }
    $layers = Get-ModLayers -Dir $d.FullName

    [pscustomobject]@{
        Mod          = $p.Mod
        ModId        = $p.ModId
        StagingName  = $d.Name
        Installed    = $d.LastWriteTime
        Layers       = $layers
        IsBehaviour  = [bool](@($layers | Where-Object { $behaviourLayers -contains $_ }).Count)
        Downloads    = $hist
        VersionCount = $hist.Count
        # The version actually staged is unknowable from the folder name, so
        # report the newest download at or before the install instead, and say
        # so rather than pretending to certainty.
        LikelyVersion = $(
            $before = @($hist | Where-Object { $_.Downloaded -le $d.LastWriteTime.AddMinutes(5) })
            if ($before.Count) { $before[-1].Version } elseif ($hist.Count) { $hist[-1].Version } else { $null }
        )
        Path         = $d.FullName
    }
}

$mods = @($mods)
if ($BehaviourOnly) { $mods = @($mods | Where-Object IsBehaviour) }

# ------------------------------------------------------------------- modes --

function Format-Layers { param($L) if ($L -and $L.Count) { ($L -join '+') } else { '-' } }

switch ($PSCmdlet.ParameterSetName) {

    'Owns' {
        $needle = Split-Path $Owns -Leaf
        Write-Host "searching $($mods.Count) staged mod(s) for '$needle'`n"
        $found = 0
        foreach ($m in $mods) {
            $hits = @(Get-ChildItem -LiteralPath $m.Path -Recurse -File -Filter $needle -ErrorAction SilentlyContinue)
            foreach ($h in $hits) {
                $found++
                $rel = Get-RelativePath -Full $h.FullName -Root $m.Path
                Write-Host ("  {0}" -f $m.Mod) -ForegroundColor Green
                Write-Host ("     staging : {0}" -f $m.StagingName)
                Write-Host ("     file    : {0}" -f $rel)
                if ($m.ModId) { Write-Host ("     nexus   : https://www.nexusmods.com/cyberpunk2077/mods/{0}" -f $m.ModId) }
                Write-Host ("     installed {0}" -f $m.Installed.ToString('yyyy-MM-dd HH:mm'))
            }
        }
        if (-not $found) {
            Write-Host "  no staged mod ships a file named '$needle'."
            Write-Host "  if it exists in the game folder it is either base game, a framework's own"
            Write-Host "  output, or something written at runtime - none of which Vortex owns."
        }
    }

    'Mod' {
        # NOT $matches: that is PowerShell's automatic variable, written by every
        # -match in this script. Shadowing it works until something upstream of
        # the loop runs a regex, and then it silently is not your list any more.
        $hitMods = @($mods | Where-Object { $_.Mod -like "*$Mod*" -or $_.StagingName -like "*$Mod*" })
        if (-not $hitMods.Count) { Write-Host "no staged mod matching '$Mod'"; break }
        foreach ($m in $hitMods) {
            Write-Host ""
            Write-Host $m.Mod -ForegroundColor Green
            Write-Host ("  staging   : {0}" -f $m.StagingName)
            Write-Host ("  installed : {0}" -f $m.Installed.ToString('yyyy-MM-dd HH:mm'))
            Write-Host ("  layers    : {0}" -f (Format-Layers $m.Layers))
            if ($m.ModId) { Write-Host ("  nexus     : https://www.nexusmods.com/cyberpunk2077/mods/{0}" -f $m.ModId) }
            if ($m.Downloads.Count) {
                Write-Host "  every version you ever downloaded:"
                foreach ($d in $m.Downloads) {
                    $pub = if ($d.Published) { $d.Published.ToString('yyyy-MM-dd') } else { '?' }
                    Write-Host ("     v{0,-14} downloaded {1}   published {2}   {3} KB" -f `
                        $d.Version, $d.Downloaded.ToString('yyyy-MM-dd'), $pub, $d.SizeKB)
                }
                if ($m.Downloads.Count -gt 1) {
                    Write-Host ("  -> {0} versions on disk. The staged files are whichever was installed LAST;" -f $m.Downloads.Count)
                    Write-Host  "     the folder name is not evidence of which."
                }
            } else {
                Write-Host "  no archive in downloads - built locally, or the download was cleaned up."
            }
        }
    }

    default {
        if ($WorkingOn) { $From = $WorkingOn; $To = Get-Date }
        if (-not $From) { $From = (Get-Date).AddDays(-30) }
        if (-not $To)   { $To   = Get-Date }

        Write-Host ("changes between {0} and {1}" -f $From.ToString('yyyy-MM-dd'), $To.ToString('yyyy-MM-dd'))
        if ($BehaviourOnly) { Write-Host "restricted to mods that touch behaviour (scripts, tweaks, xl, quests, CET)" }
        Write-Host ""

        $events = @()
        foreach ($m in $mods) {
            if ($m.Installed -ge $From -and $m.Installed -le $To) {
                $events += [pscustomobject]@{
                    When = $m.Installed; What = 'installed/updated'; Mod = $m.Mod
                    Detail = ("v{0}  [{1}]" -f ($m.LikelyVersion ?? '?'), (Format-Layers $m.Layers))
                    Behaviour = $m.IsBehaviour
                }
            }
            foreach ($d in $m.Downloads) {
                if ($d.Downloaded -ge $From -and $d.Downloaded -le $To) {
                    $events += [pscustomobject]@{
                        When = $d.Downloaded; What = 'downloaded'; Mod = $m.Mod
                        Detail = ("v{0}" -f $d.Version); Behaviour = $m.IsBehaviour
                    }
                }
            }
        }

        if (-not $events.Count) { Write-Host "  nothing changed in that window."; break }

        $events = @($events | Sort-Object When -Descending)
        foreach ($e in $events) {
            $mark = if ($e.Behaviour) { '*' } else { ' ' }
            Write-Host ("{0} {1}  {2,-18} {3,-46} {4}" -f `
                $mark, $e.When.ToString('yyyy-MM-dd HH:mm'), $e.What, $e.Mod, $e.Detail)
        }
        Write-Host ""
        Write-Host ("{0} event(s). Lines marked * touch behaviour and are the ones worth suspecting first." -f $events.Count)

        if ($Touching) {
            Write-Host ""
            Write-Host ("of those, the ones whose files mention '{0}':" -f $Touching) -ForegroundColor Cyan
            $changed = @($mods | Where-Object {
                ($_.Installed -ge $From -and $_.Installed -le $To) -or
                @($_.Downloads | Where-Object { $_.Downloaded -ge $From -and $_.Downloaded -le $To }).Count
            })
            $textLike = '\.(reds|xl|yaml|yml|lua|json|xml|txt|ini)$'
            $any = $false
            foreach ($m in $changed) {
                $where = @()
                foreach ($f in Get-ChildItem -LiteralPath $m.Path -Recurse -File -ErrorAction SilentlyContinue) {
                    if ($f.Name -notmatch $textLike) { continue }
                    if ($f.Length -gt 8MB) { continue }
                    # .Contains, not -like: a needle such as "[NetSec]" is a
                    # character class to -like and silently matches nothing.
                    $body = [IO.File]::ReadAllText($f.FullName)
                    if ($body.Contains($Touching)) {
                        $where += Get-RelativePath -Full $f.FullName -Root $m.Path
                    }
                }
                if ($where.Count) {
                    $any = $true
                    Write-Host ("   {0}  [{1}]" -f $m.Mod, (Format-Layers $m.Layers)) -ForegroundColor Green
                    Write-Host ("      installed {0}   v{1}" -f $m.Installed.ToString('yyyy-MM-dd HH:mm'), ($m.LikelyVersion ?? '?'))
                    foreach ($w in ($where | Select-Object -First 4)) { Write-Host ("      - {0}" -f $w) }
                    if ($where.Count -gt 4) { Write-Host ("      - ... and {0} more file(s)" -f ($where.Count - 4)) }
                }
            }
            if (-not $any) {
                Write-Host ("   nothing that changed in this window mentions '{0}'." -f $Touching)
                Write-Host  "   that is a real result: it rules the window out, rather than failing to find something."
            }
        }

        # A mod with more than one download in the window changed UNDER the
        # install rather than being newly added, which is the case people miss.
        $churn = @($mods | Where-Object {
            @($_.Downloads | Where-Object { $_.Downloaded -ge $From -and $_.Downloaded -le $To }).Count -ge 1 -and
            $_.Downloads.Count -ge 2
        })
        if ($churn.Count) {
            # Rank rather than dump. On a mass-update day this list runs to
            # hundreds, and the one that broke the game is not findable by
            # scrolling. Behaviour before art, then quest/script layers before
            # plain archives, because that is the order suspicion belongs in.
            $weight = { param($m)
                $w = 0
                if ($m.IsBehaviour) { $w += 100 }
                foreach ($l in $m.Layers) {
                    switch ($l) {
                        'quest'   { $w += 40 }
                        'xl'      { $w += 20 }
                        'reds'    { $w += 20 }
                        'red4ext' { $w += 15 }
                        'tweak'   { $w += 10 }
                        'cet'     { $w += 10 }
                    }
                }
                $w
            }
            $ranked = @($churn | Sort-Object @{ e = { & $weight $_ } }, Mod -Descending)
            Write-Host ""
            Write-Host "updated in place during this window - you had an older version before:" -ForegroundColor Yellow
            Write-Host "(ranked: behaviour layers first, because art rarely breaks a save)"
            foreach ($c in ($ranked | Select-Object -First $Top)) {
                $vs = ($c.Downloads | ForEach-Object { "v$($_.Version) ($($_.Downloaded.ToString('yyyy-MM-dd')))" }) -join '  ->  '
                Write-Host ("   {0}  [{1}]" -f $c.Mod, (Format-Layers $c.Layers))
                Write-Host ("      {0}" -f $vs)
            }
            if ($ranked.Count -gt $Top) {
                Write-Host ("   ... and {0} more, mostly art. Raise -Top to see them." -f ($ranked.Count - $Top))
            }
        }
    }
}

if ($PassThru) { $mods }
