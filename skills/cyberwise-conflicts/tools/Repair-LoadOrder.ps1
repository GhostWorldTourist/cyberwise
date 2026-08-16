<#
.SYNOPSIS
    Check (and optionally repair) the Cyberpunk 2077 archive load order.

.DESCRIPTION
    Three independent checks against archive\pc\mod\modlist.txt:

      1. INVENTORY  - entries listed with no file on disk (stale), and archives
                      on disk with no entry (unlisted). Unlisted archives cannot
                      be positioned at all, so they are a silent failure.

      2. PRECEDENCE - the standing "X must load before Y" rules in $Rules below.
                      EARLIER IN modlist.txt WINS (verified 2026-08-09 against a
                      conflict checker on three independent collisions). This is
                      the opposite of the usual "zzz_ prefix wins" intuition.

      3. COLLISIONS - parses every .archive index and reports which archives lose
                      files to which. Flags INERT archives: every file they carry
                      is owned by something earlier, so the mod is installed,
                      enabled, and doing absolutely nothing. This is the trap that
                      silently ate the Arasaka monowire retex twice, because
                      whatever rewrites modlist.txt APPENDS new archives at the
                      end -- and the end is the bottom of the priority stack.

    Run this after ANY Vortex change: install, uninstall, or variant swap.

.PARAMETER Fix
    Apply repairs: reorder to satisfy the rules, and place unlisted archives next
    to their closest-named sibling. Backs up modlist.txt first. Without this the
    script only reports.

.PARAMETER PruneStale
    Also delete entries whose archive is missing. Off by default on purpose: a
    stale line holds the slot for a mod you have merely disabled, so it keeps its
    position if you re-enable it.

.PARAMETER SkipScan
    Skip the collision scan (checks 1 and 2 only). The scan reads 680 archive
    indices in about 7 seconds, so you rarely want this.

.EXAMPLE
    .\Repair-LoadOrder.ps1
    .\Repair-LoadOrder.ps1 -Fix
#>
[CmdletBinding()]
param(
    [string] $ModDir,
    [string] $RulesFile,
    [switch] $Fix,
    [switch] $PruneStale,
    [switch] $SkipScan
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# WHERE THE INSTALL IS. Steam, GOG and Epic all install elsewhere and the drive
# is the user's choice, so never assume a path - read the storefront's own
# record and confirm the exe is actually there.
# ---------------------------------------------------------------------------
if (-not $ModDir) {
    $seen = New-Object System.Collections.Generic.List[string]
    try {
        $steam = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath
        if ($steam) {
            $seen.Add((Join-Path $steam 'steamapps\common\Cyberpunk 2077'))
            $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
            if (Test-Path -LiteralPath $vdf) {
                foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
                    $seen.Add((Join-Path ($m.Groups[1].Value -replace '\\\\','\') 'steamapps\common\Cyberpunk 2077'))
                }
            }
        }
    } catch {}
    foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games\1423049311','HKLM:\SOFTWARE\GOG.com\Games\1423049311') {
        try { $g = (Get-ItemProperty $k -ErrorAction SilentlyContinue).path; if ($g) { $seen.Add($g) } } catch {}
    }
    foreach ($p in $seen) {
        if ($p -and (Test-Path -LiteralPath (Join-Path $p 'bin\x64\Cyberpunk2077.exe'))) {
            $ModDir = Join-Path $p 'archive\pc\mod'; break
        }
    }
}
if (-not $ModDir -or -not (Test-Path -LiteralPath $ModDir)) {
    throw "Could not find archive\pc\mod. Pass -ModDir 'X:\...\Cyberpunk 2077\archive\pc\mod'."
}

# ---------------------------------------------------------------------------
# YOUR standing decisions live in a separate file, not in this script.
#
#   <ModDir>\..\..\..\_loadorder\loadorder-rules.psd1     (or pass -RulesFile)
#
# It is deliberately EMPTY here. Precedence rules are one person's settled
# conflicts on one load order; shipping somebody else's would silently reorder
# an install that never had those mods. Write the file as:
#
#   @{
#       Rules = @(
#           @{ Before = 'specific_retex.archive'
#              After  = 'catch_all_aio.archive'
#              Why    = 'AIO should lose to anything specific' }
#       )
#       BenignInert      = @{ 'some.archive' = 'why this being inert is fine' }
#       RuntimeGenerated = @{ 'other.archive' = 'why this appears and vanishes' }
#   }
# ---------------------------------------------------------------------------
$Rules = @()

# Facts about PUBLIC mods, true on any install that has them - as distinct from
# one user's preferences, which belong in the rules file above.
$RuntimeGenerated = @{
    'dynamic_moon_phases.archive' =
        'written at runtime by bin\x64\plugins\dynamic_moon_phases.asi from its .luna phase textures. It ships NO archive in staging, so it appears and vanishes with game sessions - never prune its entry as stale. It still needs a permanent slot: unlisted archives sort last and would lose the moon texture.'
}

$BenignInert = @{
    'SkillfulAttributes.archive' =
        'Skillful and Skillful Attributes are companion mods, not rivals - Skillful guards its settings with @if(!ModuleExists("SBAConfig")). Both archives carry the same single localization string, so either copy works.'
}

# Merge in the user's own file, if there is one.
if (-not $RulesFile) { $RulesFile = Join-Path (Split-Path (Split-Path (Split-Path $ModDir))) '_loadorder\loadorder-rules.psd1' }
if (Test-Path -LiteralPath $RulesFile) {
    try {
        $userRules = Import-PowerShellDataFile -LiteralPath $RulesFile
        if ($userRules.Rules)            { $Rules = @($userRules.Rules) }
        if ($userRules.BenignInert)      { foreach ($k in $userRules.BenignInert.Keys)      { $BenignInert[$k]      = $userRules.BenignInert[$k] } }
        if ($userRules.RuntimeGenerated) { foreach ($k in $userRules.RuntimeGenerated.Keys) { $RuntimeGenerated[$k] = $userRules.RuntimeGenerated[$k] } }
        Write-Host "rules file: $RulesFile ($($Rules.Count) precedence rule(s))" -ForegroundColor DarkGray
    } catch {
        Write-Warning "could not read $RulesFile : $($_.Exception.Message)"
    }
} else {
    Write-Host "no rules file at $RulesFile - precedence check will pass trivially" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# .archive index reader. Header: magic 'RDAR' u32, version u32,
# indexPosition u64, indexSize u32. At indexPosition: fileTableOffset u32,
# fileTableSize u32, crc u64, fileEntryCount u32, fileSegmentCount u32,
# resourceDependencyCount u32 (28 bytes), then fileEntryCount * 56-byte entries
# whose first 8 bytes are the FNV1a-64 name hash. File data is Oodle-compressed;
# only the index is readable without a decompressor.
# ---------------------------------------------------------------------------
function Get-ArchiveHashes {
    param([string] $Path)
    $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try {
        $br = New-Object IO.BinaryReader($fs)
        if ([Text.Encoding]::ASCII.GetString($br.ReadBytes(4)) -ne 'RDAR') { return $null }
        $null = $br.ReadUInt32()
        $indexPosition = $br.ReadUInt64()
        $null = $br.ReadUInt32()
        $fs.Position = [int64] $indexPosition
        $null = $br.ReadUInt32(); $null = $br.ReadUInt32(); $null = $br.ReadUInt64()
        $count = $br.ReadUInt32()
        $null = $br.ReadUInt32(); $null = $br.ReadUInt32()
        $out = New-Object 'System.Collections.Generic.List[UInt64]'
        for ($i = 0; $i -lt $count; $i++) {
            $e = $br.ReadBytes(56)
            if ($e.Length -lt 56) { break }
            $out.Add([BitConverter]::ToUInt64($e, 0))
        }
        return $out
    } finally { $fs.Dispose() }
}

function Write-Section { param([string] $Text) Write-Host "`n=== $Text ===" -ForegroundColor Cyan }
function Write-Ok      { param([string] $Text) Write-Host "  OK   $Text" -ForegroundColor DarkGray }
function Write-Warn    { param([string] $Text) Write-Host "  WARN $Text" -ForegroundColor Yellow }
function Write-Bad     { param([string] $Text) Write-Host "  BAD  $Text" -ForegroundColor Red }

$listPath = Join-Path $ModDir 'modlist.txt'
if (-not (Test-Path -LiteralPath $listPath)) { throw "modlist.txt not found at $listPath" }

# Backups go with the other install records, NOT beside this script.
#
# $PSScriptRoot here is inside the skill - which is a link into a repo, or into
# an installed copy. Writing backups there means they land in somebody's git
# clone, or disappear when the skill is reinstalled or unlinked. A backup that
# lives inside the thing that gets replaced is not a backup.
#
# modlist.txt is a deliberate custom order that nothing else can reconstruct, so
# this one matters more than most.
$backupDir = Join-Path $env:USERPROFILE 'Saved Games\CD Projekt Red\Cyberpunk 2077\Cyberwise\modlist-backups'
$lines     = [System.Collections.Generic.List[string]](Get-Content -LiteralPath $listPath)
$onDisk    = (Get-ChildItem -LiteralPath $ModDir -Filter *.archive).Name
$dirty     = $false
$problems  = 0

Write-Host "modlist.txt : $($lines.Count) entries"
Write-Host "on disk     : $($onDisk.Count) .archive files"

# --- 1. inventory -----------------------------------------------------------
Write-Section 'INVENTORY'

foreach ($rg in $RuntimeGenerated.Keys) {
    if (($lines -contains $rg) -or ($onDisk -contains $rg)) {
        Write-Host "  INFO runtime-generated: $rg" -ForegroundColor DarkGray
        Write-Host "         $($RuntimeGenerated[$rg])" -ForegroundColor DarkGray
    }
}
# Runtime-generated archives keep their slot even when the file is absent, so they
# are exempt from the stale check -- but they still get listed and positioned.
$stale = @($lines | Where-Object { $_.Trim() -and -not $RuntimeGenerated.ContainsKey($_) -and -not (Test-Path -LiteralPath (Join-Path $ModDir $_)) })
if ($stale.Count -eq 0) { Write-Ok 'no stale entries' }
else {
    foreach ($s in $stale) { Write-Warn "listed but missing: $s" }
    if ($PruneStale) {
        foreach ($s in $stale) { $null = $lines.Remove($s) }
        $dirty = $true
        Write-Host "       -> pruned $($stale.Count) stale entr$(if($stale.Count -eq 1){'y'}else{'ies'})" -ForegroundColor Green
    } else {
        Write-Host '       (kept - a stale line holds the slot for a disabled mod. -PruneStale to remove)' -ForegroundColor DarkGray
    }
}

$unlisted = @($onDisk | Where-Object { $lines -notcontains $_ })
if ($unlisted.Count -eq 0) { Write-Ok 'no unlisted archives' }
else {
    $problems += $unlisted.Count
    foreach ($u in $unlisted) { Write-Bad "on disk but unlisted (cannot be positioned): $u" }
    if ($Fix) {
        foreach ($u in $unlisted) {
            # place next to the closest-named listed sibling, else append
            $best = $null; $bestLen = 0
            foreach ($cand in $lines) {
                if (-not $cand.Trim()) { continue }
                $n = 0
                while ($n -lt $cand.Length -and $n -lt $u.Length -and $cand[$n] -eq $u[$n]) { $n++ }
                if ($n -gt $bestLen) { $bestLen = $n; $best = $cand }
            }
            if ($best -and $bestLen -ge 8) {
                $lines.Insert($lines.IndexOf($best) + 1, $u)
                Write-Host "       -> placed after sibling '$best' (matched $bestLen chars)" -ForegroundColor Green
            } else {
                $lines.Add($u)
                Write-Warn "       -> no sibling found; APPENDED at the end, where it loses every conflict. Position it yourself."
            }
        }
        $dirty = $true
    }
}

# --- 2. precedence ----------------------------------------------------------
Write-Section 'PRECEDENCE RULES'

function Get-Index { param($List) $h = @{}; for ($i = 0; $i -lt $List.Count; $i++) { $h[$List[$i]] = $i }; return $h }

$violations = @()
$idx = Get-Index $lines
foreach ($r in $Rules) {
    $hasA = $idx.ContainsKey($r.Before); $hasB = $idx.ContainsKey($r.After)
    if (-not $hasA -or -not $hasB) { Write-Ok "skipped (archive absent): $($r.Before) -> $($r.After)"; continue }
    if ($idx[$r.Before] -lt $idx[$r.After]) {
        Write-Ok ("{0} ({1}) before {2} ({3})" -f $r.Before, ($idx[$r.Before] + 1), $r.After, ($idx[$r.After] + 1))
    } else {
        $violations += $r
        Write-Bad ("{0} ({1}) must precede {2} ({3})" -f $r.Before, ($idx[$r.Before] + 1), $r.After, ($idx[$r.After] + 1))
        Write-Host "       why: $($r.Why)" -ForegroundColor DarkGray
    }
}

if ($violations.Count -gt 0) {
    $problems += $violations.Count
    if ($Fix) {
        for ($pass = 0; $pass -lt 50; $pass++) {
            $idx = Get-Index $lines
            $bad = @($Rules | Where-Object {
                $idx.ContainsKey($_.Before) -and $idx.ContainsKey($_.After) -and $idx[$_.Before] -gt $idx[$_.After] })
            if ($bad.Count -eq 0) { break }
            $r = $bad[0]
            $null = $lines.Remove($r.Before)
            $lines.Insert($lines.IndexOf($r.After), $r.Before)
            $dirty = $true
        }
        $idx = Get-Index $lines
        $left = @($Rules | Where-Object {
            $idx.ContainsKey($_.Before) -and $idx.ContainsKey($_.After) -and $idx[$_.Before] -gt $idx[$_.After] })
        if ($left.Count -eq 0) { Write-Host "       -> all rules satisfied" -ForegroundColor Green }
        else { Write-Bad "       -> could not satisfy $($left.Count) rule(s); they may contradict each other" }
    }
}

# --- write ------------------------------------------------------------------
if ($dirty) {
    if (-not (Test-Path -LiteralPath $backupDir)) { $null = New-Item -ItemType Directory -Path $backupDir }
    $bak = Join-Path $backupDir ("modlist.{0}.bak" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Copy-Item -LiteralPath $listPath -Destination $bak
    Set-Content -LiteralPath $listPath -Value $lines -Encoding utf8NoBOM
    Write-Host "`nmodlist.txt written. Backup: $bak" -ForegroundColor Green
    $dupes = @($lines | Group-Object | Where-Object Count -gt 1)
    if ($dupes.Count) { Write-Bad "duplicate entries introduced: $($dupes.Name -join ', ')" }
}
elseif ($Fix) { Write-Host "`nnothing to change." -ForegroundColor DarkGray }

# --- 3. collisions ----------------------------------------------------------
if (-not $SkipScan) {
    Write-Section 'COLLISION SCAN'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $lines = [System.Collections.Generic.List[string]](Get-Content -LiteralPath $listPath)
    $idx = Get-Index $lines
    # Sort-Object binds $_ inside the scriptblock; unlisted archives sort last.
    $rank = { if ($null -ne $_ -and $idx.ContainsKey($_)) { $idx[$_] } else { [int]::MaxValue } }

    $owner = @{}
    $total = @{}
    foreach ($f in (Get-ChildItem -LiteralPath $ModDir -Filter *.archive)) {
        $hs = Get-ArchiveHashes $f.FullName
        if ($null -eq $hs) { Write-Warn "unreadable (not RDAR): $($f.Name)"; continue }
        $total[$f.Name] = $hs.Count
        foreach ($h in $hs) {
            if (-not $owner.ContainsKey($h)) { $owner[$h] = New-Object 'System.Collections.Generic.List[string]' }
            $owner[$h].Add($f.Name)
        }
    }

    $lost = @{}
    foreach ($kv in $owner.GetEnumerator()) {
        if ($kv.Value.Count -lt 2) { continue }
        $ranked = $kv.Value | Sort-Object $rank
        foreach ($l in $ranked[1..($ranked.Count - 1)]) {
            if (-not $lost.ContainsKey($l)) { $lost[$l] = @{ Count = 0; To = @{} } }
            $lost[$l].Count++
            $lost[$l].To[$ranked[0]] = 1 + $lost[$l].To[$ranked[0]]
        }
    }

    Write-Host ("scanned {0} archives in {1:N1}s; {2} distinct resources" -f $total.Count, $sw.Elapsed.TotalSeconds, $owner.Count)

    $allInert = @($lost.Keys | Where-Object { $total[$_] -gt 0 -and $lost[$_].Count -ge $total[$_] } | Sort-Object $rank)
    $benign   = @($allInert | Where-Object { $BenignInert.ContainsKey($_) })
    $inert    = @($allInert | Where-Object { -not $BenignInert.ContainsKey($_) })

    foreach ($b in $benign) {
        Write-Host "  INFO inert but known harmless: $b" -ForegroundColor DarkGray
        Write-Host "         $($BenignInert[$b])" -ForegroundColor DarkGray
    }

    if ($inert.Count -eq 0) { Write-Ok 'no unexplained inert archives' }
    else {
        $problems += $inert.Count
        foreach ($i in $inert) {
            $pos = if ($idx.ContainsKey($i)) { $idx[$i] + 1 } else { 'UNLISTED' }
            Write-Bad "INERT: $i (line $pos) - all $($total[$i]) of its files are owned by:"
            foreach ($w in ($lost[$i].To.Keys | Sort-Object $rank)) {
                $wp = if ($idx.ContainsKey($w)) { $idx[$w] + 1 } else { 'UNLISTED' }
                Write-Host "         $($lost[$i].To[$w]) file(s) -> $w (line $wp)" -ForegroundColor DarkGray
            }
        }
    }

    $partial = @($lost.Keys | Where-Object { $total[$_] -gt 0 -and $lost[$_].Count -lt $total[$_] })
    Write-Host "`n  $($partial.Count) archive(s) lose some but not all of their files (normal for overlapping retextures)."
    Write-Host "  Re-run with -Verbose to list them."
    if ($VerbosePreference -ne 'SilentlyContinue') {
        foreach ($p in ($partial | Sort-Object $rank)) {
            $pos = if ($idx.ContainsKey($p)) { $idx[$p] + 1 } else { 'UNLISTED' }
            Write-Host ("    line {0,5}  {1,-58} {2}/{3} files lost" -f $pos, $p, $lost[$p].Count, $total[$p])
        }
    }
}

Write-Host ''
if ($problems -eq 0) { Write-Host 'Load order is clean.' -ForegroundColor Green; exit 0 }
if ($Fix)            { Write-Host "Finished with $problems issue(s) flagged - re-run to confirm." -ForegroundColor Yellow; exit 1 }
Write-Host "$problems issue(s) found. Re-run with -Fix to repair." -ForegroundColor Yellow
exit 1
