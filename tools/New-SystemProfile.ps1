# New-SystemProfile.ps1 -- a deterministic profile of a modded Cyberpunk 2077
# install, in Discord-pasteable markdown and as an HTML report.
#
#     .\New-SystemProfile.ps1                      # auto-detect, write both
#     .\New-SystemProfile.ps1 -GameRoot 'D:\...' -Md prof.md -Html prof.html
#
# ---------------------------------------------------------------------------
# Scope: only stats that change a diagnosis
# ---------------------------------------------------------------------------
#
# This is deliberately NOT a full system dump. Every field here exists because
# it has explained a real modding failure - "your 8K texture pack is thrashing
# 6 GB of VRAM", "your framework is a patch behind so every .reds mod is off",
# "40 archives are missing from your load order". Motherboard model and audio
# devices explain nothing about a mod, so they are not collected.
#
# The FLAGS section at the top is the point of the tool. Everything below it is
# the evidence for those flags. Someone pasting this into a help channel should
# get a useful answer from the first six lines.
#
# ---------------------------------------------------------------------------
# Deterministic
# ---------------------------------------------------------------------------
#
# Same install, same output: fixed section order, sorted enumerations, no
# hardware ordering left to WMI's whim. Two runs either side of a change should
# diff cleanly - only the timestamp and what actually changed.
#
# ---------------------------------------------------------------------------
# Traps worth knowing, since both cost real time
# ---------------------------------------------------------------------------
#
#   * Win32_VideoController.AdapterRAM is a uint32 and SATURATES AT 4 GB. Every
#     card above 4 GB reports exactly 4294967295. Read
#     HardwareInformation.qwMemorySize from the display class registry key
#     instead - it is a QWORD and reports the truth.
#   * Discord does NOT render markdown tables. Pipes-and-dashes turn into
#     unreadable line noise in the one place this file is meant to be pasted.
#     The markdown output uses fenced code blocks with aligned columns, which
#     render identically everywhere.

[CmdletBinding()]
param(
    [string] $GameRoot,
    [string] $Md   = "$env:USERPROFILE\Downloads\cp2077-system-profile.md",
    [string] $Html = "$env:USERPROFILE\Downloads\cp2077-system-profile.html",
    [switch] $NoHtml,

    # Paths and machine identity are stripped by default, because the whole
    # point of the markdown output is that it gets pasted somewhere public.
    [switch] $NoRedact
)

$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['*:ErrorAction'] = 'SilentlyContinue'

# ================================================================== helpers ==

function Get-GameRootAuto {
    <#
        Steam, GOG and Epic in that order, then a plain guess. Returns $null
        rather than a wrong path - a profile of the wrong directory is worse
        than no profile.
    #>
    $seen = [System.Collections.Generic.List[string]]::new()

    # Steam: read the library folders file rather than assuming C:\Program Files.
    $steam = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -Name InstallPath).InstallPath
    if (-not $steam) { $steam = (Get-ItemProperty 'HKCU:\SOFTWARE\Valve\Steam' -Name SteamPath).SteamPath }
    if ($steam) {
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $seen.Add((Join-Path ($m.Groups[1].Value -replace '\\\\','\') 'steamapps\common\Cyberpunk 2077'))
            }
        }
        $seen.Add((Join-Path $steam 'steamapps\common\Cyberpunk 2077'))
    }

    # GOG registry, any product id.
    foreach ($k in (Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games')) {
        $p = (Get-ItemProperty $k.PSPath -Name path).path
        if ($p -and (Test-Path -LiteralPath (Join-Path $p 'bin\x64\Cyberpunk2077.exe'))) { $seen.Add($p) }
    }

    # Epic ships a manifest per install.
    foreach ($f in (Get-ChildItem 'C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests' -Filter *.item)) {
        $j = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
        if ($j.DisplayName -match 'Cyberpunk' -and $j.InstallLocation) { $seen.Add($j.InstallLocation) }
    }

    foreach ($p in $seen) {
        if ($p -and (Test-Path -LiteralPath (Join-Path $p 'bin\x64\Cyberpunk2077.exe'))) { return $p }
    }
    return $null
}

if (-not $GameRoot) { $GameRoot = Get-GameRootAuto }
if (-not $GameRoot -or -not (Test-Path -LiteralPath (Join-Path $GameRoot 'bin\x64\Cyberpunk2077.exe'))) {
    throw "Could not locate a Cyberpunk 2077 install. Pass -GameRoot 'X:\path\to\Cyberpunk 2077'."
}
$GameRoot = (Resolve-Path -LiteralPath $GameRoot).Path

function GB { param([double]$bytes) if ($bytes -le 0) { '?' } else { '{0:N1} GB' -f ($bytes / 1GB) } }
function Ver {
    param([string]$relPath)
    $p = Join-Path $GameRoot $relPath
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    $v = (Get-Item -LiteralPath $p).VersionInfo.ProductVersion
    if (-not $v) { $v = (Get-Item -LiteralPath $p).VersionInfo.FileVersion }
    if ($v) { ($v -split '\+')[0].Trim() } else { 'present' }
}
function CountIn {
    param([string]$rel, [string]$filter, [switch]$Recurse, [switch]$Directory)
    $p = Join-Path $GameRoot $rel
    if (-not (Test-Path -LiteralPath $p)) { return 0 }
    @(Get-ChildItem -LiteralPath $p -Filter $filter -Recurse:$Recurse -Directory:$Directory -File:(-not $Directory)).Count
}

# ================================================================= hardware ==

$cs   = Get-CimInstance Win32_ComputerSystem
$os   = Get-CimInstance Win32_OperatingSystem
$cpu  = @(Get-CimInstance Win32_Processor | Sort-Object DeviceID)[0]

# Pick the adapter the game will actually run on: the one with the most VRAM.
#
# Name and VRAM must come from the SAME registry entry. Reading the name from
# Win32_VideoController and the VRAM separately pairs them wrong the moment a
# machine has more than one adapter - and plenty do: an APU's integrated
# graphics alongside a discrete card, or a USB display adapter. On one test
# machine that mismatch reported a 32 GB integrated GPU that does not exist.
#
# The VRAM has to come from the registry QWORD because
# Win32_VideoController.AdapterRAM is a uint32 and saturates: an RTX 5090 with
# 32 GB reports 4293918720 there, which is where a "4 GB" misdiagnosis comes
# from.
$adapters = foreach ($k in (Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' |
                            Where-Object { $_.PSChildName -match '^\d{4}$' } | Sort-Object PSChildName)) {
    $p = Get-ItemProperty $k.PSPath
    if ($p.DriverDesc) {
        [pscustomobject]@{ Name = [string]$p.DriverDesc; VRam = [long]($p.'HardwareInformation.qwMemorySize') }
    }
}
# Sort by VRAM then name so a tie resolves the same way on every run.
$gpu       = @($adapters | Sort-Object @{E='VRam';Descending=$true}, Name)[0]
$gpuName   = if ($gpu) { $gpu.Name } else { 'unknown' }
$vram      = if ($gpu) { $gpu.VRam } else { 0L }
$gpuDriver = (Get-CimInstance Win32_VideoController | Where-Object { $_.Name -eq $gpuName } | Select-Object -First 1).DriverVersion
if (-not $gpuDriver) { $gpuDriver = '?' }
$ramBytes  = [long]$cs.TotalPhysicalMemory

# Pagefile. A small fixed pagefile is a recurring cause of late-load crashes on
# heavily modded installs, and it is invisible unless you go looking.
$pfAuto  = [bool]$cs.AutomaticManagedPagefile
$pfBytes = 0L
foreach ($pf in @(Get-CimInstance Win32_PageFileUsage | Sort-Object Name)) { $pfBytes += ([long]$pf.AllocatedBaseSize * 1MB) }

# Game drive: type and free space.
$letter   = $GameRoot.Substring(0,1)
$vol      = Get-Volume -DriveLetter $letter
$freeBytes= if ($vol) { [long]$vol.SizeRemaining } else { 0 }
$media    = 'unknown'
$part = Get-Partition -DriveLetter $letter
if ($part) {
    $pd = Get-Disk -Number $part.DiskNumber | Get-PhysicalDisk
    if ($pd) {
        $media = "$($pd.MediaType)"
        if ($pd.BusType -eq 'NVMe') { $media = 'NVMe SSD' }
        elseif ($media -eq 'SSD')   { $media = 'SSD' }
        elseif ($media -eq 'HDD')   { $media = 'HDD' }
    }
}

# ===================================================================== game ==

$exeInfo  = (Get-Item -LiteralPath (Join-Path $GameRoot 'bin\x64\Cyberpunk2077.exe')).VersionInfo
$gameVer  = if ($exeInfo.ProductVersion) { ($exeInfo.ProductVersion -split '\+')[0].Trim() } else { 'unknown' }

$store = 'unknown'
if (Test-Path -LiteralPath (Join-Path $GameRoot 'bin\x64\steam_api64.dll'))            { $store = 'Steam' }
elseif (@(Get-ChildItem -LiteralPath $GameRoot -Filter 'goggame-*.info').Count -gt 0)  { $store = 'GOG' }
elseif (Test-Path -LiteralPath (Join-Path $GameRoot '.egstore'))                       { $store = 'Epic' }

# Mod manager. Detection is best-effort and says so - an MO2 install can look
# almost empty with the game closed, so absence of files proves nothing.
$manager = 'manual / unknown'
if (Get-ChildItem -LiteralPath $GameRoot -Recurse -Depth 3 -Filter '__folder_managed_by_vortex') { $manager = 'Vortex' }
elseif (Test-Path -LiteralPath (Join-Path $GameRoot 'usvfs_x64.dll')) { $manager = 'MO2 (USVFS)' }

# =============================================================== frameworks ==

# Ordered deliberately: load-bearing runtimes first, then content frameworks.
$frameworks = [ordered]@{
    'RED4ext'     = Ver 'red4ext\RED4ext.dll'
    'CET'         = Ver 'bin\x64\plugins\cyber_engine_tweaks.asi'
    'redscript'   = Ver 'engine\tools\scc.exe'
    'ArchiveXL'   = Ver 'red4ext\plugins\ArchiveXL\ArchiveXL.dll'
    'TweakXL'     = Ver 'red4ext\plugins\TweakXL\TweakXL.dll'
    'Codeware'    = Ver 'red4ext\plugins\Codeware\Codeware.dll'
    'ModSettings' = Ver 'red4ext\plugins\mod_settings\mod_settings.dll'
    'ReShade'     = Ver 'bin\x64\dxgi.dll'
}

# ============================================================== mod payload ==

$archDir  = Join-Path $GameRoot 'archive\pc\mod'
$archives = @(Get-ChildItem -LiteralPath $archDir -Filter *.archive -File | Sort-Object Name)
$archBytes= ($archives | Measure-Object Length -Sum).Sum
if (-not $archBytes) { $archBytes = 0 }

$payload = [ordered]@{
    'archives'   = $archives.Count
    'REDmods'    = CountIn 'mods' '*' -Directory
    '.reds'      = CountIn 'r6\scripts' '*.reds' -Recurse
    'CET mods'   = CountIn 'bin\x64\plugins\cyber_engine_tweaks\mods' '*' -Directory
    '.asi'       = CountIn 'bin\x64\plugins' '*.asi'
    'tweaks'     = (CountIn 'r6\tweaks' '*.yaml' -Recurse) + (CountIn 'r6\tweaks' '*.yml' -Recurse)
    '.xl'        = CountIn 'archive\pc\mod' '*.xl'
}

# =============================================================== load order ==

$modlist   = Join-Path $archDir 'modlist.txt'
$hasList   = Test-Path -LiteralPath $modlist
$listed    = @()
if ($hasList) {
    $listed = @(Get-Content -LiteralPath $modlist |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') })
}
$onDisk    = @($archives | ForEach-Object { $_.Name })
$unlisted  = @($onDisk | Where-Object { $listed -notcontains $_ })
$missing   = @($listed | Where-Object { $onDisk -notcontains $_ })

# ===================================================================== logs ==

# One line of truth per framework: is it running, and did it last succeed?
$redscriptState = 'not installed'
$rlog = Join-Path $GameRoot 'r6\logs\redscript_rCURRENT.log'
if (Test-Path -LiteralPath $rlog) {
    $txt = Get-Content -LiteralPath $rlog -Raw
    $redscriptState =
        if     ($txt -match '(?i)compilation failed|failed to compile') { 'FAILED to compile' }
        elseif ($txt -match '(?i)successfully compiled|compilation complete') { 'compiled OK' }
        else { 'ran, result unclear' }
}

$xlErrors = 0
$xlog = Join-Path $GameRoot 'red4ext\logs\archivexl.log'
if (Test-Path -LiteralPath $xlog) { $xlErrors = @(Select-String -LiteralPath $xlog -Pattern '\[error\]' -AllMatches).Count }

# ==================================================================== flags ==
#
# Each flag names the symptom AND the reason, because "you have 6 GB of VRAM" is
# not advice. Ordered by how likely it is to be the actual problem.

$flags = [System.Collections.Generic.List[string]]::new()

if ($vram -gt 0 -and $archBytes -gt 0) {
    $vramGB = $vram / 1GB
    $arcGB  = $archBytes / 1GB
    if ($vramGB -lt 8 -and $arcGB -gt 15) {
        $flags.Add("**VRAM $([math]::Round($vramGB)) GB against $([math]::Round($arcGB)) GB of archives.** High-res texture packs do not stream gracefully once VRAM is exhausted - expect stutter, muddy textures that never sharpen, or hard crashes in dense areas. This is the first thing to suspect with 4K/8K retextures.")
    } elseif ($vramGB -lt 12 -and $arcGB -gt 60) {
        $flags.Add("**$([math]::Round($arcGB)) GB of archives on $([math]::Round($vramGB)) GB of VRAM.** Workable, but you are near the edge; a single 8K pack can tip it. Suspect VRAM before load order if the symptom is stutter or blurry textures.")
    }
}
if ($ramBytes -gt 0 -and $ramBytes -lt 16GB) {
    $flags.Add("**System RAM $(GB $ramBytes).** A heavily modded install regularly exceeds this; the shortfall lands on the pagefile and shows up as stutter or out-of-memory crashes.")
}
if (-not $pfAuto -and $pfBytes -gt 0 -and $pfBytes -lt 8GB) {
    $flags.Add("**Fixed pagefile of $(GB $pfBytes).** Modded CP2077 commits far more than it resident-uses. A small fixed pagefile produces crashes that look random and are not - let Windows manage it, or set 16 GB+.")
} elseif ($pfBytes -eq 0) {
    $flags.Add('**No pagefile detected.** Modded CP2077 will crash under commit pressure. Enable a system-managed pagefile before diagnosing anything else.')
}
if ($media -eq 'HDD') {
    $flags.Add('**Game is on a mechanical drive.** CP2077 streams assets constantly; mods add more. Expect texture pop-in and long hitches that no load-order change will fix.')
}
if ($freeBytes -gt 0 -and $freeBytes -lt 20GB) {
    $flags.Add("**Only $(GB $freeBytes) free on the game drive.** Shader cache, logs and the pagefile all need room; low space causes failures that look like mod bugs.")
}
if ($hasList -and $unlisted.Count -gt 0) {
    $flags.Add("**$($unlisted.Count) archive(s) on disk but absent from modlist.txt.** Unlisted archives sort last, so they lose every file they contest - installed, enabled, and quite possibly doing nothing. See references/load-order.md.")
}
if ($missing.Count -gt 0) {
    $flags.Add("**$($missing.Count) modlist.txt entr(ies) with no file on disk.** Usually a disabled or removed mod. Harmless in itself, but it means the list and the folder disagree.")
}
if ($redscriptState -like 'FAILED*') {
    $flags.Add('**redscript failed to compile.** When this happens EVERY .reds mod on the install is silently off, with no in-game sign. Fix this before investigating any individual mod.')
}
if ($payload['.xl'] -gt 0 -and -not $frameworks['ArchiveXL']) {
    $flags.Add("**$($payload['.xl']) .xl file(s) present but ArchiveXL is not installed.** Those mods cannot work at all.")
}
if ($payload['tweaks'] -gt 0 -and -not $frameworks['TweakXL']) {
    $flags.Add("**$($payload['tweaks']) tweak file(s) present but TweakXL is not installed.** Those edits are being ignored.")
}
if ($payload['CET mods'] -gt 0 -and -not $frameworks['CET']) {
    $flags.Add("**$($payload['CET mods']) CET mod(s) present but Cyber Engine Tweaks is not installed.** None of them are running.")
}
if ($xlErrors -gt 0) {
    $flags.Add("**$xlErrors error(s) in the ArchiveXL log.** Usually a mod referencing something the current patch moved or renamed.")
}
if (-not $hasList -and $archives.Count -gt 1) {
    $flags.Add("**No modlist.txt.** The game falls back to alphabetical order, so filenames alone decide every conflict across $($archives.Count) archives.")
}

# =================================================================== output ==

function Redact {
    <#
        The install path is more identifying than it looks - a non-default
        library folder is a fingerprint, and it can carry an account name. What
        a helper actually needs from it is the drive (for the SSD/HDD and free
        space questions), so keep that and drop the middle.
    #>
    param([string]$s)
    if ($NoRedact) { return $s }
    $s = $s -replace [regex]::Escape($env:USERPROFILE), '~'
    if ($env:USERNAME) { $s = $s -replace "(?i)\\$([regex]::Escape($env:USERNAME))\b", '\<user>' }
    $s = $s -replace '^([A-Za-z]:)\\.*\\([^\\]+)$', '$1\...\$2'
    return $s
}

$stamp   = Get-Date -Format 'yyyy-MM-dd HH:mm'
$rootOut = Redact $GameRoot

function Pad { param([string]$k, $v, [int]$w = 12) '{0} {1}' -f $k.PadRight($w), $v }

$machineLines = @(
    Pad 'CPU'    "$($cpu.Name.Trim()) ($($cpu.NumberOfCores)c/$($cpu.NumberOfLogicalProcessors)t)"
    Pad 'RAM'    (GB $ramBytes)
    Pad 'GPU'    "$gpuName - $(if ($vram) { GB $vram } else { 'VRAM unknown' }) - driver $gpuDriver"
    Pad 'OS'     "$($os.Caption -replace 'Microsoft ','') build $($os.BuildNumber)"
    Pad 'Pagefile' $(if ($pfAuto) { "system-managed ($(GB $pfBytes))" } else { "fixed $(GB $pfBytes)" })
    Pad 'Game drive' "$letter`: $media - $(GB $freeBytes) free"
)
$gameLines = @(
    Pad 'Version' "$gameVer ($store)"
    Pad 'Managed'  $manager
    Pad 'Archives' "$($archives.Count) - $(GB $archBytes)"
    Pad 'Load order' $(if ($hasList) { "modlist.txt - $($listed.Count) entries, $($unlisted.Count) unlisted, $($missing.Count) missing" } else { 'no modlist.txt (alphabetical)' })
    Pad 'redscript'  $redscriptState
)
$fwLines      = foreach ($k in $frameworks.Keys) { Pad $k ($(if ($frameworks[$k]) { $frameworks[$k] } else { '-' })) }
$payloadLines = foreach ($k in $payload.Keys)    { Pad $k $payload[$k] }

# ---- markdown (Discord) ----
# Fenced blocks, never tables: Discord does not render markdown tables.
$mdFlags = if ($flags.Count) {
    (@($flags | ForEach-Object { "- $_" }) -join "`n")
} else {
    '- Nothing obviously wrong. If something is misbehaving it is specific to a mod, not the machine.'
}

$mdText = @"
**Cyberpunk 2077 - system profile**
``$stamp``

**Flags**
$mdFlags

**Machine**
``````
$($machineLines -join "`n")
``````

**Install**
``````
$($gameLines -join "`n")
``````

**Frameworks**
``````
$($fwLines -join "`n")
``````

**Mod payload**
``````
$($payloadLines -join "`n")
``````
"@

$dir = Split-Path -Parent $Md
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
Set-Content -LiteralPath $Md -Value $mdText -Encoding UTF8

$chars = $mdText.Length
Write-Host "wrote $Md ($chars chars)" -ForegroundColor Green
if ($chars -gt 2000) {
    Write-Warning "Discord caps a message at 2000 characters. Paste the Flags block, or attach the file."
}

# ---- html ----
if (-not $NoHtml) {
    # NOT named H: PowerShell resolves ALIASES BEFORE FUNCTIONS, and `h` is a
    # built-in alias for Get-History. A function called H is silently shadowed,
    # and the argument lands on Get-History's -Id parameter as a failed cast to
    # Int64. Single-letter helpers are a trap in PowerShell generally.
    function HtmlEsc { param([string]$s) ($s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;') }
    # Markdown bold survives into the flag text; render it rather than show it.
    function HtmlBold { param([string]$s) [regex]::Replace((HtmlEsc $s), '\*\*(.+?)\*\*', '<b>$1</b>') }

    $flagHtml = if ($flags.Count) {
        (@($flags | ForEach-Object { "<li>$(HtmlBold $_)</li>" }) -join '')
    } else {
        '<li class="ok">Nothing obviously wrong. If something is misbehaving it is specific to a mod, not the machine.</li>'
    }
    function Block { param([string[]]$lines) '<pre>' + (HtmlEsc ($lines -join "`n")) + '</pre>' }

    $htmlText = @"
<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Cyberpunk 2077 System Profile</title>
<style>
:root{--yellow:#fcee0a;--cyan:#00f0ff;--red:#ff003c;--green:#39ff88;
  --bg:#07070a;--panel:#101018;--line:#26263a;--text:#e4e4ee;--dim:#8a8aa2;
  --mono:'Consolas','SF Mono','DejaVu Sans Mono',monospace;--sans:'Segoe UI',system-ui,sans-serif}
*{box-sizing:border-box}html,body{margin:0;padding:0}
body{background:var(--bg);color:var(--text);font-family:var(--sans);font-size:16px;line-height:1.5}
.wrap{max-width:1100px;margin:0 auto;padding:0 22px 60px}
header{position:relative;padding:26px 0 14px;border-bottom:1px solid var(--line);overflow:hidden}
header::after{content:'';position:absolute;inset:0;pointer-events:none;
  background:repeating-linear-gradient(0deg,rgba(0,0,0,.34) 0 1px,transparent 1px 3px)}
h1{font-family:var(--mono);font-size:clamp(24px,4vw,40px);margin:0;letter-spacing:.08em;
  text-transform:uppercase;color:var(--yellow);text-shadow:2px 0 var(--red),-2px 0 var(--cyan)}
h1 span{color:var(--text);text-shadow:none}
.sub{font-family:var(--mono);font-size:12px;letter-spacing:.14em;color:var(--dim);margin-top:8px}
h2{font-family:var(--mono);font-size:12px;letter-spacing:.2em;text-transform:uppercase;color:var(--cyan);
  margin:28px 0 10px;padding-bottom:7px;border-bottom:1px solid var(--line)}
ul{list-style:none;padding:0;margin:0}
li{background:var(--panel);border:1px solid var(--line);border-left:3px solid var(--red);
  padding:12px 15px;margin-bottom:9px;font-size:15px}
li.ok{border-left-color:var(--green);color:var(--dim)}
li b{color:var(--yellow);font-weight:600}
pre{background:var(--panel);border:1px solid var(--line);padding:14px 16px;margin:0;
  font-family:var(--mono);font-size:14px;color:#c8c8da;overflow-x:auto}
footer{margin-top:34px;padding-top:14px;border-top:1px solid var(--line);
  font-family:var(--mono);font-size:11px;color:#4c4c60;line-height:1.7}
</style></head><body><div class="wrap">
<header><h1>System <span>Profile</span></h1>
<div class="sub">CYBERPUNK 2077 $(HtmlEsc $gameVer) &nbsp;//&nbsp; $(HtmlEsc $store) &nbsp;//&nbsp; $stamp</div></header>
<h2>Flags</h2><ul>$flagHtml</ul>
<h2>Machine</h2>$(Block $machineLines)
<h2>Install</h2>$(Block $gameLines)
<h2>Frameworks</h2>$(Block $fwLines)
<h2>Mod payload</h2>$(Block $payloadLines)
<footer>$(HtmlEsc $rootOut)<br>Generated $stamp // CYBERWISE. Only fields that change a diagnosis are collected.</footer>
</div></body></html>
"@
    $hdir = Split-Path -Parent $Html
    if ($hdir -and -not (Test-Path -LiteralPath $hdir)) { New-Item -ItemType Directory -Path $hdir -Force | Out-Null }
    Set-Content -LiteralPath $Html -Value $htmlText -Encoding UTF8
    Write-Host "wrote $Html" -ForegroundColor Green
}

Write-Host "$($flags.Count) flag(s) raised" -ForegroundColor $(if ($flags.Count) { 'Yellow' } else { 'Green' })
