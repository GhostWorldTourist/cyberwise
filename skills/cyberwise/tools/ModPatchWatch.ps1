# ModPatchWatch.ps1 -- notice when a mod you patched or overrode has changed.
#
#     . .\tools\ModPatchWatch.ps1
#
#     Register-ModPatch -Name 'VisibleBullets Borg4a' `
#                       -UpstreamPath '<staging>\...\Items.Preset_Borg4a_Default.yaml' `
#                       -OverridePath '<staging>\zzz_Fix\...\Items.Preset_Borg4a_Default.yaml' `
#                       -Note 'author indents line 3 by 3 spaces; yaml-cpp rejects the file'
#
#     Test-ModPatches            # the sweep: has anything changed underneath us?
#     Get-ModPatch               # what is registered
#     Unregister-ModPatch -Name  # retired, author fixed it upstream
#
# WHY THIS EXISTS
#
# Fixing somebody else's mod has two failure modes and they are opposites:
#
#   An IN-PLACE PATCH is wiped by their update. Loud - the bug comes back.
#   An OVERRIDE is NOT wiped. Silent - your old copy keeps winning, and every
#   fix the author ships afterwards loses to it with nothing reporting the fact.
#
# The second is the dangerous one, and it is the reason to be careful about
# overriding whole files. But that danger comes entirely from *not noticing*.
# Record what the upstream file looked like when you patched it, and a sweep
# turns the silent failure into a loud one - at which point an override is the
# better option almost everywhere, because it also survives the update.
#
# So: register every patch and override, and run the sweep after any mod update.

# WHERE THE RECORDS LIVE, and why it is not next to this script.
#
#   %USERPROFILE%\Saved Games\CD Projekt Red\Cyberpunk 2077\Cyberwise\patches.json
#
# Beside the saves, in a namespace folder of our own - the same shape mod authors
# use for their own data there. Three reasons, and the third is the point:
#
#   1. It describes THE INSTALL, not the tooling. It belongs with the game.
#   2. It survives the tooling. Reinstalling, moving or deleting the skill does
#      not lose the record of what was patched.
#   3. **It is agent-neutral.** Claude Code and Codex both read this path, so
#      work started under one is picked up by the other. A record kept in one
#      agent's memory is invisible to the next one and is lost on a switch.
#
# NEVER put install records in the repo: they describe one person's machine.
# --- upstream guard ---------------------------------------------------------
# Advisory, and only that: silent while this copy matches what shipped, one
# short line when it does not, and it never blocks or changes an exit code.
# Rationale, and why it is deliberately not a PreToolUse hook: UpstreamGuard.ps1.
$cwGuard = Join-Path $PSScriptRoot 'UpstreamGuard.ps1'
if (Test-Path -LiteralPath $cwGuard) { try { . $cwGuard; Invoke-CwStartupGuard } catch { } }

$script:PatchStore = Join-Path $env:USERPROFILE 'Saved Games\CD Projekt Red\Cyberpunk 2077\Cyberwise\patches.json'

function Get-ModPatchStorePath { $script:PatchStore }

# One-time move from the old per-user location, so an existing record is not
# orphaned by this change.
$legacyStore = Join-Path $env:LOCALAPPDATA 'cyberwise\patches.json'
if ((Test-Path -LiteralPath $legacyStore) -and -not (Test-Path -LiteralPath $script:PatchStore)) {
    $dir = Split-Path -Parent $script:PatchStore
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Move-Item -LiteralPath $legacyStore -Destination $script:PatchStore
    Write-Host "moved the patch record to $script:PatchStore" -ForegroundColor DarkGray
}

function Get-ModPatch {
    <#  Registered patches, newest first. -Name filters.  #>
    [CmdletBinding()]
    param([string]$Name)
    if (-not (Test-Path -LiteralPath $script:PatchStore)) { return @() }
    try   { $all = @(Get-Content -LiteralPath $script:PatchStore -Raw | ConvertFrom-Json) }
    catch { Write-Warning "patch store unreadable: $($_.Exception.Message)"; return @() }
    if ($Name) { $all = $all | Where-Object { $_.Name -eq $Name } }
    return @($all)
}

function Save-ModPatchStore {
    param($Entries)
    $dir = Split-Path -Parent $script:PatchStore
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    @($Entries) | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:PatchStore -Encoding UTF8
}

# ------------------------------------------------------------ affected paths --
# WHY A PATH INDEX EXISTS AT ALL.
#
# The registry answers "has upstream moved under me?" and nothing else. It could
# not answer "we are looking at broken arms - have we ever touched arms?", and on
# 2026-09-10 that cost a whole session: the override responsible was listed on
# screen in the first ten minutes and nothing connected it to the symptom.
#
# So every entry now records the resource paths it affects, and Test-ModPatches
# -Affects searches them. A symptom maps to interventions in one command.

# The game-layer roots. A path is recorded relative to whichever of these it sits
# under, so a staging path and a deployed path index identically.
$script:CwLayerRoots = @(
    'archive\pc\mod', 'archive\pc\patch', 'mods',
    'r6\scripts', 'r6\tweaks', 'r6\input', 'r6\config',
    'red4ext\plugins', 'bin\x64\plugins', 'bin\x64'
)

function ConvertTo-GameRelativePath {
    <#  '<staging>\Foo-123\r6\tweaks\x\y.yaml' -> 'r6\tweaks\x\y.yaml'.

        Falls back to the leaf when no layer root is recognised, so indexing
        never loses a file. -Strict returns $null instead, which is what any
        caller deriving a DIRECTORY from the result must use: the leaf fallback
        makes the computed mod folder wrong by an arbitrary number of levels,
        and one such miss pointed a scan at the whole staging root as if it were
        a single mod. 821 false positives, first run.  #>
    param([string] $Path, [switch] $Strict)
    if (-not $Path) { return $null }
    $norm = $Path -replace '/', '\'
    foreach ($root in $script:CwLayerRoots) {
        $i = $norm.IndexOf('\' + $root + '\', [StringComparison]::OrdinalIgnoreCase)
        if ($i -ge 0) { return $norm.Substring($i + 1) }
    }
    if ($Strict) { return $null }
    return (Split-Path -Leaf $norm)
}

function Get-XlPatchTarget {
    <#  The targets an ArchiveXL .xl patches into.

        This is the shape that hid the arms fault. A one-line .xl can redirect
        fifty-five meshes, and none of those paths appears anywhere in the
        registry unless something reads the file. Cheap, so it is done at
        registration rather than asked for.  #>
    param([string] $Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return @() }
    if ([IO.Path]::GetExtension($Path) -notin '.xl', '.yaml', '.yml') { return @() }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in (Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        # list items under a `patch:` map, and the map keys themselves
        if ($line -match '^\s+-\s+(\S.*\.(?:mesh|ent|app|xbm|streamingsector|community))\s*$') {
            $out.Add($Matches[1].Trim()) | Out-Null
        } elseif ($line -match '^\s+(\S.*\.(?:mesh|ent|app|xbm))\s*:\s*$') {
            $out.Add($Matches[1].Trim()) | Out-Null
        }
    }
    return @($out | Sort-Object -Unique)
}

function Resolve-ModPatchAffects {
    <#  What a registration touches: its own two files, plus anything an .xl
        redirects. Explicit -Affects is added on top, never replaced by this.  #>
    param([string] $UpstreamPath, [string] $OverridePath, [string[]] $Extra)
    $a = New-Object System.Collections.Generic.List[string]
    foreach ($p in @($UpstreamPath, $OverridePath)) {
        $rel = ConvertTo-GameRelativePath $p
        if ($rel) { $a.Add($rel) | Out-Null }
    }
    foreach ($p in @($OverridePath, $UpstreamPath)) {
        foreach ($t in (Get-XlPatchTarget $p)) { $a.Add($t) | Out-Null }
    }
    foreach ($e in @($Extra)) { if ($e) { $a.Add($e) | Out-Null } }
    return @($a | Sort-Object -Unique)
}

function Register-ModPatch {
    <#
    .SYNOPSIS
        Record that you have patched or overridden a file, and what it looked like.
    .DESCRIPTION
        Register at the moment you make the change, not later - the whole value is
        in the hash of the version you actually worked against.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Name,
        # The AUTHOR'S file - the thing that changes when they release an update.
        [Parameter(Mandatory)][string] $UpstreamPath,
        # Your override file, if this is an override rather than an in-place edit.
        [string] $OverridePath,
        [string] $Note,

        # Extra resource paths this touches, beyond the ones derived from the
        # two files. Only needed when the connection is not visible in either -
        # a redscript override of a method that changes some unrelated system,
        # say. Derived paths are always recorded regardless.
        [string[]] $Affects
    )

    if (-not (Test-Path -LiteralPath $UpstreamPath)) { throw "no upstream file at: $UpstreamPath" }

    # Keep a COPY of their file as it was, not just its hash.
    #
    # When the sweep later says CHANGED, the question is never "did it change" -
    # it is "does my change still apply, and did they fix it themselves?". That
    # needs their-old against their-new, which needs their-old to still exist.
    # A hash tells you something moved; the snapshot tells you what.
    #
    # This exists to make the JUDGEMENT fast, not to enable an automatic merge.
    # See Show-ModPatchDrift, and the warning above it.
    $snapDir = Join-Path (Split-Path -Parent $script:PatchStore) 'upstream'
    if (-not (Test-Path -LiteralPath $snapDir)) { New-Item -ItemType Directory -Path $snapDir -Force | Out-Null }
    $safe = ($Name -replace '[^A-Za-z0-9._-]', '_')
    $snap = Join-Path $snapDir "$safe.upstream"
    $srcItem = Get-Item -LiteralPath $UpstreamPath
    if ($srcItem.Length -le 5MB) {
        Copy-Item -LiteralPath $UpstreamPath -Destination $snap -Force
    } else {
        $snap = $null   # too big to be a text patch target; hash-only is honest
    }

    $entry = [pscustomobject]@{
        Name         = $Name
        Kind         = if ($OverridePath) { 'override' } else { 'in-place' }
        UpstreamPath = (Get-Item -LiteralPath $UpstreamPath).FullName
        UpstreamSha  = (Get-FileHash -LiteralPath $UpstreamPath -Algorithm SHA256).Hash
        UpstreamSize = (Get-Item -LiteralPath $UpstreamPath).Length
        OverridePath = if ($OverridePath) { $OverridePath } else { $null }
        Snapshot     = $snap
        RecordedUtc  = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
        Note         = $Note
        Affects      = Resolve-ModPatchAffects -UpstreamPath $UpstreamPath -OverridePath $OverridePath -Extra $Affects
    }

    $all = @(Get-ModPatch | Where-Object { $_.Name -ne $Name })   # re-registering replaces
    Save-ModPatchStore (@($all) + $entry)
    Write-Host "registered '$Name' ($($entry.Kind)) against $($entry.UpstreamSha.Substring(0,12)), $(@($entry.Affects).Count) affected path(s)" -ForegroundColor Green
    return $entry
}

function Unregister-ModPatch {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Name)
    $all = @(Get-ModPatch)
    $keep = @($all | Where-Object { $_.Name -ne $Name })
    if ($keep.Count -eq $all.Count) { Write-Warning "nothing registered as '$Name'"; return }
    Save-ModPatchStore $keep
    Write-Host "unregistered '$Name'" -ForegroundColor Green
}

function Show-ModPatchDrift {
    <#
    .SYNOPSIS
        Show what the AUTHOR changed since you patched their file.
    .DESCRIPTION
        Run this when the sweep says CHANGED. It diffs their file as it was when
        you patched it against their file now - so you can see what they did, and
        judge whether your change still applies, still belongs somewhere else, or
        is no longer needed because they fixed it themselves.

        ** NEVER AUTO-APPLY THE OLD PATCH TO THE NEW FILE. **

        This is deliberate and it is not laziness. A patch is a semantic change
        to code that has since moved. Re-applying it mechanically either fails -
        which is fine - or SUCCEEDS IN THE WRONG PLACE, which is silent and
        worse. Fuzzy or context-matched patching exists precisely to land a hunk
        somewhere plausible, and "plausible" is not "correct" in someone else's
        refactored file.

        Three questions, in order, every time:

          1. **Did they fix it themselves?** Then retire the patch:
             Unregister-ModPatch, and uninstall the override. This is the happy
             outcome and it is easy to miss while concentrating on re-applying.
          2. **Does the thing you changed still exist**, under that name, doing
             that job? A rename or a restructure can make an old patch
             meaningless while still applying cleanly.
          3. **Re-derive from their new file** - read it, make the change again,
             rebuild the override, then Register-ModPatch again to clear the flag.

        No -AutoFix switch will ever be added here, and one should not be.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Name)

    $p = Get-ModPatch -Name $Name | Select-Object -First 1
    if (-not $p) { throw "nothing registered as '$Name'" }
    if (-not $p.Snapshot -or -not (Test-Path -LiteralPath $p.Snapshot)) {
        throw "no snapshot of their original file for '$Name' - registered before snapshots, or the file was too large. Re-derive by reading their file directly."
    }
    if (-not (Test-Path -LiteralPath $p.UpstreamPath)) { throw "their file is gone: $($p.UpstreamPath)" }

    $backup = Join-Path $PSScriptRoot 'ModFileBackup.ps1'
    if (-not (Test-Path -LiteralPath $backup)) { throw "ModFileBackup.ps1 not found beside this script" }
    . $backup

    Write-Host ''
    Write-Host "what the AUTHOR changed since you patched '$Name':" -ForegroundColor Cyan
    Write-Host "  yours was for: $($p.Note)" -ForegroundColor DarkGray
    Show-ModFileDiff -Path $p.Snapshot -NewFile $p.UpstreamPath | Out-Null
    Write-Host 'Re-derive from their new file. Do not replay the old edit blindly.' -ForegroundColor Yellow
}

function Update-ModPatchAffects {
    <#
    .SYNOPSIS
        Fill in the affected-path index for entries registered before it existed.
    .DESCRIPTION
        Re-derives Affects from each entry's own files. It does NOT re-hash
        upstream and does not touch UpstreamSha, so an entry mid-CHANGED stays
        CHANGED - backfilling an index must never quietly bless a drift.

        Safe to re-run; -Force redoes entries that already have an index.
    #>
    [CmdletBinding()]
    param([switch] $Force)

    $all = @(Get-ModPatch)
    if (-not $all.Count) { Write-Host 'no patches registered' -ForegroundColor DarkGray; return }

    $done = 0
    foreach ($p in $all) {
        # @($null).Count is 1, not 0 - so a bare .Count here skips every entry
        # that has no index, which is precisely the set this exists to fill.
        # Measured: 'backfilled 0' on a registry where all 8 needed it.
        $have = @($p.Affects | Where-Object { $_ })
        if (-not $Force -and $have.Count) { continue }
        $a = Resolve-ModPatchAffects -UpstreamPath $p.UpstreamPath -OverridePath $p.OverridePath
        $p | Add-Member -NotePropertyName Affects -NotePropertyValue $a -Force
        $done++
        Write-Host ("  {0,-58} {1} path(s)" -f $p.Name, @($a).Count) -ForegroundColor DarkGray
    }
    if ($done) { Save-ModPatchStore $all }
    Write-Host "backfilled $done entr(ies)" -ForegroundColor Green
}

# ----------------------------------------------------------- reconciliation --
# THE REGISTRY ONLY KNOWS WHAT IT WAS TOLD, AND THAT IS THE HOLE.
#
# Registering is a step a person has to remember, so the failure mode is an
# override sitting on disk that nothing is watching. On 2026-09-10 exactly that
# happened: Cyberwise_UVHqArms_YamlFix-1.0 was built the same day as four
# siblings that were all registered, was itself missed, and ten days later had
# broken V's arms with nothing able to connect the two.
#
# So: find overrides by looking at the disk, and say which ones the registry has
# never heard of. No name pattern is hardcoded - "an override" is defined
# structurally, as a small mod every one of whose files is also shipped by some
# other mod. That definition is manager-neutral and catches a hand-built fix,
# a repack, and an accidental duplicate alike.
#
# WHAT IT DELIBERATELY WILL NOT DO. When two small mods ship exactly the same
# files and nothing else, which one is the override is not decidable from the
# filesystem - so BOTH are reported rather than guessing. In practice the author's
# mod ships more than the one file you overrode, so only yours comes back; the
# symmetric case is real but rare, and a pair in the report is a question worth
# answering, not a false positive to suppress.

function Find-UnregisteredOverride {
    <#
    .SYNOPSIS
        Mods on disk that look like overrides and are not in the registry.
    .PARAMETER SearchPath
        Staging roots to scan. Defaults to the roots implied by what is already
        registered, so a correctly-registered install needs no configuration and
        nothing about any one manager is baked in.
    .PARAMETER MaxFiles
        A mod shipping more than this is treated as a real mod, not an override.
    #>
    [CmdletBinding()]
    param([string[]] $SearchPath, [int] $MaxFiles = 25, [string[]] $Ignore)

    $patches = @(Get-ModPatch)

    if (-not $SearchPath) {
        # The staging root is the common ancestor of the override paths already
        # registered. Derived, not assumed.
        $roots = New-Object System.Collections.Generic.List[string]
        foreach ($p in $patches) {
            foreach ($cand in @($p.OverridePath, $p.UpstreamPath)) {
                if (-not $cand) { continue }
                $rel = ConvertTo-GameRelativePath $cand -Strict
                if (-not $rel -or $cand.Length -le $rel.Length) { continue }
                $modDir = $cand.Substring(0, $cand.Length - $rel.Length - 1)
                $parent = Split-Path -Parent $modDir
                if ($parent -and (Test-Path -LiteralPath $parent)) { $roots.Add($parent) | Out-Null }
            }
        }
        # An ancestor of another candidate is the manager's own root, not a
        # staging root; keeping it makes every mod look like it collides with
        # the one giant folder containing them all.
        $uniq = @($roots | Sort-Object -Unique)
        $SearchPath = @($uniq | Where-Object {
            $me = $_
            -not (@($uniq | Where-Object { $_ -ne $me -and $_.StartsWith($me + '\', [StringComparison]::OrdinalIgnoreCase) }).Count)
        })
    }
    if (-not $SearchPath) {
        Write-Host 'no staging root known - register one patch first, or pass -SearchPath' -ForegroundColor Yellow
        return @()
    }

    # relative path -> the mod folders shipping it
    $owners = @{}
    $modFiles = @{}
    foreach ($root in $SearchPath) {
        foreach ($mod in (Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
            $files = @(Get-ChildItem -LiteralPath $mod.FullName -Recurse -File -ErrorAction SilentlyContinue)
            if (-not $files.Count) { continue }
            $rels = @($files | ForEach-Object { ConvertTo-GameRelativePath $_.FullName })
            $modFiles[$mod.FullName] = $rels
            foreach ($r in $rels) {
                $k = $r.ToLowerInvariant()
                if (-not $owners.ContainsKey($k)) { $owners[$k] = New-Object System.Collections.Generic.List[string] }
                $owners[$k].Add($mod.FullName) | Out-Null
            }
        }
    }

    # Everything the registry already accounts for, however it names it.
    $known = ($patches | ForEach-Object { "$($_.Name)|$($_.Note)|$($_.OverridePath)|$($_.UpstreamPath)" }) -join [Environment]::NewLine

    $out = foreach ($modPath in $modFiles.Keys) {
        $rels = $modFiles[$modPath]
        if ($rels.Count -gt $MaxFiles) { continue }
        # A folder that contains other scanned mod folders is a container, not a mod.
        if (@($modFiles.Keys | Where-Object { $_ -ne $modPath -and $_.StartsWith($modPath + '\', [StringComparison]::OrdinalIgnoreCase) }).Count) { continue }
        $leaf = Split-Path -Leaf $modPath
        if ($Ignore -and ($Ignore | Where-Object { $leaf -like $_ })) { continue }
        # every file it ships is also shipped elsewhere => it overrides, it does not add
        $contested = @($rels | Where-Object { $owners[$_.ToLowerInvariant()].Count -gt 1 })
        if ($contested.Count -ne $rels.Count) { continue }
        if ($known.Contains($leaf, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $rivals = @()
        foreach ($r in $rels) { $rivals += @($owners[$r.ToLowerInvariant()] | Where-Object { $_ -ne $modPath } | ForEach-Object { Split-Path -Leaf $_ }) }
        [pscustomobject]@{
            Mod       = $leaf
            Path      = $modPath
            Files     = $rels.Count
            Overrides = @($rivals | Sort-Object -Unique)
            Affects   = $rels
        }
    }
    return @($out | Sort-Object Mod)
}

function Test-ModPatches {
    <#
    .SYNOPSIS
        The sweep. Reports every patch whose upstream file has changed.
    .DESCRIPTION
        Run after ANY mod update. Exit-style result: returns the findings, and
        writes a non-zero $global:LASTPATCHSWEEP when something needs attention.

        Four things can be wrong, and they need different actions:

          CHANGED  the author shipped a new version of the file you patched.
                   An in-place patch is probably already gone; an override is
                   probably now stale and hiding their fix. RE-DERIVE.
          GONE     the upstream file is missing - the mod was uninstalled,
                   renamed, or updated into a different layout.
          NOOVER   an override was registered but its file is not there, so
                   nothing is overriding anything and the bug is back.
          OK       byte-identical to when you patched it.
    #>
    [CmdletBinding()]
    param(
        [switch] $Quiet,

        # Report only entries touching a resource path matching this. The
        # symptom-to-intervention lookup: -Affects arms, -Affects vehicle.
        [string] $Affects,

        # Also scan disk for override-shaped mods the registry has never seen.
        [switch] $Reconcile,
        [string[]] $SearchPath,
        [string[]] $Ignore
    )

    $patches = @(Get-ModPatch)

    if ($Affects) {
        $patches = @($patches | Where-Object {
            $hay = @($_.Affects) + $_.Name + $_.Note
            @($hay | Where-Object { $_ -and $_ -match [regex]::Escape($Affects) }).Count -gt 0
        })
        if (-not $Quiet) {
            Write-Host "entries affecting '$Affects': $($patches.Count)" -ForegroundColor Cyan
            foreach ($p in $patches) {
                Write-Host "  $($p.Name)" -ForegroundColor Green
                $hits = @($p.Affects | Where-Object { $_ -match [regex]::Escape($Affects) })
                foreach ($a in @($hits | Select-Object -First 6)) {
                    Write-Host "     $a" -ForegroundColor DarkGray
                }
                if ($hits.Count -gt 6) { Write-Host "     ... and $($hits.Count - 6) more" -ForegroundColor DarkGray }
            }
            Write-Host ''
        }
    }
    if (-not $patches.Count) {
        if (-not $Quiet) { Write-Host 'no patches registered' -ForegroundColor DarkGray }
        $global:LASTPATCHSWEEP = 0
        return @()
    }

    $findings = foreach ($p in $patches) {
        $state = 'OK'; $detail = ''

        if (-not (Test-Path -LiteralPath $p.UpstreamPath)) {
            $state = 'GONE'; $detail = 'upstream file is missing - mod uninstalled, renamed, or restructured'
        } else {
            $now = (Get-FileHash -LiteralPath $p.UpstreamPath -Algorithm SHA256).Hash
            if ($now -ne $p.UpstreamSha) {
                $state  = 'CHANGED'
                $detail = if ($p.Kind -eq 'override') {
                    'the author changed this file. Your override still wins, so their change is NOT in effect - re-derive it.'
                } else {
                    'the author changed this file. Your in-place edit is probably gone - re-apply or re-derive.'
                }
            }
        }

        if ($state -eq 'OK' -and $p.Kind -eq 'override' -and $p.OverridePath -and
            -not (Test-Path -LiteralPath $p.OverridePath)) {
            $state = 'NOOVER'; $detail = 'the override file is missing, so nothing is overriding anything'
        }

        [pscustomobject]@{ Name = $p.Name; Kind = $p.Kind; State = $state; Detail = $detail; Path = $p.UpstreamPath; Note = $p.Note }
    }

    if (-not $Quiet) {
        foreach ($f in $findings) {
            $colour = switch ($f.State) { 'OK' { 'DarkGreen' } 'CHANGED' { 'Yellow' } default { 'Red' } }
            Write-Host ("{0,-8} {1}" -f $f.State, $f.Name) -ForegroundColor $colour
            if ($f.Detail) { Write-Host "         $($f.Detail)" -ForegroundColor DarkGray }
            if ($f.State -ne 'OK' -and $f.Note) { Write-Host "         was: $($f.Note)" -ForegroundColor DarkGray }
        }
        $bad = @($findings | Where-Object State -ne 'OK').Count
        Write-Host ''
        if ($bad) { Write-Host "$bad patch(es) need attention" -ForegroundColor Yellow }
        else      { Write-Host "all $($findings.Count) patch(es) still match the version they were made against" -ForegroundColor Green }
    }

    if ($Reconcile) {
        $orphans = @(Find-UnregisteredOverride -SearchPath $SearchPath -Ignore $Ignore)
        if (-not $Quiet) {
            Write-Host ''
            if ($orphans.Count) {
                Write-Host "$($orphans.Count) override-shaped mod(s) on disk that the registry has never seen:" -ForegroundColor Yellow
                foreach ($o in $orphans) {
                    Write-Host "  $($o.Mod)" -ForegroundColor Yellow
                    Write-Host "     $($o.Files) file(s), all of them also shipped by: $($o.Overrides -join ', ')" -ForegroundColor DarkGray
                }
                Write-Host ''
                Write-Host 'Each is either an override nobody is watching, or an intentional replacement.' -ForegroundColor DarkGray
                Write-Host 'Register the first kind; -Ignore the second. An unwatched override is how a' -ForegroundColor DarkGray
                Write-Host "fix goes stale, and how one broke V's arms for ten days." -ForegroundColor DarkGray
            } else {
                Write-Host 'reconcile: every override-shaped mod on disk is accounted for' -ForegroundColor Green
            }
        }
        $global:LASTPATCHSWEEP = @($findings | Where-Object State -ne 'OK').Count + $orphans.Count
        return @{ Findings = $findings; Unregistered = $orphans }
    }

    $global:LASTPATCHSWEEP = @($findings | Where-Object State -ne 'OK').Count
    return $findings
}
