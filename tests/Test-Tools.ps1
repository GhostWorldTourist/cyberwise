# Test-Tools.ps1 -- behaviour tests for the shipped tools, against fixtures.
#
#     .\tests\Test-Tools.ps1
#
# WHAT THIS IS FOR
#
# Test-Family.ps1 checks that the family is filed correctly and that every .ps1
# parses. Parsing is not working. Every defect these tools have actually shipped
# was a live-data bug that parsed perfectly:
#
#   - '#' treated as a comment marker in modlist.txt, which silently discarded 61
#     real entries and reported all 61 as "on disk but unlisted" - a fabricated
#     load-order fault, reported to a user twice before it was caught
#   - an LZ4 match copied with a block move instead of byte-at-a-time, which
#     breaks the overlapping runs LZ4 uses to encode repeats
#   - redaction that stopped covering a field, in a report designed to be pasted
#     in public
#
# So these tests build synthetic installs and run the real scripts against them.
# No game, no hardware assumptions, no network. Fixtures are per-test and torn
# down; nothing is written outside the temp directory.

[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),

    # Skip the headless-browser checks. They are the slow part by a wide margin,
    # and Test-ToolMutations.ps1 runs this whole suite nine times over - so it
    # passes -Quick, being a harness for mutations that cannot reach page fit.
    # Never pass it for a real run.
    [switch] $Quick
)

$script:pass = 0
$script:fail = 0
function Ok  { param($m) $script:pass++; Write-Host "ok    $m" -ForegroundColor DarkGreen }
function Bad { param($m, $d) $script:fail++; Write-Host "FAIL  $m" -ForegroundColor Red; if ($d) { $d -split "`n" | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkRed } } }
function Skip { param($m, $why) Write-Host "skip  $m" -ForegroundColor Yellow; Write-Host "        $why" -ForegroundColor DarkYellow }

$tools = @{
    Profile = Join-Path $Root 'skills\cyberwise-reports\tools\New-SystemProfile.ps1'
    PageFit = Join-Path $Root 'skills\cyberwise-reports\tools\Measure-PageFit.ps1'
    Preset  = Join-Path $Root 'skills\cyberwise-saves\tools\Decode-Preset.ps1'
    Save    = Join-Path $Root 'skills\cyberwise-saves\tools\Expand-Save.ps1'
}

$sandbox = Join-Path ([IO.Path]::GetTempPath()) ("cw-tools-" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $sandbox -Force | Out-Null

# A game root the tools will accept. They gate on the exe existing, so a stub is
# enough - none of the load-order logic reads it.
function New-FixtureGame {
    param([string]$Name, [string[]]$Archives, [string[]]$ModlistLines, [switch]$NoModlist)
    $g = Join-Path $sandbox $Name
    $mod = Join-Path $g 'archive\pc\mod'
    New-Item -ItemType Directory -Path $mod -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $g 'bin\x64') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $g 'bin\x64\Cyberpunk2077.exe') 'stub' -NoNewline
    foreach ($a in $Archives) { Set-Content -LiteralPath (Join-Path $mod $a) 'x' -NoNewline }
    if (-not $NoModlist) { Set-Content -LiteralPath (Join-Path $mod 'modlist.txt') (($ModlistLines -join "`n") + "`n") -NoNewline }
    return $g
}

function Get-Profile {
    param([string]$GameRoot, [switch]$NoRedact, [switch]$WithHtml)
    $id   = [guid]::NewGuid().ToString('N').Substring(0,6)
    $md   = Join-Path $sandbox "profile-$id.md"
    $html = Join-Path $sandbox "profile-$id.html"
    $splat = @{ GameRoot = $GameRoot; Md = $md }
    if ($WithHtml) { $splat.Html = $html } else { $splat.NoHtml = $true }
    if ($NoRedact) { $splat.NoRedact = $true }
    & $tools.Profile @splat *>$null
    if ($WithHtml) { return (Get-Content -LiteralPath $html -Raw) }
    return (Get-Content -LiteralPath $md -Raw)
}

# Write-Host writes to the INFORMATION stream, not stdout. Capturing a tool's
# console report needs 6>&1; without it every assertion below runs against an
# empty string and passes or fails for the wrong reason.
function Get-Console {
    param([scriptblock]$Call)
    return (& $Call 6>&1 2>&1 | Out-String)
}

Write-Host "tool fixtures under $sandbox`n"

# ============================================================ load order =====
#
# The regression that matters most. '#' and '!' are legitimate LEADING
# characters in archive filenames - mods use them to sort early - so a parser
# that strips '^#' as comments drops real entries and then reports them as
# missing from the very list they are in.

$g = New-FixtureGame -Name 'hash-in-modlist' `
    -Archives @('#ZZZ_first.archive', '!bang.archive', 'normal.archive', 'orphan.archive') `
    -ModlistLines @('#ZZZ_first.archive', '!bang.archive', 'normal.archive', 'gone.archive')

$rep = Get-Profile -GameRoot $g

# 4 entries proves nothing was stripped; 3 would mean '#' was eaten as a comment.
if ($rep -match 'modlist\.txt - (\d+) entries, (\d+) unlisted, (\d+) missing') {
    $entries, $unlisted, $missing = [int]$matches[1], [int]$matches[2], [int]$matches[3]
    $problems = @(
        if ($entries -ne 4)  { "counted $entries modlist entries, expected 4 - a '#' line was probably stripped as a comment" }
        # orphan.archive only. If '#' were stripped, #ZZZ_first would join it.
        if ($unlisted -ne 1) { "reported $unlisted unlisted, expected exactly 1 (orphan.archive)" }
        if ($missing -ne 1)  { "reported $missing missing, expected exactly 1 (gone.archive)" }
    )
    if ($problems) { Bad "modlist.txt: '#' is a filename character, not a comment" ($problems -join "`n") }
    else           { Ok  "modlist.txt: '#'- and '!'-led entries count as listed" }
} else {
    Bad "modlist.txt: '#' is a filename character, not a comment" 'the report has no load-order summary line at all'
}

# The counters above could both be right by accident if the tool simply never
# reports anything. Prove the detector fires when there IS something to find.
if ($rep -match 'archive\(s\) on disk but absent from modlist\.txt') {
    Ok 'an genuinely unlisted archive is still flagged'
} else {
    Bad 'an genuinely unlisted archive is still flagged' 'orphan.archive was on disk and not in the list, but nothing was raised'
}

# ...and that it stays quiet when there is not. A check that always fires is as
# useless as one that never does.
$clean = New-FixtureGame -Name 'clean-modlist' `
    -Archives @('#early.archive', 'b.archive') -ModlistLines @('#early.archive', 'b.archive')
$cleanRep = Get-Profile -GameRoot $clean
if ($cleanRep -match 'on disk but absent from modlist') {
    Bad 'a fully-listed install raises no unlisted flag' "flagged something on an install where every archive is listed - almost certainly the '#' bug"
} else {
    Ok 'a fully-listed install raises no unlisted flag'
}

$none = New-FixtureGame -Name 'no-modlist' -Archives @('a.archive') -NoModlist
$noneRep = Get-Profile -GameRoot $none
if ($noneRep -match 'No modlist\.txt' -or $noneRep -match 'no modlist\.txt \(alphabetical\)') {
    Ok 'a missing modlist.txt is reported as alphabetical fallback'
} else {
    Bad 'a missing modlist.txt is reported as alphabetical fallback' 'no mention of the fallback in the report'
}

# ============================================================== redaction ====
#
# The markdown output exists to be pasted into Discord. Redaction is on by
# default; a field that quietly stops being covered leaks a real username.

$redacted = Get-Profile -GameRoot $g
$leaks = @(
    if ($redacted -match [regex]::Escape($env:USERNAME)) { "the Windows username appears in the redacted report" }
    if ($redacted -match [regex]::Escape($sandbox))      { "the full fixture path appears in the redacted report" }
    if ($redacted -match 'C:\\Users\\')                  { "a C:\Users\ path appears in the redacted report" }
)
if ($leaks) { Bad 'the markdown carries no path or machine identity' ($leaks -join "`n") }
else        { Ok  'the markdown carries no path or machine identity' }

# The install path reaches the HTML footer only - the markdown never carries it
# at all. Redaction is therefore an HTML-side property, and this is where a
# regression would actually leak.
$htmlRed = Get-Profile -GameRoot $g -WithHtml
$htmlLeaks = @(
    if ($htmlRed -match [regex]::Escape($env:USERPROFILE)) { 'the user profile path is in the HTML footer' }
    if ($htmlRed -match "(?i)\\$([regex]::Escape($env:USERNAME))\b") { 'the Windows username is in the HTML footer' }
)
if ($htmlLeaks) { Bad 'the HTML footer redacts the install path by default' ($htmlLeaks -join "`n") }
else            { Ok  'the HTML footer redacts the install path by default' }

# And -NoRedact must actually turn it off, or the switch is a lie. Fixtures live
# under the temp dir, so the un-redacted footer should show that real path.
$htmlPlain = Get-Profile -GameRoot $g -WithHtml -NoRedact
if ($htmlPlain -match [regex]::Escape((Split-Path -Leaf $g))) { Ok 'the -NoRedact switch restores the real path' }
else { Bad 'the -NoRedact switch restores the real path' 'the path was still redacted with -NoRedact' }

# ================================================================== LZ4 ======
#
# Expand-Save carries a hand-rolled LZ4 BLOCK decoder because .NET has none. The
# subtle part is that a match must be copied ONE BYTE AT A TIME: LZ4 encodes
# repeats as a match that overlaps its own output, so a block move produces
# zeroes or stale bytes where the repeat should be.

function New-Lz4Save {
    param([byte[]]$Block, [int]$DecompressedSize, [string]$Path)
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([byte[]][char[]]'VASC')          # magic, stored reversed
    $bw.Write([uint32]193)                     # saveVersion
    $bw.Write([uint32]13)                      # gameVersion
    $bw.Write([byte[]](,0 * 13))               # 13 misc bytes
    $bw.Write([byte[]][char[]]'FZLC')          # chunk table marker (scanned for)
    $bw.Write([uint32]1)                       # chunkCount
    $payloadAt = 25 + 8 + 12                   # header+marker+count, then one triplet
    $bw.Write([uint32]$payloadAt)              # fileOffset
    $bw.Write([uint32]($Block.Length + 8))     # compressedSize, incl. 8-byte chunk header
    $bw.Write([uint32]$DecompressedSize)       # decompressedSize
    $bw.Write([byte[]][char[]]'XNLZ')          # chunk header
    $bw.Write([uint32]$DecompressedSize)
    $bw.Write($Block)
    $bw.Flush()
    [IO.File]::WriteAllBytes($Path, $ms.ToArray())
    $bw.Dispose(); $ms.Dispose()
}

# token 0x22: literal length 2, match length 2+4=6. Literals "ab", then a match
# at offset 2 - which reads bytes the match itself is writing. Correct output is
# "abababab"; a block-move decoder gives "ab" followed by six wrong bytes.
$overlap = [byte[]]@(0x22, 0x61, 0x62, 0x02, 0x00)
$savePath = Join-Path $sandbox 'overlap.dat'
$outPath  = Join-Path $sandbox 'overlap.bin'
New-Lz4Save -Block $overlap -DecompressedSize 8 -Path $savePath
& $tools.Save -SavePath $savePath -OutPath $outPath *>$null
$got = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($outPath))
if ($got -eq 'abababab') { Ok 'LZ4: an overlapping match decodes as a repeat' }
else { Bad 'LZ4: an overlapping match decodes as a repeat' "got '$got', expected 'abababab' - the match copy is not byte-at-a-time" }

# Literals-only, the other end of the token encoding: high nibble 5, low nibble 0.
$literal = [byte[]]@(0x50, 0x68, 0x65, 0x6C, 0x6C, 0x6F)   # "hello"
$savePath2 = Join-Path $sandbox 'literal.dat'
$outPath2  = Join-Path $sandbox 'literal.bin'
New-Lz4Save -Block $literal -DecompressedSize 5 -Path $savePath2
& $tools.Save -SavePath $savePath2 -OutPath $outPath2 *>$null
$got2 = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($outPath2))
if ($got2 -eq 'hello') { Ok 'LZ4: a literals-only block decodes' }
else { Bad 'LZ4: a literals-only block decodes' "got '$got2', expected 'hello'" }

# ============================================================ ACU presets ====
#
# A preset key is an FNV1a-64 hash of the customization GROUP name, not a
# localization key. The rule that matters: an unrecognised hash must be PRINTED,
# never dropped, or a preset silently reports as smaller than it is.

$presetDir = Join-Path $sandbox 'presets'
New-Item -ItemType Directory -Path $presetDir -Force | Out-Null
$csv = Join-Path $Root 'skills\cyberwise-saves\tools\preset-groups.csv'
$map = @{}; Import-Csv $csv | ForEach-Object { $map[$_.Group] = $_.Hash }

$hairHash = $map['hairstyle']
$bogus    = '1234567890123456789'
Set-Content -LiteralPath (Join-Path $presetDir 'Nomad alpha.preset') "LocKey#${hairHash}:12`nLocKey#${bogus}:3`n"
Set-Content -LiteralPath (Join-Path $presetDir 'Nomad beta.preset')  "LocKey#${hairHash}:29`n"

$one = Get-Console { & $tools.Preset -Path (Join-Path $presetDir 'Nomad alpha.preset') -GroupCsv $csv }
$problems = @(
    if ($one -notmatch 'Hairstyle')      { 'a known group did not resolve to its label' }
    if ($one -notmatch [regex]::Escape("?$bogus")) { 'an unknown hash was dropped instead of printed as ?<hash>' }
    if ($one -notmatch '\b12\b')         { 'the slider index was lost' }
)
if ($problems) { Bad 'presets: known groups resolve and unknown hashes survive' ($problems -join "`n") }
else           { Ok  'presets: known groups resolve and unknown hashes survive' }

# The compare table strips the prefix every preset name shares, so the character
# name does not eat the column width. It must derive that prefix, not assume one.
$cmp = Get-Console { & $tools.Preset -Directory $presetDir -Compare -GroupCsv $csv }
if ($cmp -match '\balpha\b' -and $cmp -match '\bbeta\b' -and $cmp -notmatch 'Nomad\s+alpha') {
    Ok 'presets: the shared name prefix is derived and stripped'
} else {
    Bad 'presets: the shared name prefix is derived and stripped' "expected bare 'alpha'/'beta' columns`n$cmp"
}

# A shared prefix that is not a whole word must be left alone - trimming "Val"
# off "Valkyrie"/"Valerie" would mangle both names.
$midWord = Join-Path $sandbox 'midword'
New-Item -ItemType Directory -Path $midWord -Force | Out-Null
Set-Content -LiteralPath (Join-Path $midWord 'Valkyrie.preset') "LocKey#${hairHash}:1`n"
Set-Content -LiteralPath (Join-Path $midWord 'Valerie.preset')  "LocKey#${hairHash}:2`n"
$mw = Get-Console { & $tools.Preset -Directory $midWord -Compare -GroupCsv $csv }
if ($mw -match 'Valkyrie' -and $mw -match 'Valerie') {
    Ok 'presets: a mid-word shared prefix is left intact'
} else {
    Bad 'presets: a mid-word shared prefix is left intact' "names were trimmed at a non-word boundary`n$mw"
}

# ================================================================ hotkeys ====
#
# The flagship method rule is "never quote a mod's shipped defaults as the user's
# configuration". Get-Hotkeys is where that rule is implemented, across five
# separate stores, and it is the tool most likely to answer confidently and
# wrongly - a key it fails to find reads as a key that is FREE.

$hk = New-FixtureGame -Name 'hotkeys' -Archives @() -NoModlist
New-Item -ItemType Directory -Path (Join-Path $hk 'r6\input') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $hk 'r6\cache') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $hk 'red4ext\plugins\mod_settings') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $hk 'bin\x64\plugins\cyber_engine_tweaks') -Force | Out-Null

# The mod SHIPS F3, and declares the binding overridable.
Set-Content -LiteralPath (Join-Path $hk 'r6\input\TestMod.xml') @'
<?xml version="1.0" encoding="UTF-8"?>
<bindings>
  <context name="Exploration">
    <action name="TestMod_Toggle" map="TestMod_Toggle_Button"/>
  </context>
  <mapping name="TestMod_Toggle_Button" type="Button">
    <button id="IK_F3" overridableUI="testModHotkey"/>
  </mapping>
  <mapping name="TestMod_Grouped_Button" type="Button">
    <button id="grpTest"/>
  </mapping>
</bindings>
'@

# A buttonGroup is an indirection: the mapping names a group, not a key.
Set-Content -LiteralPath (Join-Path $hk 'r6\cache\inputUserMappings.xml') @'
<?xml version="1.0" encoding="UTF-8"?>
<root>
  <buttonGroup id="grpTest">
    <button id="IK_F5"/>
  </buttonGroup>
</root>
'@

# ...and the USER actually rebound it to F7. This is the value that must win.
Set-Content -LiteralPath (Join-Path $hk 'red4ext\plugins\mod_settings\user.ini') @'
[TestMod.Config]
testModHotkey = IK_F7
'@

# CET packs a virtual-key code into the high bits, and ships keys that differ
# only in case. Without -AsHashtable, ConvertFrom-Json throws on those and the
# whole harvest dies - so this fixture is really testing that it does not.
$vkA = [long]65 -shl 48    # 'A'
$vkB = [long]66 -shl 48    # 'B'
Set-Content -LiteralPath (Join-Path $hk 'bin\x64\plugins\cyber_engine_tweaks\bindings.json') @"
{
  "testcet": {
    "HideMeshes": "$vkA",
    "hideMeshes": "$vkB",
    "NeverSet": "0"
  }
}
"@

$hkTool = Join-Path $Root 'skills\cyberwise-hotkeys\tools\Get-Hotkeys.ps1'
$bind = $null
$hkErr = $null
try { $bind = @(& $hkTool -GameRoot $hk 3>$null) } catch { $hkErr = $_.Exception.Message }

if ($hkErr) {
    Bad 'hotkeys: the five-store harvest survives a case-colliding bindings.json' "the tool threw: $hkErr"
} else {
    Ok 'hotkeys: the five-store harvest survives a case-colliding bindings.json'

    $toggle = $bind | Where-Object { $_.Action -match '(?i)toggle' } | Select-Object -First 1
    if (-not $toggle) {
        Bad "hotkeys: the user's rebind beats the mod's shipped default" 'the overridable binding never appeared at all'
    } else {
        $problems = @(
            if ($toggle.Key -notmatch '(?i)F7') { "reported '$($toggle.Key)', but user.ini rebound it to F7" }
            if ($toggle.Key -match  '(?i)F3')   { "reported the SHIPPED default F3 as if it were the user's setting" }
            if ($toggle.Source -notmatch '(?i)your setting') { "labelled the source '$($toggle.Source)' rather than the user's own setting" }
        )
        if ($problems) { Bad "hotkeys: the user's rebind beats the mod's shipped default" ($problems -join "`n") }
        else           { Ok  "hotkeys: the user's rebind beats the mod's shipped default" }
    }

    $grouped = $bind | Where-Object { $_.Action -match '(?i)grouped' } | Select-Object -First 1
    if ($grouped -and $grouped.Key -match '(?i)F5') { Ok 'hotkeys: a buttonGroup indirection resolves to its key' }
    else { Bad 'hotkeys: a buttonGroup indirection resolves to its key' "expected F5 from the cache's buttonGroup, got '$($grouped.Key)'" }

    # 0 means unbound in CET's packing. Reporting it as a real binding would tell
    # the user a free key is taken.
    if ($bind | Where-Object { $_.Action -match '(?i)never ?set' }) {
        Bad 'hotkeys: a CET value of 0 is treated as unbound' 'an unbound CET entry was reported as a live binding'
    } else {
        Ok 'hotkeys: a CET value of 0 is treated as unbound'
    }
}

# ================================================================ page fit ===
#
# The trap this guards: scrollHeight has the viewport as its floor, so
# DocHeight == ViewHeight only means "not taller than the viewport". A tool that
# reads equality as "fits" calls every page a pass.

# Same discovery list the tool itself uses - Edge counts, and on a stock Windows
# box it is the only one present.
$browser = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if ($Quick) {
    Skip 'page fit: headless browser checks' '-Quick was passed'
} elseif (-not $browser) {
    Skip 'page fit: a too-tall page is reported as not fitting' 'no Chromium browser found - headless measurement unavailable'
} else {
    $tall  = Join-Path $sandbox 'tall.html'
    $short = Join-Path $sandbox 'short.html'
    Set-Content -LiteralPath $tall  '<title>tall</title><body style="margin:0"><div style="height:4000px;background:#333"></div></body>'
    Set-Content -LiteralPath $short '<title>short</title><body style="margin:0"><div style="height:100px;background:#333"></div></body>'

    $rt = & $tools.PageFit -Path $tall  -Width 1200 -Height 800 2>&1 | Out-String
    $rs = & $tools.PageFit -Path $short -Width 1200 -Height 800 2>&1 | Out-String

    if ($rt -match '(?i)\bno\b|does not fit|overflow|too tall|FAIL') { Ok 'page fit: a 4000px page is reported as not fitting' }
    else { Bad 'page fit: a 4000px page is reported as not fitting' $rt }

    if ($rs -match '(?i)fits|\byes\b|OK') { Ok 'page fit: a short page is reported as fitting' }
    else { Bad 'page fit: a short page is reported as fitting' $rs }
}

# =================================================================== report ==

Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($script:fail) { Write-Host "$($script:pass) passed, $($script:fail) FAILED" -ForegroundColor Red; exit 1 }
Write-Host "$($script:pass) passed, 0 failed" -ForegroundColor Green
exit 0
