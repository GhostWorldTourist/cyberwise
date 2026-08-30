# Write-InstallLedger.ps1 -- append what the install looks like right now to a
# permanent, compressed ledger, so "what changed since it worked" has an answer
# that does not depend on anything still being on disk.
#
# WHY THIS EXISTS. The first version of the forensics tool reconstructed history
# from Vortex's downloads folder, on the theory that Vortex never deletes an
# archive. That was wrong, and wrong in the way that matters: the user deletes
# them deliberately, because they do not want a hoard of mods they will never
# install again. A forensic tool that assumes the evidence is still there is a
# tool that quietly returns less history the tidier you are.
#
# So record it instead of inferring it. One line per launch, appended forever.
#
# WHY IT STAYS SMALL. The first entry is a full baseline. Every entry after that
# is a DELTA against the previous state - added, removed, changed - and on a
# normal launch nothing changed, so the entry is a few dozen bytes. A snapshot of
# this install is ~1,600 entries and ~150 KB raw; the deltas between launches are
# almost always empty. Gzipped and appended, 100,000 launches is single-digit
# megabytes. Keeping it forever is the cheap option.
#
# WHAT IT RECORDS. Deployed archives, plugin DLLs, script folders and CET mod
# folders - name, size, mtime - plus the Vortex staging folder names. Not file
# contents: this answers "what was present and when did it change", which is the
# question, and hashing 700 archives at every launch is not free.
#
# WIRING IT UP. Call it from whatever already runs at launch - the crash watcher
# registered by Register-CrashWatch.ps1 is the natural host. It is safe to call
# often: an unchanged install appends nothing at all.

[CmdletBinding()]
param(
    [string] $GameRoot,
    [string] $StagingRoot,

    # Where the ledger lives. Outside the game folder on purpose: a verify,
    # a reinstall or a manager purge must not take the history with it.
    [string] $LedgerPath,

    # Print what would be appended and write nothing.
    [switch] $WhatIfOnly,

    # Append a full baseline even if nothing changed. Use after editing the
    # ledger by hand, or if you suspect it has drifted from reality.
    [switch] $Baseline,

    # Report the ledger's own size and span, then exit.
    [switch] $Stat
)

$ErrorActionPreference = 'Stop'

# --- upstream guard ---------------------------------------------------------
$cwGuard = Join-Path $PSScriptRoot '..\..\cyberwise\tools\UpstreamGuard.ps1'
if (Test-Path -LiteralPath $cwGuard) { try { . $cwGuard; Invoke-CwStartupGuard } catch { } }

# --- where -------------------------------------------------------------------

if (-not $LedgerPath) {
    $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [IO.Path]::GetTempPath() }
    $LedgerPath = Join-Path $base 'cyberwise\install-ledger.ndjson.gz'
}
$ledgerDir = Split-Path -Parent $LedgerPath
if (-not (Test-Path -LiteralPath $ledgerDir)) { New-Item -ItemType Directory -Force -Path $ledgerDir | Out-Null }

# --- read the whole ledger ---------------------------------------------------
# Gzip has no random access and the file is small, so read it all. At the sizes
# this reaches - megabytes after years - that costs milliseconds.

function Read-Ledger {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $fs = [IO.File]::OpenRead($Path)
    try {
        $gz = New-Object IO.Compression.GZipStream($fs, [IO.Compression.CompressionMode]::Decompress)
        try {
            $sr = New-Object IO.StreamReader($gz)
            try { $text = $sr.ReadToEnd() } finally { $sr.Dispose() }
        } finally { $gz.Dispose() }
    } finally { $fs.Dispose() }
    return @($text -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
}

function Append-Ledger {
    param([string] $Path, [string] $Line)
    # Rewrite rather than append to the gzip stream: concatenated gzip members
    # are legal but not every reader handles them, and at this size rewriting is
    # cheaper than the class of bug that causes.
    $existing = ''
    if (Test-Path -LiteralPath $Path) {
        $fs = [IO.File]::OpenRead($Path)
        try {
            $gz = New-Object IO.Compression.GZipStream($fs, [IO.Compression.CompressionMode]::Decompress)
            try { $sr = New-Object IO.StreamReader($gz); try { $existing = $sr.ReadToEnd() } finally { $sr.Dispose() } }
            finally { $gz.Dispose() }
        } finally { $fs.Dispose() }
    }
    $all = $existing + $Line + "`n"
    $tmp = "$Path.tmp"
    $out = [IO.File]::Create($tmp)
    try {
        $gz = New-Object IO.Compression.GZipStream($out, [IO.Compression.CompressionLevel]::Optimal)
        try { $sw = New-Object IO.StreamWriter($gz); try { $sw.Write($all) } finally { $sw.Dispose() } }
        finally { $gz.Dispose() }
    } finally { $out.Dispose() }
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

if ($Stat) {
    $entries = @(Read-Ledger -Path $LedgerPath)
    if (-not $entries.Count) { Write-Host "no ledger yet at $LedgerPath"; return }
    $size = (Get-Item $LedgerPath).Length
    $raw  = ($entries | ForEach-Object { ($_ | ConvertTo-Json -Compress -Depth 6).Length } | Measure-Object -Sum).Sum
    Write-Host "ledger    : $LedgerPath"
    Write-Host ("entries   : {0}  ({1} baseline, {2} delta)" -f $entries.Count,
        @($entries | Where-Object kind -eq 'baseline').Count, @($entries | Where-Object kind -eq 'delta').Count)
    Write-Host ("span      : {0}  ->  {1}" -f $entries[0].at, $entries[-1].at)
    Write-Host ("on disk   : {0:N1} KB compressed, {1:N1} KB raw  ({2:N0}x)" -f ($size/1KB), ($raw/1KB), ($raw/[Math]::Max($size,1)))
    $deltas = @($entries | Where-Object kind -eq 'delta')
    if ($deltas.Count) {
        $avg = ($deltas | ForEach-Object { ($_ | ConvertTo-Json -Compress -Depth 6).Length } | Measure-Object -Average).Average
        Write-Host ("projected : {0:N1} MB at 100,000 launches, at {1:N0} raw bytes per delta" -f ($avg * 100000 / 1MB / 3), $avg)
    } else {
        Write-Host  "projected : no deltas yet to measure. An unchanged launch appends NOTHING,"
        Write-Host  "            so the growth rate is set by how often you actually change mods."
    }
    return
}

# --- discovery ---------------------------------------------------------------

if (-not $StagingRoot -and $env:APPDATA) {
    $p = Join-Path $env:APPDATA 'Vortex\cyberpunk2077\mods'
    if (Test-Path -LiteralPath $p) { $StagingRoot = $p }
}
if (-not $GameRoot) {
    # Ask the machine, never guess a drive letter.
    $cands = [System.Collections.Generic.List[string]]::new()
    $steam = $null
    try   { $steam = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -Name InstallPath -ErrorAction Stop).InstallPath }
    catch { try { $steam = (Get-ItemProperty 'HKCU:\SOFTWARE\Valve\Steam' -Name SteamPath -ErrorAction Stop).SteamPath } catch { } }
    if ($steam) {
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $cands.Add((Join-Path ($m.Groups[1].Value -replace '\\\\', '\') 'steamapps\common\Cyberpunk 2077'))
            }
        }
        $cands.Add((Join-Path $steam 'steamapps\common\Cyberpunk 2077'))
    }
    try {
        foreach ($k in (Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games' -ErrorAction Stop)) {
            $v = (Get-ItemProperty $k.PSPath -Name path -ErrorAction SilentlyContinue).path
            if ($v) { $cands.Add($v) }
        }
    } catch { }
    foreach ($c in $cands) {
        if (Test-Path -LiteralPath (Join-Path $c 'bin\x64\Cyberpunk2077.exe')) { $GameRoot = $c; break }
    }
}
if (-not $GameRoot) { throw "Could not find the game. Pass -GameRoot." }

# --- take the snapshot -------------------------------------------------------
# A stable key per thing, mapped to a short state string. Keys are relative and
# forward-slashed so a ledger stays readable if the install ever moves.

$state = [ordered]@{}

function Add-Files {
    param([string] $Dir, [string] $Tag, [string[]] $Include, [switch] $Recurse)
    if (-not (Test-Path -LiteralPath $Dir)) { return }
    $gci = @{ LiteralPath = $Dir; File = $true; ErrorAction = 'SilentlyContinue' }
    if ($Recurse) { $gci.Recurse = $true }
    foreach ($f in Get-ChildItem @gci) {
        if ($Include -and ($Include -notcontains $f.Extension.ToLowerInvariant())) { continue }
        $key = "$Tag/" + $f.FullName.Substring($Dir.Length).TrimStart([char]0x5C, [char]0x2F).Replace('\', '/')
        $state[$key] = '{0}|{1:yyyyMMddHHmm}' -f $f.Length, $f.LastWriteTimeUtc
    }
}

Add-Files -Dir (Join-Path $GameRoot 'archive\pc\mod')  -Tag 'archive' -Include '.archive', '.xl'
Add-Files -Dir (Join-Path $GameRoot 'red4ext\plugins') -Tag 'red4ext' -Include '.dll' -Recurse

# Folders, not files, for the layers where the folder is the unit of meaning.
foreach ($pair in @(
    @{ dir = Join-Path $GameRoot 'r6\scripts'; tag = 'reds' },
    @{ dir = Join-Path $GameRoot 'r6\tweaks';  tag = 'tweak' },
    @{ dir = Join-Path $GameRoot 'bin\x64\plugins\cyber_engine_tweaks\mods'; tag = 'cet' })) {
    if (-not (Test-Path -LiteralPath $pair.dir)) { continue }
    foreach ($d in Get-ChildItem -LiteralPath $pair.dir -Directory -ErrorAction SilentlyContinue) {
        $n = @(Get-ChildItem -LiteralPath $d.FullName -Recurse -File -ErrorAction SilentlyContinue).Count
        $state["$($pair.tag)/$($d.Name)"] = "$n files"
    }
}

# Staging folder names are the only place a mod's Nexus id and its install time
# survive after the download is deleted - which is the whole point of this file.
if ($StagingRoot -and (Test-Path -LiteralPath $StagingRoot)) {
    foreach ($d in Get-ChildItem -LiteralPath $StagingRoot -Directory -ErrorAction SilentlyContinue) {
        $state["staged/$($d.Name)"] = '{0:yyyyMMddHHmm}' -f $d.LastWriteTimeUtc
    }
}

# --- diff against the last known state --------------------------------------

$entries = @(Read-Ledger -Path $LedgerPath)
$prev = @{}
foreach ($e in $entries) {
    if ($e.kind -eq 'baseline') {
        $prev = @{}
        foreach ($k in $e.state.PSObject.Properties.Name) { $prev[$k] = $e.state.$k }
    } elseif ($e.kind -eq 'delta') {
        foreach ($k in $e.add.PSObject.Properties.Name) { $prev[$k] = $e.add.$k }
        foreach ($k in $e.chg.PSObject.Properties.Name) { $prev[$k] = $e.chg.$k }
        foreach ($k in $e.del) { $prev.Remove($k) }
    }
}

$add = [ordered]@{}; $chg = [ordered]@{}; $del = @()
foreach ($k in $state.Keys) {
    if (-not $prev.ContainsKey($k))       { $add[$k] = $state[$k] }
    elseif ($prev[$k] -ne $state[$k])     { $chg[$k] = $state[$k] }
}
foreach ($k in $prev.Keys) { if (-not $state.Contains($k)) { $del += $k } }

$isFirst = -not $entries.Count
$nothing = (-not $isFirst) -and (-not $Baseline) -and ($add.Count + $chg.Count + $del.Count) -eq 0

if ($nothing) {
    Write-Host "install unchanged since the last entry - nothing appended ($($state.Count) items tracked)" -ForegroundColor DarkGray
    return
}

if ($isFirst -or $Baseline) {
    $line = @{ kind = 'baseline'; at = (Get-Date).ToString('s'); count = $state.Count; state = $state } | ConvertTo-Json -Compress -Depth 6
    $what = "baseline of $($state.Count) item(s)"
} else {
    $line = @{ kind = 'delta'; at = (Get-Date).ToString('s'); add = $add; chg = $chg; del = $del } | ConvertTo-Json -Compress -Depth 6
    $what = "+$($add.Count) ~$($chg.Count) -$($del.Count)"
}

if ($WhatIfOnly) {
    Write-Host "would append: $what  ($($line.Length) bytes before compression)"
    foreach ($k in @($add.Keys) + @($chg.Keys)) { Write-Host "   changed $k" -ForegroundColor DarkGray }
    foreach ($k in $del) { Write-Host "   gone    $k" -ForegroundColor DarkGray }
    return
}

Append-Ledger -Path $LedgerPath -Line $line
$sz = (Get-Item $LedgerPath).Length
Write-Host "appended $what to the ledger  ($('{0:N1}' -f ($sz/1KB)) KB total)" -ForegroundColor Green
