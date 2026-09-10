# Get-ModDependencies.ps1 -- who needs whom, across a deployed load order, and
# which mods are carrying nobody.
#
#     .\Get-ModDependencies.ps1                       # summary + orphan candidates
#     .\Get-ModDependencies.ps1 -Mod 'Codeware'       # both directions for one mod
#     .\Get-ModDependencies.ps1 -Orphans              # just the list
#     .\Get-ModDependencies.ps1 -Json                 # the whole graph, for a report
#
# WHY THE DEPLOYMENT MANIFEST. Nothing on disk under r6\scripts says which mod
# put a file there. vortex.deployment.json does, file by file, and it describes
# what is deployed RIGHT NOW rather than what is staged. A dependency graph built
# from staging would include mods that are installed and switched off, which is
# the difference between "this is load-bearing" and "this was, once".
#
# WHAT COUNTS AS AN EDGE
#
#   redscript   `import Some.Module`            hard - the compile fails without it
#               `@if(ModuleExists("Some.Mod"))` soft - the mod handles its absence
#   CET Lua     `GetMod("Name")`                soft - Lua checks at runtime
#               `require("OtherMod/...")`       hard
#
# Hard and soft are reported separately and they mean different things. A hard
# edge is a promise: remove the provider and the WHOLE redscript compile fails,
# taking every other mod down with it, not just the one that asked. A soft edge
# is a mod being polite.
#
# WHAT "ORPHAN" MEANS HERE, AND WHAT IT DOES NOT
#
# A mod is an orphan candidate when all three hold:
#
#   1. it PROVIDES something - defines at least one redscript module
#   2. nothing deployed imports any of them
#   3. it does nothing on its own - no archive, no tweaks, no hooks into game
#      classes, no CET event registrations
#
# All three matter. (1) alone is every framework. (2) alone flags a mod that
# simply has no dependents, which is most mods. (3) is what separates a library
# nobody uses from a mod that acts by itself and happens to export a symbol.
#
# It is a CANDIDATE list, not a delete list. Three known ways it can be wrong:
# an archive can reference a resource this mod supplies without any script
# saying so; a CET mod can look another up by a name built at runtime; and a
# framework can be a dependency of something you have not installed yet. Read
# the reasons it prints, do not just act on the names.

[CmdletBinding()]
param(
    [string] $GameRoot,

    # One mod: everything it needs, and everything that needs it. Substring match.
    [string] $Mod,

    # Only the orphan candidates.
    [switch] $Orphans,

    # Emit the graph as JSON on stdout instead of a report.
    [switch] $Json
)

$ErrorActionPreference = 'Stop'

# NOTE: do not introduce a local named $mod. PowerShell variable names are
# case-insensitive, so $mod IS the -Mod parameter, and a loop over every
# deployed mod silently sets it - which sends the script down the single-mod
# branch on a run that asked for the summary. That happened on the first run of
# this file. Locals here are $owningMod for exactly that reason.

# --- upstream guard ---------------------------------------------------------
$cwGuard = Join-Path $PSScriptRoot '..\..\cyberwise\tools\UpstreamGuard.ps1'
if (Test-Path -LiteralPath $cwGuard) { try { . $cwGuard; Invoke-CwStartupGuard } catch { } }

# --- find the game ----------------------------------------------------------
if (-not $GameRoot) {
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
    foreach ($c in $cands) { if (Test-Path -LiteralPath (Join-Path $c 'bin\x64\Cyberpunk2077.exe')) { $GameRoot = $c; break } }
}
if (-not $GameRoot) { throw "Could not find the game. Pass -GameRoot." }

$manifestPath = Join-Path $GameRoot 'vortex.deployment.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "No vortex.deployment.json under $GameRoot - this needs a Vortex-deployed install to know who owns which file."
}

Write-Verbose "manifest: $manifestPath"
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

# --- file -> owning mod -----------------------------------------------------
$owner = @{}
foreach ($f in $manifest.files) { $owner[$f.relPath.ToLowerInvariant()] = $f.source }

# Trim Vortex's decoration so the report says what a person would say.
function Get-ShortName {
    param([string] $Staging)
    $n = $Staging -replace '-\d{3,7}-[\w.\-]*-?\d{9,11}$', ''
    $n = $n -replace '\s+\d{3,7}\s+[\w.]+\s+20\d\d-\d\d-\d\dT[\d-]+Z\s+\w+$', ''
    return $n.Trim()
}

# --- scan -------------------------------------------------------------------
$provides   = @{}   # module name -> mod
$needsHard  = @{}   # mod -> set of module names
$needsSoft  = @{}
$actsAlone  = @{}   # mod -> reason it does something by itself
$hasContent = @{}
$modFiles   = @{}

$reModule  = [regex]'(?m)^\s*module\s+([A-Za-z0-9_.]+)'
# `import Foo.Bar.*` is the common redscript idiom and [A-Za-z0-9_.]+ is greedy,
# so it captures "Foo.Bar." WITH the trailing dot - which matches no declared
# module and silently drops the edge. 943 of 1637 imports on this install are
# wildcards, so that shape was losing most of the hard graph. Requiring a name
# character after every dot makes a trailing dot uncapturable.
$reImport  = [regex]'(?m)^\s*import\s+([A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*)'
$reExists  = [regex]'ModuleExists\(\s*"([^"]+)"\s*\)'
# A mod acts on its own in two ways, and the first version of this only knew
# about one of them. Annotations are the obvious route. But a class extending
# ScriptableService or ScriptableSystem registers itself and runs its `cb func
# On...` callbacks with NO annotation anywhere - ReImagined does exactly that in
# 27 files and was reported as doing nothing. So did the rent mod written the
# same day. Miss this and the orphan list fills with mods that are working fine.
$reHook    = [regex]'@(wrapMethod|replaceMethod|addMethod|addField|replaceGlobal)|extends\s+Scriptable(Service|System)\b|cb\s+func\s+On[A-Za-z]'
$reCetMod  = [regex]'GetMod\(\s*[''"]([^''"]+)[''"]\s*\)'
$reRequire = [regex]'require\(\s*[''"]([^''"]+)[''"]\s*\)'
$reCetEvt  = [regex]'registerFor(Event|AllEvents)'

foreach ($entry in $manifest.files) {
    $rel = $entry.relPath
    $owningMod = $entry.source
    if (-not $modFiles.ContainsKey($owningMod)) { $modFiles[$owningMod] = 0 }
    $modFiles[$owningMod]++

    $ext = [IO.Path]::GetExtension($rel).ToLowerInvariant()

    # content layers: a mod shipping these is doing something regardless of code
    if ($ext -eq '.archive') { $hasContent[$owningMod] = 'ships an archive' }
    elseif ($rel -match '(^|\\)r6\\tweaks\\') { if (-not $hasContent.ContainsKey($owningMod)) { $hasContent[$owningMod] = 'ships TweakXL records' } }
    elseif ($ext -eq '.xl')  { if (-not $hasContent.ContainsKey($owningMod)) { $hasContent[$owningMod] = 'ships an ArchiveXL manifest' } }

    if ($ext -ne '.reds' -and $ext -ne '.lua') { continue }
    $full = Join-Path $GameRoot $rel
    if (-not (Test-Path -LiteralPath $full)) { continue }
    $text = [IO.File]::ReadAllText($full)

    if ($ext -eq '.reds') {
        foreach ($m in $reModule.Matches($text)) { $provides[$m.Groups[1].Value] = $owningMod }
        foreach ($m in $reImport.Matches($text)) {
            if (-not $needsHard.ContainsKey($owningMod)) { $needsHard[$owningMod] = @{} }
            $needsHard[$owningMod][$m.Groups[1].Value] = $true
        }
        foreach ($m in $reExists.Matches($text)) {
            if (-not $needsSoft.ContainsKey($owningMod)) { $needsSoft[$owningMod] = @{} }
            $needsSoft[$owningMod][$m.Groups[1].Value] = $true
        }
        if (-not $actsAlone.ContainsKey($owningMod)) {
            if ([regex]::IsMatch($text, '@(wrapMethod|replaceMethod|addMethod|addField|replaceGlobal)')) {
                $actsAlone[$owningMod] = 'hooks game classes'
            } elseif ([regex]::IsMatch($text, 'extends\s+Scriptable(Service|System)\b')) {
                $actsAlone[$owningMod] = 'runs a ScriptableService/System of its own'
            } elseif ([regex]::IsMatch($text, 'cb\s+func\s+On[A-Za-z]')) {
                $actsAlone[$owningMod] = 'handles engine callbacks'
            }
        }
    } else {
        foreach ($m in $reCetMod.Matches($text)) {
            if (-not $needsSoft.ContainsKey($owningMod)) { $needsSoft[$owningMod] = @{} }
            $needsSoft[$owningMod]["cet:" + $m.Groups[1].Value] = $true
        }
        foreach ($m in $reRequire.Matches($text)) {
            $r = $m.Groups[1].Value
            if ($r -match '^(modules?|Modules?)[\\/]') { continue }   # its own submodule
            if (-not $needsSoft.ContainsKey($owningMod)) { $needsSoft[$owningMod] = @{} }
            $needsSoft[$owningMod]["cet:" + $r] = $true
        }
        if ($reCetEvt.IsMatch($text) -and -not $actsAlone.ContainsKey($owningMod)) {
            $actsAlone[$owningMod] = 'registers CET events'
        }
    }
}

# --- resolve module names to providers, both directions ---------------------
$dependsOn  = @{}   # mod -> @{ provider -> 'hard'|'soft' }
$dependedBy = @{}

function Add-Edge { param($From, $To, $Kind)
    if ($From -eq $To) { return }
    if (-not $dependsOn.ContainsKey($From))  { $dependsOn[$From]  = @{} }
    if (-not $dependedBy.ContainsKey($To))   { $dependedBy[$To]   = @{} }
    if ($dependsOn[$From][$To] -ne 'hard')   { $dependsOn[$From][$To] = $Kind }
    if ($dependedBy[$To][$From] -ne 'hard')  { $dependedBy[$To][$From] = $Kind }
}

foreach ($owningMod in $needsHard.Keys) {
    foreach ($modName in $needsHard[$owningMod].Keys) {
        if ($provides.ContainsKey($modName)) { Add-Edge $owningMod $provides[$modName] 'hard' }
    }
}
foreach ($owningMod in $needsSoft.Keys) {
    foreach ($k in $needsSoft[$owningMod].Keys) {
        if ($k -like 'cet:*') {
            $needle = $k.Substring(4)
            foreach ($cand in $modFiles.Keys) {
                if ((Get-ShortName $cand) -eq $needle -or $cand -eq $needle) { Add-Edge $owningMod $cand 'soft'; break }
            }
        } elseif ($provides.ContainsKey($k)) { Add-Edge $owningMod $provides[$k] 'soft' }
    }
}

# --- orphan candidates ------------------------------------------------------
$providerMods = @{}
foreach ($k in $provides.Keys) { $providerMods[$provides[$k]] = $true }

$orphanList = @()
foreach ($owningMod in $providerMods.Keys) {
    if ($dependedBy.ContainsKey($owningMod) -and $dependedBy[$owningMod].Count -gt 0) { continue }
    if ($actsAlone.ContainsKey($owningMod))  { continue }
    if ($hasContent.ContainsKey($owningMod)) { continue }
    $mods = @($provides.Keys | Where-Object { $provides[$_] -eq $owningMod })
    # A mod whose scripts are only `native` declarations is a binding layer for a
    # RED4ext plugin. Its consumers may be native code this scan cannot see, so
    # it is the shape most likely to be a false positive - flag it as such.
    $native = $false
    foreach ($fe in $manifest.files) {
        if ($fe.source -ne $owningMod) { continue }
        if ([IO.Path]::GetExtension($fe.relPath).ToLowerInvariant() -ne '.reds') { continue }
        $fp = Join-Path $GameRoot $fe.relPath
        if (Test-Path -LiteralPath $fp) {
            if ([regex]::IsMatch([IO.File]::ReadAllText($fp), '(?m)^\s*(public\s+)?native\s+(class|func|struct)')) { $native = $true }
        }
    }
    $orphanList += [pscustomobject]@{
        Mod     = Get-ShortName $owningMod
        Staging = $owningMod
        Modules = $mods
        Files   = $modFiles[$owningMod]
        Native  = $native
    }
}
$orphanList = @($orphanList | Sort-Object Mod)

# --- output -----------------------------------------------------------------
if ($Json) {
    $edges = foreach ($f in $dependsOn.Keys) {
        foreach ($t in $dependsOn[$f].Keys) {
            [pscustomobject]@{ from = (Get-ShortName $f); to = (Get-ShortName $t); kind = $dependsOn[$f][$t] }
        }
    }
    [pscustomobject]@{
        generated = (Get-Date).ToString('s')
        mods      = $modFiles.Count
        edges     = @($edges)
        orphans   = $orphanList
    } | ConvertTo-Json -Depth 6
    return
}

if ($Mod) {
    $hits = @($modFiles.Keys | Where-Object { $_ -like "*$Mod*" })
    if (-not $hits.Count) { Write-Host "no deployed mod matching '$Mod'"; return }
    foreach ($h in $hits) {
        Write-Host ""
        Write-Host (Get-ShortName $h) -ForegroundColor Green
        Write-Host ("  staging : {0}" -f $h)
        $mine = @($provides.Keys | Where-Object { $provides[$_] -eq $h })
        if ($mine.Count) { Write-Host ("  provides: {0}" -f ($mine -join ', ')) }

        Write-Host "  DEPENDS ON:"
        if ($dependsOn.ContainsKey($h) -and $dependsOn[$h].Count) {
            foreach ($t in ($dependsOn[$h].Keys | Sort-Object)) {
                Write-Host ("     [{0}] {1}" -f $dependsOn[$h][$t], (Get-ShortName $t)) -ForegroundColor $(if ($dependsOn[$h][$t] -eq 'hard') { 'Yellow' } else { 'DarkGray' })
            }
        } else { Write-Host "     nothing" -ForegroundColor DarkGray }

        Write-Host "  DEPENDED ON BY:"
        if ($dependedBy.ContainsKey($h) -and $dependedBy[$h].Count) {
            foreach ($t in ($dependedBy[$h].Keys | Sort-Object)) {
                Write-Host ("     [{0}] {1}" -f $dependedBy[$h][$t], (Get-ShortName $t)) -ForegroundColor $(if ($dependedBy[$h][$t] -eq 'hard') { 'Yellow' } else { 'DarkGray' })
            }
        } else { Write-Host "     nothing" -ForegroundColor DarkGray }
    }
    return
}

if (-not $Orphans) {
    $hard = 0; $soft = 0
    foreach ($f in $dependsOn.Keys) { foreach ($t in $dependsOn[$f].Keys) { if ($dependsOn[$f][$t] -eq 'hard') { $hard++ } else { $soft++ } } }
    Write-Host ("deployed mods      : {0}" -f $modFiles.Count)
    Write-Host ("redscript modules  : {0} provided by {1} mod(s)" -f $provides.Count, $providerMods.Count)
    Write-Host ("dependency edges   : {0} hard, {1} soft" -f $hard, $soft)
    Write-Host ""
    Write-Host "most depended on:" -ForegroundColor Cyan
    $dependedBy.GetEnumerator() | Sort-Object { $_.Value.Count } -Descending | Select-Object -First 10 | ForEach-Object {
        $h = @($_.Value.Keys | Where-Object { $_.Value -eq 'hard' }).Count
        Write-Host ("  {0,3}  {1}" -f $_.Value.Count, (Get-ShortName $_.Key))
    }
    Write-Host ""
}

Write-Host ("orphan candidates: {0}" -f $orphanList.Count) -ForegroundColor $(if ($orphanList.Count) { 'Yellow' } else { 'Green' })
Write-Host "(provides modules, nothing imports them, and it does nothing on its own)"
foreach ($o in $orphanList) {
    Write-Host ""
    Write-Host ("  {0}" -f $o.Mod) -ForegroundColor Yellow
    Write-Host ("     provides : {0}" -f ($o.Modules -join ', '))
    Write-Host ("     files    : {0}" -f $o.Files)
    Write-Host ("     staging  : {0}" -f $o.Staging)
    if ($o.Native) {
        Write-Host "     NOTE     : declares native bindings - this is a RED4ext plugin's script" -ForegroundColor DarkGray
        Write-Host "                surface, and its callers may be native code this scan cannot see." -ForegroundColor DarkGray
    }
}
if ($orphanList.Count) {
    Write-Host ""
    Write-Host "These are CANDIDATES. An archive can reference a resource no script mentions," -ForegroundColor DarkGray
    Write-Host "a CET mod can resolve a name at runtime, and a framework can be waiting for a" -ForegroundColor DarkGray
    Write-Host "mod you have not installed yet. Check before removing anything." -ForegroundColor DarkGray
}
