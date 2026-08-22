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
#
# THE NO-NETWORK RULE IS LOAD-BEARING. New-ModManifest picks up a Nexus key from
# Credential Manager on its own, so the manifest fixture MUST pass -NoNexus - the
# first run of it fetched real descriptions for six invented mod ids off the live
# API. A test suite that calls somebody else's server is not a test suite.

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

# Write-Warning is stream 3, which Get-Console does not take. The Discord cap is
# reported as a warning, so those tests need everything the tool emits.
function Get-AllOutput {
    param([scriptblock]$Call)
    return (& $Call *>&1 | Out-String)
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

# ============================================================ discord cap ====
#
# The markdown exists to be pasted into a help channel, and Discord does not
# truncate an over-long message - it REFUSES it. So a report that quietly runs
# past 2000 characters is one the user cannot send at all, and finds that out
# while already stuck. The tool has to say so itself.
#
# A profile only runs long when a flag carries a lot of items, so the fixture is
# an install whose archives and modlist entries all have long names.
$capNames = 1..8 | ForEach-Object { "unlisted-$_-" + ('x' * 100) + '.archive' }
$capGone  = 1..8 | ForEach-Object { "missing-$_-"  + ('x' * 100) + '.archive' }
$capGame  = New-FixtureGame -Name 'discord-cap' -Archives $capNames -ModlistLines $capGone
$capMd    = Join-Path $sandbox 'cap.md'
$capOut   = Get-AllOutput { & $tools.Profile -GameRoot $capGame -Md $capMd -NoHtml }
$capChars = (Get-Content -LiteralPath $capMd -Raw).Length

if ($capChars -le 2000) {
    Bad 'the markdown warns when it is too long to paste' `
        "the fixture only produced $capChars characters, so the warning was never reachable - the test proves nothing"
} elseif ($capOut -match '2000') {
    Ok 'the markdown warns when it is too long to paste'
} else {
    Bad 'the markdown warns when it is too long to paste' `
        "$capChars characters written and nothing said about the cap:`n$capOut"
}

# And it must stay quiet on a report that fits, or the warning is noise people
# learn to scroll past. The clean fixture raises no flags at all, so its markdown
# is the smallest this tool ever writes.
$smallMd  = Join-Path $sandbox 'small.md'
$smallOut = Get-AllOutput { & $tools.Profile -GameRoot $clean -Md $smallMd -NoHtml }
$smallChars = (Get-Content -LiteralPath $smallMd -Raw).Length
if ($smallChars -gt 2000) {
    Skip 'a pasteable markdown says nothing about the cap' "even the minimal report is $smallChars characters"
} elseif ($smallOut -match '2000') {
    Bad 'a pasteable markdown says nothing about the cap' "warned about the cap on a $smallChars-character report"
} else {
    Ok 'a pasteable markdown says nothing about the cap'
}

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
# off "Jackie"/"Jackson" would mangle both names.
$midWord = Join-Path $sandbox 'midword'
New-Item -ItemType Directory -Path $midWord -Force | Out-Null
Set-Content -LiteralPath (Join-Path $midWord 'Jackie.preset') "LocKey#${hairHash}:1`n"
Set-Content -LiteralPath (Join-Path $midWord 'Jackson.preset')  "LocKey#${hairHash}:2`n"
$mw = Get-Console { & $tools.Preset -Directory $midWord -Compare -GroupCsv $csv }
if ($mw -match 'Jackie' -and $mw -match 'Jackson') {
    Ok 'presets: a mid-word shared prefix is left intact'
} else {
    Bad 'presets: a mid-word shared prefix is left intact' "names were trimmed at a non-word boundary`n$mw"
}

# ================================================================= backups ===
#
# The undo gap. Nothing in this family modifies a user's install, but an
# assistant following it will - modlist.txt, another author's .yaml, user.ini -
# and those edits have no undo. These tests exist because the FIRST version of
# Show-ModFileDiff reported "3 lines removed, 0 added" for a one-line insertion:
# `(if (...) {...} else {...})` is not a valid sub-expression in PowerShell, so
# the new text came back empty. The write was correct; only the PREVIEW lied.
#
# A preview that lies is worse than no preview, because it is the thing the user
# is being asked to approve.

. (Join-Path $Root 'skills\cyberwise\tools\ModFileBackup.ps1')

$vault = Join-Path $sandbox 'vault'
$mf    = Join-Path $sandbox 'modlist.txt'
$orig  = "#early.archive`nb.archive`nc.archive"
Set-Content -LiteralPath $mf -Value $orig -NoNewline

# --- the diff must be arithmetically true ---------------------------------
$d = Show-ModFileDiff -Path $mf -NewText "#early.archive`nb.archive`nZZZ.archive`nc.archive" 6>$null
$problems = @(
    if (-not $d.Changed)   { 'an inserted line was reported as no change' }
    if ($d.Added   -ne 1)  { "reported $($d.Added) lines added, expected 1" }
    if ($d.Removed -ne 0)  { "reported $($d.Removed) lines removed, expected 0 - the preview is lying about the edit" }
)
if ($problems) { Bad 'backups: the diff counts the actual change' ($problems -join "`n") }
else           { Ok  'backups: the diff counts the actual change' }

# A preview must not touch the file.
if ((Get-Content -LiteralPath $mf -Raw) -eq $orig) { Ok 'backups: a preview writes nothing' }
else { Bad 'backups: a preview writes nothing' 'Show-ModFileDiff modified the file' }

# An identical write is not a change, and must not burn a snapshot.
$same = Show-ModFileDiff -Path $mf -NewText $orig 6>$null
if (-not $same.Changed) { Ok 'backups: an identical write reports no change' }
else { Bad 'backups: an identical write reports no change' 'a no-op edit was reported as a change' }

# --- write, then undo ------------------------------------------------------
$updated = "#early.archive`nb.archive`nZZZ.archive`nc.archive"
$snap = Set-ModFileContent -Path $mf -NewText $updated -Note 'test' -Vault $vault -Confirm:$false 6>$null
if ((Get-Content -LiteralPath $mf -Raw) -eq $updated) { Ok 'backups: the safe write actually writes' }
else { Bad 'backups: the safe write actually writes' 'the file was not updated' }

Restore-ModFile -Path $mf -Vault $vault -Confirm:$false 6>$null | Out-Null
if ((Get-Content -LiteralPath $mf -Raw) -eq $orig) { Ok 'backups: restore returns the original bytes' }
else { Bad 'backups: restore returns the original bytes' "got: $(Get-Content -LiteralPath $mf -Raw)" }

# Restoring must itself be undoable, or picking the wrong snapshot is a dead end.
if ((Get-ModFileBackup -Path $mf -Vault $vault).Count -ge 2) {
    Ok 'backups: a restore snapshots the state it replaced'
} else {
    Bad 'backups: a restore snapshots the state it replaced' 'restore left no way back to the pre-restore contents'
}

# --- the vault must not live in the install --------------------------------
# A manager purge or redeploy owns the game tree and will take the backups with
# it. Default vault must be outside it.
$defaultVault = Get-ModBackupVault
if ($defaultVault -like "*$([IO.Path]::DirectorySeparatorChar)Cyberpunk 2077*") {
    Bad 'backups: the default vault is outside the game directory' "vault resolves to $defaultVault"
} elseif ($defaultVault -like "$env:LOCALAPPDATA*") {
    Ok 'backups: the default vault is outside the game directory'
} else {
    Bad 'backups: the default vault is outside the game directory' "unexpected vault location: $defaultVault"
}

# --- refuse to swallow an archive ------------------------------------------
$big = Join-Path $sandbox 'huge.archive'
$fs = [IO.File]::Create($big); $fs.SetLength(60MB); $fs.Close()
$threw = $false
try { Backup-ModFile -Path $big -Vault $vault -ErrorAction Stop | Out-Null } catch { $threw = $true }
if ($threw) { Ok 'backups: an oversized file is refused without -Force' }
else { Bad 'backups: an oversized file is refused without -Force' 'a 60 MB file was copied into the vault silently' }
Remove-Item -LiteralPath $big -Force

# ============================================================ snapshots ======
#
# The diff has to catch a LOAD ORDER move: the file is byte-identical, its
# timestamp is unchanged, and only its position in modlist.txt differs - so it
# now wins or loses files it did not before, with no evidence anywhere on disk.
# That is the change this tool exists for, and the one a hash-based approach
# misses entirely.

$snapTool = Join-Path $Root 'skills\cyberwise-crashes\tools\New-InstallSnapshot.ps1'
$cmpTool  = Join-Path $Root 'skills\cyberwise-crashes\tools\Compare-InstallSnapshot.ps1'

$snapGame = New-FixtureGame -Name 'snapgame' `
    -Archives @('a.archive','b.archive','c.archive') `
    -ModlistLines @('a.archive','b.archive','c.archive')

# Snapshots go to a real user path, so redirect to the sandbox for the test.
$snapHome = Join-Path $sandbox 'snaphome'
New-Item -ItemType Directory -Path (Join-Path $snapHome 'Saved Games\CD Projekt Red\Cyberpunk 2077\Cyberwise\snapshots') -Force | Out-Null
$realProfile = $env:USERPROFILE
try {
    $env:USERPROFILE = $snapHome

    Get-Console { & $snapTool -GameRoot $snapGame -Label 'one' } | Out-Null
    Start-Sleep -Seconds 1     # snapshot names are per-second; two in one second collide

    # Reorder ONLY - no file on disk changes at all.
    Set-Content -LiteralPath (Join-Path $snapGame 'archive\pc\mod\modlist.txt') `
        "c.archive`na.archive`nb.archive`n" -NoNewline
    Get-Console { & $snapTool -GameRoot $snapGame -Label 'two' } | Out-Null

    $diff = Get-Console { & $cmpTool }
    $problems = @(
        if ($diff -notmatch 'LOAD ORDER')  { 'a pure reorder was not reported' }
        if ($diff -notmatch 'c\.archive')  { 'the moved entry was not named' }
        if ($diff -match 'ARCHIVE \+')     { 'reported an added archive when none was added' }
        if ($diff -match 'ARCHIVE -')      { 'reported a removed archive when none was removed' }
    )
    if ($problems) { Bad 'snapshots: a load-order move is detected with no file change' ($problems -join "`n") }
    else           { Ok  'snapshots: a load-order move is detected with no file change' }

    # A genuinely added mod must show up too.
    Start-Sleep -Seconds 1
    Set-Content -LiteralPath (Join-Path $snapGame 'archive\pc\mod\d.archive') 'x' -NoNewline
    Get-Console { & $snapTool -GameRoot $snapGame -Label 'three' } | Out-Null
    $diff2 = Get-Console { & $cmpTool }
    if ($diff2 -match 'ARCHIVE \+' -and $diff2 -match 'd\.archive') { Ok 'snapshots: an added archive is reported' }
    else { Bad 'snapshots: an added archive is reported' "no addition reported:`n$diff2" }

    # And no change must report no change, or the tool cries wolf.
    Start-Sleep -Seconds 1
    Get-Console { & $snapTool -GameRoot $snapGame -Label 'four' } | Out-Null
    $diff3 = Get-Console { & $cmpTool }
    if ($diff3 -match 'Nothing changed') { Ok 'snapshots: an unchanged install reports no change' }
    else { Bad 'snapshots: an unchanged install reports no change' "reported changes on an untouched install:`n$diff3" }
}
finally { $env:USERPROFILE = $realProfile }

# ========================================================== patch watch ======
#
# The sweep that makes overriding another author's file safe. Without it, an
# override silently keeps winning over every fix they ship afterwards - the one
# failure mode that made overriding a whole file a bad idea in the first place.

. (Join-Path $Root 'skills\cyberwise\tools\ModPatchWatch.ps1')

$pwDir = Join-Path $sandbox 'patchwatch'
New-Item -ItemType Directory -Path $pwDir -Force | Out-Null
$script:PatchStore = Join-Path $pwDir 'patches.json'   # never touch the real store

$upstream = Join-Path $pwDir 'their.yaml'
$override = Join-Path $pwDir 'mine.yaml'
Set-Content -LiteralPath $upstream 'author: v1' -NoNewline
Set-Content -LiteralPath $override 'mine: v1'   -NoNewline

Register-ModPatch -Name 'T' -UpstreamPath $upstream -OverridePath $override -Note 'why' 6>$null | Out-Null

$s = (Test-ModPatches -Quiet | Where-Object Name -eq 'T').State
if ($s -eq 'OK') { Ok 'patchwatch: an untouched upstream file reports OK' }
else { Bad 'patchwatch: an untouched upstream file reports OK' "reported $s" }

# The one that matters: the author ships an update.
Set-Content -LiteralPath $upstream 'author: v2 with their own fix' -NoNewline
$s = (Test-ModPatches -Quiet | Where-Object Name -eq 'T').State
if ($s -eq 'CHANGED') { Ok 'patchwatch: an upstream update is detected' }
else { Bad 'patchwatch: an upstream update is detected' "reported $s - a stale override would go unnoticed" }

# Re-registering against the new version clears it, which is the re-derive loop.
Register-ModPatch -Name 'T' -UpstreamPath $upstream -OverridePath $override -Note 'why' 6>$null | Out-Null
$s = (Test-ModPatches -Quiet | Where-Object Name -eq 'T').State
if ($s -eq 'OK') { Ok 'patchwatch: re-registering after re-deriving clears the warning' }
else { Bad 'patchwatch: re-registering after re-deriving clears the warning' "reported $s" }

# An override that is not actually installed protects nothing.
Remove-Item -LiteralPath $override -Force
$s = (Test-ModPatches -Quiet | Where-Object Name -eq 'T').State
if ($s -eq 'NOOVER') { Ok 'patchwatch: a missing override file is reported' }
else { Bad 'patchwatch: a missing override file is reported' "reported $s" }

Remove-Item -LiteralPath $upstream -Force
$s = (Test-ModPatches -Quiet | Where-Object Name -eq 'T').State
if ($s -eq 'GONE') { Ok 'patchwatch: an uninstalled upstream mod is reported' }
else { Bad 'patchwatch: an uninstalled upstream mod is reported' "reported $s" }

$script:PatchStore = Join-Path $env:LOCALAPPDATA 'cyberwise\patches.json'   # restore

# =============================================================== manifest ====
#
# The manifest reads a manager's staging folder names, and Vortex's convention is
# the only reason tier 1 works without credentials:
#
#     <Display Name>-<NexusID>-<version>-<unix timestamp>
#
# Nothing enforces it. An MO2 folder or a hand-unzipped one simply does not
# match, and the rule that matters is that those still LIST - a mod dropped from
# an inventory is a mod nobody knows they have.

$stage = Join-Path $sandbox 'staging'
function New-StagedMod {
    param([string]$Folder, [string[]]$Files, [string]$Root = $stage)
    foreach ($f in $Files) {
        $full = Join-Path (Join-Path $Root $Folder) $f
        New-Item -ItemType Directory -Path (Split-Path $full) -Force | Out-Null
        Set-Content -LiteralPath $full 'x' -NoNewline
    }
}

# A name with hyphens in it, so the lazy match has to find the RIGHT id.
New-StagedMod 'Cyber-Engine-Tweaks-107-1-35-1-1750000000' @('bin\x64\plugins\cyber_engine_tweaks\mods\foo\init.lua')
# Version segments are not always numeric - "2k" and "1-0-beta" are real.
New-StagedMod 'Preem Textures-777-2k-1750000000'          @('archive\pc\mod\y.archive')
New-StagedMod 'Better Handling-1234-2-1-0-1750000000'     @('archive\pc\mod\x.archive')
# No Vortex convention at all: MO2, or unzipped by hand.
New-StagedMod 'ManuallyUnzippedMod'                       @('r6\scripts\a.reds')
# A genuine ASI, which must not be confused with the CET case above.
New-StagedMod 'RealAsi-42-1-0-1750000000'                 @('bin\x64\plugins\thing.asi')
New-StagedMod 'NothingKnown-66-1-0-1750000000'            @('readme.txt')

$manifestTool = Join-Path $Root 'skills\cyberwise-reports\tools\New-ModManifest.ps1'
$mdOut  = Join-Path $sandbox 'manifest.md'
$htmOut = Join-Path $sandbox 'manifest.html'

# -NoNexus is mandatory here. With a key in Credential Manager the tool would
# reach the live API and fetch real descriptions for these invented ids - slow,
# non-deterministic, and rude to somebody else's server.
$mmConsole = Get-Console {
    & $manifestTool -StagingRoot $stage -Out $mdOut -HtmlOut $htmOut -NoNexus `
        -CachePath (Join-Path $sandbox 'mm-cache.json') -OverridePath (Join-Path $sandbox 'nsfw.json')
}
$mm = Get-Content -LiteralPath $mdOut -Raw

# Sections are '## <kind>  (n)'; split so a mod filed under the wrong one shows.
$sections = @{}
$curKind = $null
foreach ($line in ($mm -split "`r?`n")) {
    if ($line -match '^##\s+(\S+)') { $curKind = $matches[1]; $sections[$curKind] = @(); continue }
    if ($curKind -and $line -match '^\*\*') { $sections[$curKind] += $line }
}

$problems = @(
    if ($mm -notmatch '\*\*6\*\* mods listed') { 'not all six staged folders were listed' }
    # The lazy name match must not stop at the first hyphen.
    if ($mm -notmatch 'Cyber-Engine-Tweaks\]\(https://www\.nexusmods\.com/cyberpunk2077/mods/107\)') {
        'a hyphenated mod name did not resolve to the right Nexus id'
    }
    if ($mm -notmatch 'v2k')     { 'a non-numeric version ("2k") was lost or mangled' }
    if ($mm -notmatch 'v2\.1\.0'){ 'a dashed version (2-1-0) did not become 2.1.0' }
)
if ($problems) { Bad 'manifest: Vortex folder names parse into name, id and version' ($problems -join "`n") }
else           { Ok  'manifest: Vortex folder names parse into name, id and version' }

# The one that matters most: a non-conforming folder must still appear.
if ($mm -match '\*\*ManuallyUnzippedMod\*\*') {
    Ok 'manifest: a folder with no Vortex convention still lists'
} else {
    Bad 'manifest: a folder with no Vortex convention still lists' 'an MO2/hand-unzipped mod was dropped from the inventory entirely'
}

# bin\x64\plugins is an ANCESTOR of the CET mods path, so a naive Test-Path tags
# every CET mod as an ASI plugin as well.
#
# Section headings alone cannot show this: a mod is filed under its PRIMARY
# footprint, and CET wins that ordering either way. The spurious second label
# only surfaces in the meta line, which joins multiple footprints as "CET+ASI".
# Asserting on the section would pass while the bug was present - it did.
$asi = $sections['ASI']
$cet = $sections['CET']
$problems = @(
    if (-not ($cet -match 'Cyber-Engine-Tweaks')) { 'the CET mod was not filed under CET' }
    if ($mm -match 'CET\+ASI')                    { 'the CET mod was ALSO tagged ASI - bin\x64\plugins matched as an ancestor' }
    if (-not ($asi -match 'RealAsi'))             { 'a real .asi plugin was not tagged ASI' }
)
if ($problems) { Bad 'manifest: a CET mod is not mistaken for an ASI plugin' ($problems -join "`n") }
else           { Ok  'manifest: a CET mod is not mistaken for an ASI plugin' }

if ($sections['other'] -match 'NothingKnown') { Ok 'manifest: an unrecognised layout is filed as other, not dropped' }
else { Bad 'manifest: an unrecognised layout is filed as other, not dropped' 'the mod with no known deploy path vanished' }

# -NoNexus has to mean NO network, including the stored-credential path.
if ($mmConsole -match '(?i)unique ids|Credential Manager') {
    Bad 'manifest: -NoNexus makes no network call' "the tool still went looking for a key or ids:`n$mmConsole"
} else {
    Ok 'manifest: -NoNexus makes no network call'
}

# A manifest exists to be handed to somebody else, and the staging root it was
# built from carries the Windows username. Nobody proof-reads a header before
# pasting, so the safe form has to be the default one.
#
# BOTH outputs, not just the HTML. The markdown is the one that gets pasted into
# a Discord thread, and it names the staging root in its own header line - that
# leak shipped while the HTML header was already redacted.
$mmHtml = Get-Content -LiteralPath $htmOut -Raw
$mmLeaks = @(
    if ($mm     -match "(?i)\\$([regex]::Escape($env:USERNAME))\b") { 'the Windows username is in the markdown' }
    if ($mmHtml -match "(?i)\\$([regex]::Escape($env:USERNAME))\b") { 'the Windows username is in the HTML' }
    if ($mm     -match [regex]::Escape($env:USERPROFILE))           { 'the full profile path is in the markdown' }
    if ($mmHtml -match [regex]::Escape($env:USERPROFILE))           { 'the full profile path is in the HTML' }
)
if ($mmLeaks) { Bad 'manifest: both outputs redact the staging path by default' ($mmLeaks -join "`n") }
else          { Ok  'manifest: both outputs redact the staging path by default' }

# And -NoRedact has to actually turn it off in both, or the switch is a lie in
# whichever output forgot it. The fixture lives under the temp dir, which is
# inside the profile path, so an un-redacted header must contain it verbatim.
$mdPlain  = Join-Path $sandbox 'manifest-plain.md'
$htmPlain = Join-Path $sandbox 'manifest-plain.html'
& $manifestTool -StagingRoot $stage -Out $mdPlain -HtmlOut $htmPlain -NoNexus -NoRedact `
    -CachePath (Join-Path $sandbox 'mm-cache.json') -OverridePath (Join-Path $sandbox 'nsfw.json') *>$null
$plainMd   = Get-Content -LiteralPath $mdPlain  -Raw
$plainHtml = Get-Content -LiteralPath $htmPlain -Raw
$notRestored = @(
    if ($plainMd   -notmatch [regex]::Escape($env:USERPROFILE)) { 'the markdown was still redacted with -NoRedact' }
    if ($plainHtml -notmatch [regex]::Escape($env:USERPROFILE)) { 'the HTML was still redacted with -NoRedact' }
)
if ($notRestored) { Bad 'manifest: -NoRedact restores the real staging path' ($notRestored -join "`n") }
else              { Ok  'manifest: -NoRedact restores the real staging path' }

# A manifest of any real load order is far past Discord's message cap, and the
# same rule applies as to the profile: an over-long message is refused, not
# trimmed. The tool cannot make an 800-mod inventory pasteable, so it says the
# size and names the two things that do work.
$bigStage = Join-Path $sandbox 'staging-big'
1..40 | ForEach-Object { New-StagedMod -Root $bigStage -Folder "Padding Mod $_-$(1000 + $_)-1-0-1750000000" -Files @('archive\pc\mod\p.archive') }
$bigMdOut = Join-Path $sandbox 'manifest-big.md'
$bigConsole = Get-AllOutput {
    & $manifestTool -StagingRoot $bigStage -Out $bigMdOut -NoHtml -NoNexus `
        -CachePath (Join-Path $sandbox 'mm-cache.json') -OverridePath (Join-Path $sandbox 'nsfw.json')
}
$bigChars = (Get-Content -LiteralPath $bigMdOut -Raw).Length
if ($bigChars -le 2000) {
    Bad 'manifest: an unpasteable markdown says so' `
        "40 mods only produced $bigChars characters, so the notice was never reachable - the test proves nothing"
} elseif ($bigConsole -match '2000') {
    Ok 'manifest: an unpasteable markdown says so'
} else {
    Bad 'manifest: an unpasteable markdown says so' `
        "$bigChars characters written and nothing said about the cap:`n$bigConsole"
}

# =============================================================== feedback ====
#
# The report is written FOR a stranger on the internet, by a tool the user did
# not read, out of text they did not check. Three ways that goes wrong, all of
# them silent: it carries their username, it is too long for the channel it was
# built for, or it states a fact nobody gave it.

$reportTool = Join-Path $Root 'skills\cyberwise-feedback\tools\New-ProblemReport.ps1'
$prOut      = Join-Path $sandbox 'problem-report.md'
$prDiscord  = [IO.Path]::ChangeExtension($prOut, '.discord.md')

# A stack trace is the realistic way a full path reaches a report - the user
# pastes one in without reading it. Redaction has to cover the whole document,
# not the fields the tool happens to know about.
$prError = @"
Get-Content: $env:USERPROFILE\repos\cyberwise\skills\cyberwise-hotkeys\tools\Get-Hotkeys.ps1:212
Cannot find path '$env:USERPROFILE\Documents\nope.xml' because it does not exist.
"@
$prDetail = (1..60 | ForEach-Object { "Line $_ of a long description that somebody pasted in without trimming it." }) -join "`n"

$prConsole = Get-AllOutput {
    & $reportTool -Summary 'the hotkey sheet shows a key I rebound' -Detail $prDetail `
        -Expected 'my binding, not the one the mod ships' -Area 'cyberwise-hotkeys' `
        -ErrorText $prError -Out $prOut
}
$prFull  = Get-Content -LiteralPath $prOut -Raw
$prShort = Get-Content -LiteralPath $prDiscord -Raw

$problems = @(
    if ($prFull -notmatch 'the hotkey sheet shows a key I rebound') { 'the summary is not in the report' }
    if ($prFull -notmatch '(?m)^## What happened')                  { 'no "what happened" section' }
    if ($prFull -notmatch '(?m)^## What I expected')                { 'no "what I expected" section' }
    if ($prFull -notmatch '(?m)^## Environment')                    { 'no environment block' }
    if ($prFull -notmatch 'cyberwise\s+\S')                         { 'the environment block names no cyberwise version' }
)
if ($problems) { Bad 'feedback: the report carries what the author needs' ($problems -join "`n") }
else           { Ok  'feedback: the report carries what the author needs' }

$prLeaks = @(
    if ($prFull  -match [regex]::Escape($env:USERPROFILE)) { 'the profile path survived into the full report' }
    if ($prShort -match [regex]::Escape($env:USERPROFILE)) { 'the profile path survived into the Discord form' }
    if ($prFull  -match "(?i)$([regex]::Escape($env:USERNAME))")  { 'the account name is in the full report' }
    if ($prShort -match "(?i)$([regex]::Escape($env:USERNAME))")  { 'the account name is in the Discord form' }
)
if ($prLeaks) { Bad 'feedback: a pasted stack trace is redacted too' ($prLeaks -join "`n") }
else          { Ok  'feedback: a pasted stack trace is redacted too' }

# The whole point of the second file. Discord refuses an over-long message, so
# one that does not fit is one that never arrives.
$prShortProblems = @(
    if ($prShort.Length -gt 2000)      { "the Discord form is $($prShort.Length) characters - it would be refused" }
    if ($prFull.Length -le 2000)       { 'the fixture was not long enough to need trimming - the test proves nothing' }
    if ($prShort -notmatch 'dropped')  { 'it trimmed silently, so the sender thinks they pasted everything' }
    if ($prShort -notmatch 'the hotkey sheet shows a key I rebound') { 'the summary was trimmed away - it took from the wrong end' }
)
if ($prShortProblems) { Bad 'feedback: the Discord form fits one message and says what it dropped' ($prShortProblems -join "`n") }
else                  { Ok  'feedback: the Discord form fits one message and says what it dropped' }

# "not provided" is a fact. A guessed game path produces a plausible report about
# a game nobody was playing, which is worse than a blank.
$prNoGame = Join-Path $sandbox 'pr-nogame.md'
& $reportTool -Summary 'x' -Out $prNoGame *>$null
$prNoGameText = Get-Content -LiteralPath $prNoGame -Raw
$prBogus = Join-Path $sandbox 'pr-bogus.md'
& $reportTool -Summary 'x' -GameRoot (Join-Path $sandbox 'no-such-game') -Out $prBogus *>$null
$prBogusText = Get-Content -LiteralPath $prBogus -Raw
$prGuesses = @(
    if ($prNoGameText -notmatch 'game patch\s+not provided') { 'with no -GameRoot it did not say the patch was not provided' }
    if ($prNoGameText -match 'game patch\s+\d+\.\d+')        { 'it reported a patch version nobody gave it' }
    if ($prBogusText  -match 'game patch\s+\d+\.\d+')        { 'a path with no game in it still produced a version' }
)
if ($prGuesses) { Bad 'feedback: an unknown game patch is reported as unknown' ($prGuesses -join "`n") }
else            { Ok  'feedback: an unknown game patch is reported as unknown' }

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

# The sheet's markdown twin, built from the same harvest. A key sheet is the
# thing people paste when asking why a bind does nothing, so what it must not do
# is lose a row or break its own table - a pipe inside a key name ends the cell
# early and every column after it shifts.

$sheetTool = Join-Path $Root 'skills\cyberwise-hotkeys\tools\New-HotkeySheet.ps1'
$hkMd   = Join-Path $sandbox 'hotkeys.md'
$hkHtml = Join-Path $sandbox 'hotkeys.html'
$sheetOut = Get-AllOutput { & $sheetTool -GameRoot $hk -Out $hkHtml -Md $hkMd }
$hkMdText = Get-Content -LiteralPath $hkMd -Raw

$hkMdBad = @(
    if ($hkMdText -notmatch '(?m)^\| Key \| Action \| Mod \|') { 'no binding table in the markdown' }
    # F7 is the user's own rebind; F5 comes from the buttonGroup indirection.
    # Both are in the harvest, so both have to survive the render.
    if ($hkMdText -notmatch 'F7') { "the user's rebound key is missing from the markdown" }
    # Every row must have the same number of cells as the header, or the table
    # collapses in every renderer that is stricter than GitHub.
    foreach ($row in ([regex]::Matches($hkMdText, '(?m)^\|.*\|$') | ForEach-Object { $_.Value })) {
        if ($row -notmatch '^\| --- ' -and (($row -split '(?<!\)\|').Count -ne 5)) { "a table row has the wrong cell count: $row" }
    }
)
if ($hkMdBad) { Bad 'hotkeys: the markdown sheet is a well-formed table of the same bindings' (($hkMdBad | Select-Object -Unique) -join "`n") }
else          { Ok  'hotkeys: the markdown sheet is a well-formed table of the same bindings' }

# ============================================================== readiness ====
#
# The value of this tool is one distinction: problems LAUNCHING FIXES versus
# problems it does not. Get that backwards and it is worse than no tool - either
# it nags about something the next launch resolves, or it stays quiet about mods
# that will lose every conflict forever.
#
# The trap it already fell into: a hardlinking manager deploys by making a second
# name for the staging inode, so a deployed .reds keeps the mod AUTHOR'S
# timestamp. Comparing only *.reds mtimes said "everything predates the bundle"
# for ten mods deployed the day before.

$readyTool = Join-Path $Root 'skills\cyberwise\tools\Test-InstallReady.ps1'
$rdyGame = Join-Path $sandbox 'readygame'
New-Item -ItemType Directory -Path (Join-Path $rdyGame 'bin\x64') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $rdyGame 'bin\x64\Cyberpunk2077.exe') 'stub' -NoNewline
New-Item -ItemType Directory -Path (Join-Path $rdyGame 'archive\pc\mod') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $rdyGame 'r6\logs') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $rdyGame 'r6\cache\modded') -Force | Out-Null

# An archive with no modlist entry sorts last and loses every contest, and no
# launch changes that.
Set-Content -LiteralPath (Join-Path $rdyGame 'archive\pc\mod\listed.archive') 'x' -NoNewline
Set-Content -LiteralPath (Join-Path $rdyGame 'archive\pc\mod\forgotten.archive') 'x' -NoNewline
Set-Content -LiteralPath (Join-Path $rdyGame 'archive\pc\mod\modlist.txt') "listed.archive`ngone.archive`n" -NoNewline

$rdyOut = Get-AllOutput { & $readyTool -GameRoot $rdyGame }
$problems = @(
    if ($rdyOut -notmatch 'NOT READY')                   { 'an unlisted archive did not make the install "not ready"' }
    if ($rdyOut -notmatch 'forgotten\.archive')          { 'the unlisted archive was not named' }
    if ($rdyOut -notmatch 'LAUNCHING WILL NOT FIX')      { 'it did not separate what launching cannot fix' }
    # A stale line is normal - it holds the slot of a mod disabled on purpose -
    # so it must not be dressed up as a problem.
    if ($rdyOut -match '(?m)^\s+stale entries.*\n?.*LAUNCHING WILL NOT FIX') { 'a stale modlist line was treated as an action item' }
)
if ($problems) { Bad 'readiness: an unlisted archive is reported as launching-will-not-fix' ($problems -join "`n") }
else           { Ok  'readiness: an unlisted archive is reported as launching-will-not-fix' }

# Now the other side: scripts newer than the bundle, which IS fixed by launching.
# The .reds file is deliberately given an OLD timestamp, the way a hardlinked
# deploy leaves it, while the folder carries the deploy time.
$bundlePath = Join-Path $rdyGame 'r6\cache\modded\final.redscripts.modded'
Set-Content -LiteralPath $bundlePath 'bundle' -NoNewline
$builtAt = (Get-Date).AddDays(-2)
(Get-Item -LiteralPath $bundlePath).LastWriteTime = $builtAt
$ns = [uint64]([DateTimeOffset]$builtAt).ToUnixTimeMilliseconds() * 1000000
$tsBytes = New-Object byte[] 16
[Array]::Copy([BitConverter]::GetBytes($ns), $tsBytes, 8)
[IO.File]::WriteAllBytes([IO.Path]::ChangeExtension($bundlePath, '.ts'), $tsBytes)

$log = Join-Path $rdyGame 'r6\logs\redscript_rCURRENT.log'
Set-Content -LiteralPath $log -NoNewline -Value @"
[INFO - $($builtAt.ToString('ddd, dd MMM yyyy HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)) -0400] Compiling files
[INFO - x] Compilation complete
[INFO - x] Output successfully saved to $bundlePath
"@

$modFolder = Join-Path $rdyGame 'r6\scripts\FreshMod'
New-Item -ItemType Directory -Path $modFolder -Force | Out-Null
$redsFile = Join-Path $modFolder 'mod.reds'
Set-Content -LiteralPath $redsFile 'public class Fresh {}' -NoNewline
(Get-Item -LiteralPath $redsFile).LastWriteTime = (Get-Date).AddYears(-3)   # author's date
(Get-Item -LiteralPath $modFolder).LastWriteTime = (Get-Date)               # deploy time

$rdy2 = Get-AllOutput { & $readyTool -GameRoot $rdyGame }
$scriptProblems = @(
    if ($rdy2 -notmatch 'FIXED BY LAUNCHING') { 'a mod deployed after the bundle was not reported as fixed by launching' }
    if ($rdy2 -notmatch 'FreshMod')           { 'the mod was not named - the hardlink timestamp trap' }
)
if ($scriptProblems) { Bad 'readiness: a mod deployed after the bundle is fixed by launching' ($scriptProblems -join "`n") }
else                 { Ok  'readiness: a mod deployed after the bundle is fixed by launching' }

# A failed compile is the highest-value finding in the tool: every .reds mod is
# off, with no sign in game. It must never be filed as self-healing.
Set-Content -LiteralPath $log -NoNewline -Value @"
[INFO - $($builtAt.ToString('ddd, dd MMM yyyy HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)) -0400] Compiling files
[ERROR - x] something went wrong
[INFO - x] Output successfully saved to $bundlePath
"@
$rdy3 = Get-AllOutput { & $readyTool -GameRoot $rdyGame }
if ($rdy3 -match 'EVERY \.reds mod is off') { Ok 'readiness: a failed compile is called out as install-wide' }
else { Bad 'readiness: a failed compile is called out as install-wide' "a compile with no 'Compilation complete' was not escalated:`n$rdy3" }

# ============================================================= collection ====
#
# Comparing an install against a curated collection is only useful if the two
# sides are matched correctly, and the way that fails is silent: a hashtable
# keyed by Int32 and probed with an Int64 - which is what a modId out of JSON
# becomes - matches nothing and reports a perfect ZERO overlap. That reads as a
# finding ("you share none of this list") rather than as the bug it is. It
# happened while writing this tool by hand, and the number was believable.
#
# THE NO-NETWORK RULE APPLIES HERE TOO, which is why the tool takes -FromJson: a
# suite that calls Nexus to test a comparison is not a test suite.

$collTool = Join-Path $Root 'skills\cyberwise-reports\tools\Compare-Collection.ps1'
$collStage = Join-Path $sandbox 'collstaging'
New-Item -ItemType Directory -Path $collStage -Force | Out-Null

# Two of these are Vortex-shaped and carry an id; the third is MO2-shaped and
# carries none, which is the case that makes a comparison unreliable.
foreach ($f in 'Shared Mod-111-1-0-1700000000', 'Other Mod-222-2-1-1700000000', 'HandUnzippedMod') {
    New-Item -ItemType Directory -Path (Join-Path $collStage $f) -Force | Out-Null
}

# A payload shaped exactly like the API's, with modId as a NUMBER - the type
# that broke the first hand-rolled comparison.
$payload = @{
    name = 'Fixture Collection'; summary = 'A stated scope'; revision = 3
    revision_data = @{
        modCount = 3; totalSize = 1073741824
        modFiles = @(
            @{ optional = $false; file = @{ mod = @{ modId = 111; name = 'Shared Mod'; summary = 'already installed'; author = 'a'; category = 'Gameplay'; adult = $false } } }
            @{ optional = $false; file = @{ mod = @{ modId = 999; name = 'Crash Fix For Something'; summary = 'prevents a crash'; author = 'b'; category = 'Utilities'; adult = $false } } }
            @{ optional = $false; file = @{ mod = @{ modId = 998; name = 'Shiny New Outfit'; summary = 'adds an outfit'; author = 'c'; category = 'Appearance'; adult = $false } } }
            # The same mod twice, as a collection genuinely lists it: one file
            # entry for the main download and one for a patch. Counting rows as
            # mods overstates the list.
            @{ optional = $false; file = @{ mod = @{ modId = 999; name = 'Crash Fix For Something'; summary = 'prevents a crash'; author = 'b'; category = 'Utilities'; adult = $false } } }
        )
    }
}
$payloadPath = Join-Path $sandbox 'collection.json'
$payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $payloadPath -Encoding UTF8

$collOut = Get-AllOutput { & $collTool -Slug fixture -FromJson $payloadPath -StagingRoot $collStage -Focus all }

$problems = @(
    if ($collOut -notmatch 'shared with you\s*:\s*1')  { 'the mod present in both was not matched - the Int32/Int64 key trap' }
    if ($collOut -notmatch 'missing from you\s*:\s*2') { 'the two absent mods were not both reported missing' }
    if ($collOut -notmatch '3 distinct mods across 4 file entries') { 'file entries were counted as distinct mods' }
    if ($collOut -notmatch 'Crash Fix For Something')  { 'a missing mod was not named' }
)
if ($problems) { Bad 'collection: an install is matched against a collection by mod id' ($problems -join "`n") }
else           { Ok  'collection: an install is matched against a collection by mod id' }

# The whole reason to run it: surface the FIXES, which are named after the bug
# rather than the feature and are the entries nobody finds by browsing.
$focusOut = Get-AllOutput { & $collTool -Slug fixture -FromJson $payloadPath -StagingRoot $collStage -Focus stability }
$focusProblems = @(
    if ($focusOut -notmatch 'Crash Fix For Something') { 'the stability filter dropped a crash fix' }
    if ($focusOut -match 'Shiny New Outfit')           { 'the stability filter kept a cosmetic mod' }
)
if ($focusProblems) { Bad 'collection: the stability focus keeps fixes and drops features' ($focusProblems -join "`n") }
else                { Ok  'collection: the stability focus keeps fixes and drops features' }

# An install whose folders carry no Nexus id cannot be compared, and saying
# nothing is missing would be the wrong answer rather than a quiet one.
$blindStage = Join-Path $sandbox 'blindstaging'
New-Item -ItemType Directory -Path (Join-Path $blindStage 'JustAFolder') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $blindStage 'AnotherFolder') -Force | Out-Null
$blindOut = Get-AllOutput { & $collTool -Slug fixture -FromJson $payloadPath -StagingRoot $blindStage -Focus all }
if ($blindOut -match 'WARNING: fewer than half') { Ok 'collection: an install with no ids warns instead of reporting everything missing' }
else { Bad 'collection: an install with no ids warns instead of reporting everything missing' "no warning for a staging root with no Nexus ids:`n$blindOut" }

# -FromJson must make no network call at all - that is what makes it testable,
# and a fallback that reached for a key anyway would defeat it.
if ($collOut -notmatch 'No Nexus API key') { Ok 'collection: -FromJson needs no API key' }
else { Bad 'collection: -FromJson needs no API key' 'it demanded a key despite being handed a payload' }

# ============================================================== collisions ====
#
# The collision scan is the most consequential thing in this repo - it decides
# whether a mod is reported as doing nothing - and until now it had NO test,
# because the fixtures write stub .archive files that are not RDAR and the
# reader correctly refuses them. So the scan was only ever exercised against one
# real install, where you cannot construct the case you want to check.
#
# A minimal RDAR writer fixes that. The index is the only part the reader looks
# at: file bodies are Oodle-compressed and irrelevant, so a valid header plus an
# index of 56-byte entries whose first 8 bytes are the name hash is a complete
# fixture.

function New-FixtureArchive {
    param([string] $Path, [UInt64[]] $Hashes)

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([Text.Encoding]::ASCII.GetBytes('RDAR'))   # magic
    $bw.Write([uint32]12)                                # version
    # The header is 4+4+8+4 = 20 bytes, so the index starts at 20. An earlier
    # draft said 24, which made the reader seek four bytes into the index and
    # take the entry count from the wrong field - a fixture that parses as
    # garbage rather than failing.
    $bw.Write([uint64]20)                                # indexPosition
    $bw.Write([uint32]0)                                 # indexSize, unread
    $bw.Write([uint32]8); $bw.Write([uint32]0); $bw.Write([uint64]0)
    $bw.Write([uint32]$Hashes.Count)
    $bw.Write([uint32]0); $bw.Write([uint32]0)
    foreach ($h in $Hashes) {
        $entry = New-Object byte[] 56
        [Array]::Copy([BitConverter]::GetBytes([uint64]$h), $entry, 8)
        $bw.Write($entry)
    }
    $bw.Flush()
    [IO.File]::WriteAllBytes($Path, $ms.ToArray())
    $bw.Dispose(); $ms.Dispose()
}

$repairTool = Join-Path $Root 'skills\cyberwise-conflicts\tools\Repair-LoadOrder.ps1'
$colGame = Join-Path $sandbox 'collisions'
$colMod  = Join-Path $colGame 'archive\pc\mod'
New-Item -ItemType Directory -Path (Join-Path $colGame 'bin\x64') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $colGame 'bin\x64\Cyberpunk2077.exe') 'stub' -NoNewline
New-Item -ItemType Directory -Path $colMod -Force | Out-Null

# winner holds 1,2,3; loser holds 2,3 and is listed AFTER it, so every file it
# carries is owned by something earlier: inert, which is the failure this whole
# scan exists to catch.
New-FixtureArchive -Path (Join-Path $colMod 'winner.archive') -Hashes @([uint64]1, [uint64]2, [uint64]3)
New-FixtureArchive -Path (Join-Path $colMod 'loser.archive')  -Hashes @([uint64]2, [uint64]3)
New-FixtureArchive -Path (Join-Path $colMod 'solo.archive')   -Hashes @([uint64]9)
Set-Content -LiteralPath (Join-Path $colMod 'modlist.txt') "winner.archive`nloser.archive`nsolo.archive`n" -NoNewline

$colOut = Get-AllOutput { & $repairTool -ModDir $colMod }
$problems = @(
    if ($colOut -notmatch 'INERT: loser\.archive')  { 'an archive whose every file is owned earlier was not reported as inert' }
    if ($colOut -match 'INERT: winner\.archive')    { 'the archive that wins its files was called inert' }
    if ($colOut -match 'INERT: solo\.archive')      { 'an archive contesting nothing was called inert' }
)
if ($problems) { Bad 'collisions: an archive owned entirely by earlier ones is inert' ($problems -join "`n") }
else           { Ok  'collisions: an archive owned entirely by earlier ones is inert' }

# REDmod archives live under mods\<name>\archives and are ordered by REDmod
# deploy, not by modlist.txt. Leaving them out was an UNSTATED boundary: a report
# saying "no unexplained inert archives" described one directory while another
# sat outside its view, and a REDmod can win or lose a file without appearing.
$rmPath = Join-Path (Join-Path (Join-Path (Join-Path $colGame 'mods') 'SomeRedmod') 'archives') 'rm.archive'
New-FixtureArchive -Path $rmPath -Hashes @([uint64]3, [uint64]77)
$rmOut = Get-AllOutput { & $repairTool -ModDir $colMod }
$rmProblems = @(
    if ($rmOut -notmatch 'claimed by BOTH')               { 'a file held by both a loose archive and a REDmod was not reported' }
    if ($rmOut -notmatch 'redmod:SomeRedmod/rm\.archive') { 'the REDmod side was not named' }
)
if ($rmProblems) { Bad 'collisions: a file contested across both domains is reported' ($rmProblems -join "`n") }
else             { Ok  'collisions: a file contested across both domains is reported' }

# ...and it must not RANK them. modlist.txt orders only the loose side, so
# declaring a winner across domains would be a guess wearing a verdict.
if ($rmOut -match 'INERT: redmod:') {
    Bad 'collisions: a cross-domain contest is not ranked as a loss' 'a REDmod archive was declared inert against a list that does not order it'
} else {
    Ok  'collisions: a cross-domain contest is not ranked as a loss'
}

$skipOut = Get-AllOutput { & $repairTool -ModDir $colMod -SkipRedmod }
if ($skipOut -notmatch 'claimed by BOTH') { Ok 'collisions: -SkipRedmod leaves REDmod archives out' }
else { Bad 'collisions: -SkipRedmod leaves REDmod archives out' 'REDmod archives were scanned anyway' }



# ======================================================= recommendations ====
#
# Two failures, opposite in shape, and this skill is the line between them:
# staying silent when someone cannot do what they asked (a prerequisite), and
# speaking when they told you not to (a recommendation). Both look like
# politeness from the inside.

$capTool  = Join-Path $Root 'skills\cyberwise-recommends\tools\Test-Capabilities.ps1'
$prefTool = Join-Path $Root 'skills\cyberwise-recommends\tools\ModPreference.ps1'

$recGame = Join-Path $sandbox 'recgame'
New-Item -ItemType Directory -Path (Join-Path $recGame 'bin\x64') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $recGame 'bin\x64\Cyberpunk2077.exe') 'stub' -NoNewline

# Nothing installed: the capability is blocked, and the DEPENDENCY is named too.
# "Install ACU" is useless advice to somebody who has no CET, and a gate that
# names only the leaf sends them in a circle.
# Assert the MISSING LIST, not the printed prose. The first version of this test
# matched the text 'Cyber Engine Tweaks' - which the human output prints from the
# ACU row's own Needs field, by a different path, whether or not the dependency
# was ever added to the list. Deleting the line that adds it left every test
# green. The mutation harness is the only reason that was ever noticed.
$bare = Get-AllOutput { & $capTool -GameRoot $recGame -For presets -Json }
$bareCode = $LASTEXITCODE
$bareJson = try { ($bare -join "`n") | ConvertFrom-Json } catch { $null }
$bareMissing = @($bareJson.Missing)
$bareProblems = @(
    if ($bareCode -eq 0)                                          { 'a capability with nothing installed reported as available' }
    if ($null -eq $bareJson)                                      { 'the -Json output did not parse' }
    if ($bareJson.Satisfied)                                      { 'an install with nothing on it reported the capability satisfied' }
    if ($bareMissing -notcontains 'Appearance Change Unlocker')   { 'the missing mod was absent from the missing list' }
    if ($bareMissing -notcontains 'Cyber Engine Tweaks')          { 'the unmet dependency was absent from the missing list' }
)
if ($bareProblems) { Bad 'recommends: a blocked capability names the whole chain' ($bareProblems -join "`n") }
else               { Ok  'recommends: a blocked capability names the whole chain' }

# Installed: exit 0, and nothing to say. A tool that always finds something to
# recommend is the thing this skill was written to avoid.
New-Item -ItemType Directory -Force -Path (Join-Path $recGame 'bin\x64\plugins\cyber_engine_tweaks\mods\AppearanceChangeUnlocker') | Out-Null
Set-Content -LiteralPath (Join-Path $recGame 'bin\x64\plugins\cyber_engine_tweaks.asi') 'stub' -NoNewline
$null = Get-AllOutput { & $capTool -GameRoot $recGame -For presets }
if ($LASTEXITCODE -eq 0) { Ok 'recommends: a satisfied capability is silent' }
else { Bad 'recommends: a satisfied capability is silent' 'an installed capability still reported as blocked' }

# THE PROBE TEST. The first version of this tool looked for Mod Settings under
# CET mods; it lives in red4ext\plugins. That single wrong path produced a false
# ABSENT on the first real install it saw - a recommendation to install something
# already installed, which is the exact annoyance the skill exists to prevent.
# So: every probe path must be one this family says mods actually live at.
$capJson = (Get-AllOutput { & $capTool -GameRoot $recGame -Json }) -join "`n"
$known = 'bin\x64\plugins', 'red4ext\plugins', 'r6\scripts', 'archive\pc\mod', 'mods\', 'r6\tweaks'
$badProbe = @()
foreach ($m in [regex]::Matches($capJson, '"([A-Za-z0-9_\\ .-]+(?:\\[A-Za-z0-9_ .-]+)+)"')) {
    $v = $m.Groups[1].Value -replace '\\', '\'
    if ($v -match '^(bin|red4ext|r6|archive|mods)\') {
        if (-not ($known | Where-Object { $v.StartsWith($_) })) { $badProbe += $v }
    }
}
if ($badProbe) { Bad 'recommends: every probe path is a real mod location' (($badProbe | Sort-Object -Unique) -join "`n") }
else           { Ok  'recommends: every probe path is a real mod location' }

# --- the preference store ---------------------------------------------------
. $prefTool
$prefRoot = Join-Path $sandbox 'recprefs'

# Default is on, and a MISSING file is not an error - the common case must not be
# the broken one.
if ((Test-RecommendAllowed -Item 'ACU' -RecordsRoot $prefRoot)) { Ok 'recommends: with no preferences file, recommending is allowed' }
else { Bad 'recommends: with no preferences file, recommending is allowed' 'a missing file blocked recommendations' }

$null = Register-Decline -Item 'ACU' -Reason 'test' -RecordsRoot $prefRoot
$declineProblems = @(
    if (Test-RecommendAllowed -Item 'ACU' -RecordsRoot $prefRoot)      { 'a declined item was still allowed' }
    if (-not (Test-RecommendAllowed -Item 'AMM' -RecordsRoot $prefRoot)) { 'declining one item silenced a different one' }
)
if ($declineProblems) { Bad 'recommends: a decline binds to one item and persists' ($declineProblems -join "`n") }
else                  { Ok  'recommends: a decline binds to one item and persists' }

# Saying no twice must not produce two entries or move the original date.
$firstOn = (Get-CwPreferences -RecordsRoot $prefRoot).declined[0].on
$null = Register-Decline -Item 'ACU' -Reason 'again' -On '2099-01-01' -RecordsRoot $prefRoot
$after = Get-CwPreferences -RecordsRoot $prefRoot
$dupProblems = @(
    if (@($after.declined | Where-Object { $_.mod -eq 'ACU' }).Count -ne 1) { 'declining twice created a duplicate entry' }
    if (($after.declined | Where-Object { $_.mod -eq 'ACU' }).on -ne $firstOn) { 'declining again moved the original date' }
)
if ($dupProblems) { Bad 'recommends: declining twice is idempotent' ($dupProblems -join "`n") }
else              { Ok  'recommends: declining twice is idempotent' }

$null = Set-RecommendMode -Mode off -RecordsRoot $prefRoot
if (-not (Test-RecommendAllowed -Item 'AMM' -RecordsRoot $prefRoot)) { Ok 'recommends: "never again" silences everything' }
else { Bad 'recommends: "never again" silences everything' 'mode off still allowed a recommendation' }

# FAIL CLOSED. A corrupt preferences file must never silently re-enable something
# the user switched off - the failure would be invisible and would look exactly
# like the tool working.
Set-Content -LiteralPath (Join-Path $prefRoot 'preferences.json') '{ this is not json' -NoNewline
$corrupt = Test-RecommendAllowed -Item 'AMM' -RecordsRoot $prefRoot -WarningAction SilentlyContinue
if (-not $corrupt) { Ok 'recommends: an unreadable preferences file fails closed' }
else { Bad 'recommends: an unreadable preferences file fails closed' 'a corrupt file re-enabled recommendations' }

# ========================================================== tool index ====
#
# The family ships 30 tools across 11 skills, and the failure that matters is
# not a broken one - it is a FORGOTTEN one. A preset decoder was proposed and
# half-designed on 2026-08-22 while `Decode-Preset.ps1` sat in the tree with the
# exact mode being asked for. A second copy of a tool splits its tests and
# whoever comes next finds whichever they find first.
#
# The index in cyberwise/SKILL.md is the fix, and this test is what keeps it
# true. A hand-kept index is right the day it is written and quietly wrong
# afterwards - worse than none, because an index gets trusted.

$indexTool = Join-Path $Root 'skills\cyberwise\tools\Get-ToolIndex.ps1'
$idxOut = Get-AllOutput { & $indexTool -Root $Root -Check }
if ($LASTEXITCODE -eq 0) { Ok 'tool index: SKILL.md lists every tool on disk' }
else { Bad 'tool index: SKILL.md lists every tool on disk' "the index has drifted:`n$idxOut" }

# The check is worthless if it cannot see a tool arriving. Plant one, confirm it
# is reported missing by NAME, and take it away again.
$plantDir = Join-Path $Root 'skills\cyberwise-hotkeys\tools'
$plant    = Join-Path $plantDir 'Test-PlantedTool.ps1'
Set-Content -LiteralPath $plant -Value '# Test-PlantedTool.ps1 -- a tool planted by the test suite.' -NoNewline
try {
    $plantOut = Get-AllOutput { & $indexTool -Root $Root -Check }
    $plantProblems = @(
        if ($LASTEXITCODE -eq 0)                              { 'a new tool absent from the index did not fail the check' }
        if ($plantOut -notmatch 'Test-PlantedTool\.ps1')      { 'the drifting tool was not named in the output' }
    )
    if ($plantProblems) { Bad 'tool index: a tool missing from the index is named' ($plantProblems -join "`n") }
    else                { Ok  'tool index: a tool missing from the index is named' }
} finally {
    Remove-Item -LiteralPath $plant -Force -ErrorAction SilentlyContinue
}

# Every tool must SAY what it is for in its opening lines, or the index carries a
# row that tells the reader nothing and the whole table stops being worth reading.
$noPurpose = @()
foreach ($t in (Get-ChildItem (Join-Path $Root 'skills') -Recurse -Filter *.ps1 -File |
                Where-Object { $_.Directory.Name -eq 'tools' })) {
    $head = (Get-Content -LiteralPath $t.FullName -TotalCount 12) -join "`n"
    if ($head -notmatch '(?m)^\s*\.SYNOPSIS\s*$' -and $head -notmatch '(?m)^#\s*[\w.-]+\.ps1\s+--\s+\S') {
        $noPurpose += $t.Name
    }
}
if ($noPurpose) { Bad 'tool index: every tool states its purpose in its header' ($noPurpose -join ', ') }
else            { Ok  'tool index: every tool states its purpose in its header' }

# ==================================================== wildcard precedence ====
#
# A precedence rule names an archive exactly, which breaks for every mod that
# renames its archive when you switch variant - a skin tone, a hair colour. The
# rule stops applying, and it does so SILENTLY: nothing errors, the new archive
# is merely unlisted, and unlisted sorts LAST. A skin texture that must beat a
# catch-all AIO ends up losing to it, and the only symptom is that the character
# looks wrong.

$wcGame = Join-Path $sandbox 'wildcards'
$wcMod  = Join-Path $wcGame 'archive\pc\mod'
New-Item -ItemType Directory -Path $wcMod -Force | Out-Null
$wcRules = Join-Path $wcGame 'rules.psd1'

function Reset-WcFixture {
    param([string] $ToneArchive)
    Get-ChildItem $wcMod -File | Remove-Item -Force
    New-FixtureArchive -Path (Join-Path $wcMod $ToneArchive) -Hashes @([uint64]1)
    New-FixtureArchive -Path (Join-Path $wcMod 'aio.archive') -Hashes @([uint64]2)
    # Only the AIO is listed: this is the state a variant swap leaves behind.
    Set-Content -LiteralPath (Join-Path $wcMod 'modlist.txt') "aio.archive`n" -NoNewline
}
function Get-WcList { @(Get-Content (Join-Path $wcMod 'modlist.txt') | Where-Object { $_ }) }

Set-Content -LiteralPath $wcRules @'
@{ Rules = @(
    @{ Before = 'skin_BODY_*.archive'
       After  = 'aio.archive'
       Why    = 'whichever tone is installed still beats the catch-all' }
) }
'@

# The rule never names FAIR or VANILLA. If it only works for the tone someone
# typed into the rules file, it has not solved anything.
$wcFails = @()
foreach ($tone in 'skin_BODY_FAIR.archive', 'skin_BODY_VANILLA.archive') {
    Reset-WcFixture -ToneArchive $tone
    $null = Get-AllOutput { & $repairTool -ModDir $wcMod -RulesFile $wcRules -Fix -SkipScan }
    $l = Get-WcList
    $iTone = [array]::IndexOf($l, $tone); $iAio = [array]::IndexOf($l, 'aio.archive')
    if ($iTone -lt 0)       { $wcFails += "$tone was never listed at all" }
    elseif ($iTone -gt $iAio) { $wcFails += "$tone landed at $iTone, after the AIO at $iAio" }
}
if ($wcFails) { Bad 'wildcards: a pattern rule positions whichever variant is installed' ($wcFails -join "`n") }
else          { Ok  'wildcards: a pattern rule positions whichever variant is installed' }

# A pattern matching nothing is the normal case for a mod you have not installed.
# It must report and move on - not throw, and not invent an entry for a name that
# is a pattern rather than a file.
Reset-WcFixture -ToneArchive 'skin_BODY_FAIR.archive'
Set-Content -LiteralPath $wcRules @'
@{ Rules = @(
    @{ Before = 'nothing_matches_*.archive'; After = 'aio.archive'; Why = 'absent mod' }
) }
'@
$wcMiss = Get-AllOutput { & $repairTool -ModDir $wcMod -RulesFile $wcRules -Fix -SkipScan }
$missProblems = @(
    if ($wcMiss -notmatch 'pattern matched nothing') { 'an unmatched pattern was not reported as skipped' }
    if ((Get-WcList) -contains 'nothing_matches_*.archive') { 'the pattern itself was inserted into modlist.txt as if it were an archive' }
)
if ($missProblems) { Bad 'wildcards: a pattern matching nothing is skipped, not inserted' ($missProblems -join "`n") }
else               { Ok  'wildcards: a pattern matching nothing is skipped, not inserted' }

# `*` on both sides pairs every archive with every other one. That is a typo, and
# obeying it would reorder the entire load order into an arbitrary shape - the
# single most destructive thing this tool could do while reporting success.
Get-ChildItem $wcMod -File | Remove-Item -Force
$wcMany = 1..20 | ForEach-Object { "many_$_.archive" }
foreach ($n in $wcMany) { New-FixtureArchive -Path (Join-Path $wcMod $n) -Hashes @([uint64]1) }
Set-Content -LiteralPath (Join-Path $wcMod 'modlist.txt') (($wcMany -join "`n") + "`n") -NoNewline
$wcBefore = Get-WcList
Set-Content -LiteralPath $wcRules @'
@{ Rules = @(
    @{ Before = '*.archive'; After = '*.archive'; Why = 'a typo, not an intention' }
) }
'@
$wcBroad = Get-AllOutput { & $repairTool -ModDir $wcMod -RulesFile $wcRules -Fix -SkipScan }
$broadProblems = @(
    if ($wcBroad -notmatch 'pattern too broad') { 'an all-pairs pattern was not refused' }
    if (((Get-WcList) -join '|') -ne ($wcBefore -join '|')) { 'the load order was reordered by an all-pairs pattern' }
)
if ($broadProblems) { Bad 'wildcards: an over-broad pattern is refused, not obeyed' ($broadProblems -join "`n") }
else                { Ok  'wildcards: an over-broad pattern is refused, not obeyed' }

# ========================================================= resource paths ====
#
# The table turns archive hashes into file names, which is the difference between
# "3 of 16 files lost" and naming the skin material template. Two ways it can be
# wrong, and both are silent: it can resolve the WRONG path (a reader bug in the
# binary search or the front-coded decode), or it can quietly resolve nothing at
# all and leave every report back where it started.

$resolver = Join-Path $Root 'skills\cyberwise-conflicts\tools\Resolve-ResourcePath.ps1'
$cwpx     = Join-Path $Root 'skills\cyberwise-conflicts\data\resource-paths-2.31.cwpx'

if (-not (Test-Path -LiteralPath $cwpx)) {
    Skip 'resource paths: hashes resolve to names' 'the vendored table is not in this checkout'
} else {
    . $resolver

    # FNV-1a is defined on WRAPPING 64-bit arithmetic, and PowerShell does not
    # wrap - `[uint64] * [uint64]` promotes to double and then fails the cast.
    # The first version produced 0xCBF29CE484222337 for every input, which is the
    # offset basis XORed once: a constant, and a plausible-looking one.
    $knownPath = 'base\worlds\03_night_city\_compiled\default\exterior_-14_-18_1_1.streamingsector'
    $h = Get-ResourceHash $knownPath
    # [Convert]::ToUInt64(..,16), NOT a 0x literal. PowerShell parses a hex
    # literal with the high bit set as a NEGATIVE Int64, so `[uint64]0x8000...`
    # throws at runtime - and this assertion silently vanished from the suite
    # rather than failing, because a thrown statement prints to stderr and skips
    # both branches. Half of all 64-bit hashes have that bit set.
    $expect = [Convert]::ToUInt64('800008F5BA040F7E', 16)
    if ($h -eq $expect) { Ok 'resource paths: FNV-1a wraps at 64 bits' }
    else { Bad 'resource paths: FNV-1a wraps at 64 bits' ("hashed to 0x{0:X16}, expected 0x800008F5BA040F7E" -f $h) }

    if ((Resolve-ResourceHash -Hash $h) -eq $knownPath) { Ok 'resource paths: a known hash resolves to its path' }
    else { Bad 'resource paths: a known hash resolves to its path' "got '$(Resolve-ResourceHash -Hash $h)'" }

    # Block boundaries. Paths are front-coded in blocks, so each entry is
    # rebuilt from the one before it - an off-by-one in the walk returns a
    # NEIGHBOURING path, which is the worst kind of wrong because it looks
    # entirely reasonable in a conflict report.
    $edges = @{
        'base\characters\common\skin\face\microdetail_n.xbm' = $null
        'base\materials\skin.mt'                             = $null
        'engine\materials\defaults\default.sp'               = $null
    }
    $wrong = @()
    foreach ($p in @($edges.Keys)) {
        $got = Resolve-ResourceHash -Hash (Get-ResourceHash $p)
        if ($got -ne $p) { $wrong += "$p -> '$got'" }
    }
    if ($wrong) { Bad 'resource paths: several real paths round-trip exactly' ($wrong -join "`n") }
    else        { Ok  'resource paths: several real paths round-trip exactly' }

    # The reverse direction, which is what makes quest work possible: you know
    # the shape of what you want and need the hashes to hunt for inside mod
    # archives. A pattern that silently matches nothing reads exactly like a
    # quest no mod touches - the same wrong answer, from the opposite direction.
    $found = Find-ResourcePath -Like '*\sq026\*.questphase'
    $findProblems = @(
        if (-not $found -or $found.Count -lt 5) { "pattern search returned $($found.Count) matches for a quest known to have dozens" }
        if ($found | Where-Object { $_.Path -notlike '*sq026*' }) { 'a match does not contain the pattern' }
    )
    # Every hash it hands back must resolve to the path it came with, or the
    # archive scan downstream hunts for hashes of nothing.
    $sample = @($found | Select-Object -First 5)
    foreach ($f in $sample) {
        if ((Resolve-ResourceHash -Hash $f.Hash) -ne $f.Path) { $findProblems += "hash for $($f.Path) does not resolve back" }
    }
    if ($findProblems) { Bad 'resource paths: a wildcard search finds paths and usable hashes' ($findProblems -join "`n") }
    else               { Ok  'resource paths: a wildcard search finds paths and usable hashes' }

    # A miss must be $null, never a nearby path. The table covers the BASE GAME,
    # so a mod's own resource legitimately misses - and a reader that returned
    # its binary-search neighbour would name an innocent file in every report.
    $miss = Resolve-ResourceHash -Hash ([uint64]0x0123456789ABCDEF)
    if ($null -eq $miss) { Ok 'resource paths: an unknown hash returns nothing, not a neighbour' }
    else { Bad 'resource paths: an unknown hash returns nothing, not a neighbour' "invented '$miss'" }
}

# ================================================================= bisect ====
#
# A bisect round is twenty repetitions of "move this set, record it, put it
# back". The failure that costs the most is not a crash - it is a round that
# parked less than it claimed, because a configuration nobody recorded still
# produces a result, and a clean one is indistinguishable from a real one.
#
# -Launch is deliberately not exercised. Starting a game is not something a test
# suite should do to somebody's machine.

$bisectTool = Join-Path $Root 'skills\cyberwise-crashes\tools\Invoke-BisectRound.ps1'

# The tool refuses to move mod files while Cyberpunk is running, and it is right
# to. But that refusal is about the REAL install, not this sandbox, and it THROWS
# rather than returning - so an open game window kills the rest of the suite.
#
# Under the mutation harness that surfaced as "the restore did not put the tree
# back" on every mutation from here on: a message accusing the harness of leaving
# a mutated file behind, when the only thing wrong was that someone was playing.
# An environmental stop must say it is environmental.
$bisectBlocked = @(Get-Process -Name 'Cyberpunk2077' -ErrorAction SilentlyContinue).Count -gt 0
if ($bisectBlocked) {
    foreach ($n in 'a round parks exactly the named set, and records it',
                   'an unresolvable name refuses the whole round',
                   'restore puts the round back from its manifest',
                   '-Plan reports without touching anything',
                   'a round the manager undid is reported as void',
                   'a name cannot escape the game directory',
                   'a doctored manifest cannot write outside the game directory',
                   'a parked file that vanished is reported, not skipped') {
        Skip "bisect: $n" 'Cyberpunk 2077 is running - the tool refuses to move mod files, correctly'
    }
} else {
$bgame = Join-Path $sandbox 'bisectgame'
$brecs = Join-Path $sandbox 'bisectrecords'
New-Item -ItemType Directory -Path (Join-Path $bgame 'bin\x64') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $bgame 'bin\x64\Cyberpunk2077.exe') 'stub' -NoNewline
New-Item -ItemType Directory -Path (Join-Path $bgame 'archive\pc\mod') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $bgame 'r6\scripts\ScriptMod') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $bgame 'archive\pc\mod\alpha.archive') 'a' -NoNewline
Set-Content -LiteralPath (Join-Path $bgame 'archive\pc\mod\beta.archive')  'b' -NoNewline
Set-Content -LiteralPath (Join-Path $bgame 'r6\scripts\ScriptMod\x.reds')  'x' -NoNewline

# Names as a human types them: a bare archive name and a script folder. Demanding
# full relative paths turns every round into transcription work.
$cutFile = Join-Path $sandbox 'cut1.txt'
Set-Content -LiteralPath $cutFile "alpha`nScriptMod`n"

$bOut = Get-AllOutput { & $bisectTool -GameRoot $bgame -Round 'A' -Park $cutFile -RecordDir $brecs }
$parkedA = Join-Path $bgame '_bisect_parked\A'
$problems = @(
    if (Test-Path -LiteralPath (Join-Path $bgame 'archive\pc\mod\alpha.archive')) { 'alpha.archive was not parked' }
    if (Test-Path -LiteralPath (Join-Path $bgame 'r6\scripts\ScriptMod'))          { 'the script folder was not parked' }
    if (-not (Test-Path -LiteralPath (Join-Path $bgame 'archive\pc\mod\beta.archive'))) { 'it parked something that was not on the list' }
    if (-not (Test-Path -LiteralPath (Join-Path $parkedA 'archive\pc\mod\alpha.archive'))) { 'the parked archive is not under the round folder' }
    if (-not (Test-Path -LiteralPath (Join-Path $brecs 'A.json')))                 { 'no manifest was written for the round' }
)
if ($problems) { Bad 'bisect: a round parks exactly the named set, and records it' ($problems -join "`n") }
else           { Ok  'bisect: a round parks exactly the named set, and records it' }

# The one that matters most. A name that resolves to nothing must stop the round
# rather than quietly park a subset.
$bBad = Get-AllOutput { & $bisectTool -GameRoot $bgame -Round 'B' -Park @('beta', 'does-not-exist') -RecordDir $brecs }
$partial = @(
    if (-not (Test-Path -LiteralPath (Join-Path $bgame 'archive\pc\mod\beta.archive'))) { 'it parked the resolvable half of a bad list' }
    if (Test-Path -LiteralPath (Join-Path $brecs 'B.json'))                             { 'it recorded a round it refused to arm' }
    if ($bBad -notmatch 'do not resolve')                                               { 'it did not say which names were unresolvable' }
)
if ($partial) { Bad 'bisect: an unresolvable name refuses the whole round' ($partial -join "`n") }
else          { Ok  'bisect: an unresolvable name refuses the whole round' }

& $bisectTool -GameRoot $bgame -Round 'A' -Restore -RecordDir $brecs *>$null
$restored = @(
    if (-not (Test-Path -LiteralPath (Join-Path $bgame 'archive\pc\mod\alpha.archive'))) { 'the archive did not come back' }
    if (-not (Test-Path -LiteralPath (Join-Path $bgame 'r6\scripts\ScriptMod\x.reds')))  { 'the script folder did not come back' }
)
if ($restored) { Bad 'bisect: restore puts the round back from its manifest' ($restored -join "`n") }
else           { Ok  'bisect: restore puts the round back from its manifest' }

# -Plan has to answer the same question as arming, without touching anything. A
# dry run that moves files is not a dry run, and one that hides a bad name is
# worse than none - the point is to find the bad name before the round.
$planOut = Get-AllOutput { & $bisectTool -GameRoot $bgame -Round 'P' -Park @('beta', 'not-a-mod') -Plan -RecordDir $brecs }
$planProblems = @(
    if ($planOut -notmatch 'would park')                                                { 'it did not say what would move' }
    if ($planOut -notmatch 'NO MATCH')                                                  { 'it did not name the unresolvable entry' }
    if (-not (Test-Path -LiteralPath (Join-Path $bgame 'archive\pc\mod\beta.archive'))) { 'the plan moved a file' }
    if (Test-Path -LiteralPath (Join-Path $brecs 'P.json'))                             { 'the plan wrote a manifest' }
)
if ($planProblems) { Bad 'bisect: -Plan reports without touching anything' ($planProblems -join "`n") }
else               { Ok  'bisect: -Plan reports without touching anything' }

# A round is armed while the manager still believes the mods are deployed, so any
# deployment silently puts them all back. That round then scores as a result on a
# configuration nobody recorded - the exact false answer this whole file is
# organised around.
Set-Content -LiteralPath (Join-Path $sandbox 'cut-undo.txt') "beta`n"
& $bisectTool -GameRoot $bgame -Round 'D' -Park (Join-Path $sandbox 'cut-undo.txt') -RecordDir $brecs *>$null
Set-Content -LiteralPath (Join-Path $bgame 'archive\pc\mod\beta.archive') 'redeployed' -NoNewline
$statusOut = Get-AllOutput { & $bisectTool -GameRoot $bgame -Status -RecordDir $brecs }
if ($statusOut -match 'back in the game directory') { Ok 'bisect: a round the manager undid is reported as void' }
else { Bad 'bisect: a round the manager undid is reported as void' "status did not notice a parked file had reappeared:`n$statusOut" }
& $bisectTool -GameRoot $bgame -Round 'D' -Restore -RecordDir $brecs *>$null

# SECURITY: a name in a cut list must not be able to leave the game directory.
# `..\..\Documents\x` resolves perfectly well - just not where anyone intended -
# and before containment existed this MOVED a file with nothing to do with the
# game into the park folder, reported success, and wrote it into a manifest.
# A cut list is exactly the kind of thing that arrives pasted from a forum or
# generated by an agent reading untrusted text.
$escapeVault = Join-Path $sandbox 'outside-the-game'
New-Item -ItemType Directory -Path $escapeVault -Force | Out-Null
$precious = Join-Path $escapeVault 'precious.txt'
Set-Content -LiteralPath $precious 'do not move me' -NoNewline
Set-Content -LiteralPath (Join-Path $sandbox 'cut-escape.txt') "..\outside-the-game\precious.txt"

$escOut = Get-AllOutput { & $bisectTool -GameRoot $bgame -Round 'ESC' -Park (Join-Path $sandbox 'cut-escape.txt') -RecordDir $brecs }
$escProblems = @(
    if (-not (Test-Path -LiteralPath $precious))        { 'a file outside the game directory was moved' }
    if ($escOut -notmatch 'outside the game directory') { 'it did not say why the name was refused' }
    if (Test-Path -LiteralPath (Join-Path $brecs 'ESC.json')) { 'it recorded a round built from an escaping name' }
)
if ($escProblems) { Bad 'bisect: a name cannot escape the game directory' ($escProblems -join "`n") }
else              { Ok  'bisect: a name cannot escape the game directory' }

# The manifest is a file like any other, so restore has to check too - otherwise
# a doctored one writes wherever it likes.
$forged = Join-Path $brecs 'FORGED.json'
[pscustomobject]@{
    Round = 'FORGED'; ParkedAt = '2026-01-01 00:00'; GameRoot = $bgame
    ParkDir = (Join-Path $bgame '_bisect_parked\FORGED')
    Items = @([pscustomobject]@{ Rel = '..\outside-the-game\planted.txt' })
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $forged -Encoding UTF8
$parkedForge = Join-Path $bgame '_bisect_parked\FORGED\..\outside-the-game\planted.txt'
New-Item -ItemType Directory -Path (Split-Path -Parent $parkedForge) -Force | Out-Null
Set-Content -LiteralPath $parkedForge 'planted' -NoNewline

$forgeOut = Get-AllOutput { & $bisectTool -GameRoot $bgame -Round 'FORGED' -Restore -RecordDir $brecs }
if (Test-Path -LiteralPath (Join-Path $escapeVault 'planted.txt')) {
    Bad 'bisect: a doctored manifest cannot write outside the game directory' 'restore wrote a file outside the game root'
} else {
    Ok  'bisect: a doctored manifest cannot write outside the game directory'
}

# A file missing from the park folder means something else moved it - a redeploy,
# a cleanup, another round - and every round since is suspect. Saying so is the
# whole value; restoring what is left and reporting success is the failure.
#
# Its own archive, not one an earlier round touched: sharing a fixture across
# rounds makes a mutation in one place cascade into unrelated failures here, and
# a noisy blast radius is how a mutation stops naming the thing it broke.
Set-Content -LiteralPath (Join-Path $bgame 'archive\pc\mod\gamma.archive') 'g' -NoNewline
Set-Content -LiteralPath (Join-Path $sandbox 'cut2.txt') "gamma`n"
& $bisectTool -GameRoot $bgame -Round 'C' -Park (Join-Path $sandbox 'cut2.txt') -RecordDir $brecs *>$null
Remove-Item -LiteralPath (Join-Path $bgame '_bisect_parked\C\archive\pc\mod\gamma.archive') -Force
$bLost = Get-AllOutput { & $bisectTool -GameRoot $bgame -Round 'C' -Restore -RecordDir $brecs }
if ($bLost -match 'NOT in the park folder') { Ok 'bisect: a parked file that vanished is reported, not skipped' }
else { Bad 'bisect: a parked file that vanished is reported, not skipped' "restore said nothing about the missing file:`n$bLost" }
}

# ================================================================ dossier ====
#
# One mod, every layer. The failure mode this guards is a report that says a mod
# ships things it does not: a dossier is read as an inventory, and an invented
# layer sends somebody looking for a file that was never there.

$dossierTool = Join-Path $Root 'skills\cyberwise-reports\tools\New-ModDossier.ps1'
$dgame  = Join-Path $sandbox 'dossiergame'
$dstage = Join-Path $sandbox 'dossierstaging'
New-Item -ItemType Directory -Path (Join-Path $dgame 'bin\x64') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $dgame 'bin\x64\Cyberpunk2077.exe') 'stub' -NoNewline
New-Item -ItemType Directory -Path (Join-Path $dgame 'archive\pc\mod') -Force | Out-Null

# One staged mod: an archive and a CET folder with no init.lua. Note what it does
# NOT ship - no tweaks, no scripts, no input xml - because that is the assertion.
$dmod = Join-Path $dstage 'Spaced Name-4242-1-0-1700000000'
foreach ($rel in 'archive\pc\mod\fixture.archive', 'bin\x64\plugins\cyber_engine_tweaks\mods\fixture\readme.txt') {
    $p = Join-Path $dmod $rel
    New-Item -ItemType Directory -Path (Split-Path $p) -Force | Out-Null
    Set-Content -LiteralPath $p 'x' -NoNewline
}
# Deployed, but never added to modlist.txt - the silent bottom-of-the-stack case.
Set-Content -LiteralPath (Join-Path $dgame 'archive\pc\mod\fixture.archive') 'x' -NoNewline
Set-Content -LiteralPath (Join-Path $dgame 'archive\pc\mod\modlist.txt') "someone_else.archive`n" -NoNewline

$dHtml = Join-Path $sandbox 'dossier.html'
# Typed without the space, the way a mod page writes it.
$dOut = Get-AllOutput { & $dossierTool -Mod 'SpacedName' -GameRoot $dgame -StagingRoot $dstage -Html $dHtml }

$problems = @(
    if ($dOut -notmatch 'Spaced Name')  { 'punctuation-insensitive matching failed - "SpacedName" did not find "Spaced Name"' }
    if ($dOut -notmatch 'not in modlist\.txt') { 'an archive missing from modlist.txt was not reported as losing every contest' }
    if ($dOut -notmatch 'no init\.lua')  { 'a CET folder with no init.lua was not reported as doing nothing' }
    # The bug this exists for: $layers[$missing] is $null, and @($null) has ONE
    # element, so every absent layer reported "1 of 1 file(s) deployed" - because
    # Join-Path with a null tail resolves to the game root, which exists.
    foreach ($absent in 'tweakxl', 'redscript', 'input', 'asi', 'red4ext', 'redmod') {
        if ($dOut -match "(?m)^\s+$absent\s") { "reported a '$absent' layer for a mod that ships none" }
    }
)
if ($problems) { Bad 'dossier: it reports the layers a mod ships, and no others' ($problems -join "`n") }
else           { Ok  'dossier: it reports the layers a mod ships, and no others' }

# Every HTML report here has a markdown twin. For the dossier the markdown is
# the MORE exposed of the two - it is what gets pasted into a help thread - so
# the redaction has to hold on that side as well.
$dMd = Join-Path $sandbox 'dossier.md'
$null = Get-AllOutput { & $dossierTool -Mod 'SpacedName' -GameRoot $dgame -StagingRoot $dstage -Html $dHtml -Md $dMd }
$dMdText = Get-Content -LiteralPath $dMd -Raw
$dMdBad = @(
    if ($dMdText -notmatch '(?m)^# Spaced Name') { 'the markdown does not name the mod' }
    if ($dMdText -notmatch '(?m)^\| Layer \| State \| Detail \|') { 'the markdown has no layer table' }
    if ($dMdText -notmatch 'not in modlist\.txt') { 'the markdown drops the finding the HTML reports' }
    if ($dMdText -match "(?i)\$([regex]::Escape($env:USERNAME))") { 'the Windows username is in the markdown' }
)
if ($dMdBad) { Bad 'dossier: the markdown variant carries the same facts, redacted' ($dMdBad -join "`n") }
else         { Ok  'dossier: the markdown variant carries the same facts, redacted' }

$dHtmlText = Get-Content -LiteralPath $dHtml -Raw
$dLeaks = @(
    if ($dHtmlText -match "(?i)\\$([regex]::Escape($env:USERNAME))\b") { 'the Windows username is in the dossier HTML' }
    if ($dHtmlText -notmatch 'Spaced Name')                            { 'the HTML does not name the mod' }
)
if ($dLeaks) { Bad 'dossier: the page is safe to hand to someone else' ($dLeaks -join "`n") }
else         { Ok  'dossier: the page is safe to hand to someone else' }

# ========================================================== script cache =====
#
# "The .reds file is in r6\scripts" and "that code is running" are different
# claims. The bundle is built at launch, so a mod deployed since then is
# installed, enabled, correct and doing nothing - with no sign in game.
#
# Every assertion here is a false-alarm class that this tool actually produced
# against a real install before it was fixed. Eleven mods were flagged; one was
# real. A checker that cries wolf gets switched off, so the fixtures below are
# built from the ten that were wrong.

$scTool = Join-Path $Root 'skills\cyberwise\tools\Test-ScriptsLive.ps1'
$scGame = Join-Path $sandbox 'scriptcache'
New-Item -ItemType Directory -Path (Join-Path $scGame 'bin\x64') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $scGame 'bin\x64\Cyberpunk2077.exe') 'stub' -NoNewline
New-Item -ItemType Directory -Path (Join-Path $scGame 'r6\logs') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $scGame 'r6\cache\modded') -Force | Out-Null

$scBundle = Join-Path $scGame 'r6\cache\modded\final.redscripts.modded'
$scBuilt  = (Get-Date).AddDays(-2)

# A bundle is a blob with a null-terminated ASCII symbol pool. Module-qualified
# and bare names both occur; both must resolve.
$scPool = @(
    'PlayerPuppet', 'gameObject', 'ScriptedPuppet'
    'ModAWidget', 'Fixture.ModA.ModAHelper'
    'Fixture.ModC.ModCReal'
    'Fixture.ModD.ModDCore'
) -join "`0"
[IO.File]::WriteAllBytes($scBundle, [Text.Encoding]::ASCII.GetBytes("REDS`0$scPool`0"))

# The .ts beside it: u64 nanoseconds since the Unix epoch, then 8 reserved bytes.
$ns = [uint64]([DateTimeOffset]$scBuilt).ToUnixTimeMilliseconds() * 1000000
$tsBytes = New-Object byte[] 16
[Array]::Copy([BitConverter]::GetBytes($ns), $tsBytes, 8)
[IO.File]::WriteAllBytes([IO.Path]::ChangeExtension($scBundle, '.ts'), $tsBytes)

function New-ScriptLog {
    param([string]$Name, [datetime]$When, [string]$Output, [switch]$Failed)
    $body = "[INFO - $($When.ToString('ddd, dd MMM yyyy HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)) -0400] Compiling files in x`n"
    if (-not $Failed) { $body += "[INFO - x] Compilation complete`n" }
    $body += "[INFO - x] Output successfully saved to $Output`n"
    Set-Content -LiteralPath (Join-Path $scGame "r6\logs\$Name") -Value $body -NoNewline
}

# The launch that produced the live bundle...
New-ScriptLog -Name 'redscript_r2099-01-01_00-00-00.log' -When $scBuilt -Output $scBundle
# ...and a LATER compile test, which is what rCURRENT holds. Note the archived
# log above is named for a date it does not contain: that is redscript's rotation
# scheme, and reading the filename sends you to the wrong run.
New-ScriptLog -Name 'redscript_rCURRENT.log' -When (Get-Date) -Output (Join-Path $env:TEMP 'scc_test_deadbeef\final.redscripts')

function New-ScriptMod {
    param([string]$Name, [string]$Body, [datetime]$Stamp)
    $d = Join-Path $scGame "r6\scripts\$Name"
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    $f = Join-Path $d "$Name.reds"
    Set-Content -LiteralPath $f -Value $Body -NoNewline
    (Get-Item -LiteralPath $f).LastWriteTime = $Stamp
}

# In the bundle: must not be flagged.
New-ScriptMod -Name 'ModA' -Stamp $scBuilt.AddDays(-1) -Body @'
module Fixture.ModA
public class ModAWidget {
  public func Run() -> Void {}
}
public func ModAHelper() -> Void {}
'@

# Deployed AFTER the build: the one real signal.
New-ScriptMod -Name 'ModB' -Stamp (Get-Date) -Body @'
module Fixture.ModB
public class ModBBrandNew {
  public func Run() -> Void {}
}
'@

# Documents its own API in a block comment. Parsing that as a declaration
# reported a working mod as broken.
# The documented signatures sit at COLUMN ZERO inside the comment, which is how
# mods actually write these blocks - and it is what makes comment-stripping
# load-bearing. Indenting them here would let the top-level-only parser skip them
# for the wrong reason, and the mutation that removes comment-stripping would
# then change nothing and look undetectable. The harness caught exactly that.
New-ScriptMod -Name 'ModC' -Stamp $scBuilt.AddDays(-1) -Body @'
module Fixture.ModC
/**
public func ModCDocumentedButNotReal() -> Void
public class ModCAlsoJustDocs {}
*/
public class ModCReal {}
'@

# Conditionally compiled for a mod that is not installed: correctly absent.
New-ScriptMod -Name 'ModD' -Stamp $scBuilt.AddDays(-1) -Body @'
module Fixture.ModD
public class ModDCore {}

@if(ModuleExists("SomethingNotInstalled"))
public class ModDBridge {}
'@

$scOut = Get-AllOutput { & $scTool -GameRoot $scGame }

$problems = @(
    # The "file" line is the verdict; the test path is expected to appear further
    # down, in the note explaining why the newest run was ignored.
    if ($scOut -notmatch ('(?m)^\s+file\s+' + [regex]::Escape($scBundle))) { 'the bundle it chose is not the one the launch log names' }
    if ($scOut -match '(?m)^\s+file\s+.*scc_test_deadbeef')                { 'it chose the compile test output as the live bundle' }
    if ($scOut -notmatch 'compile test')                                   { 'it never says the newest run was a test rather than a launch' }
    if ($scOut -notmatch $scBuilt.ToString('yyyy-MM-dd HH:mm'))            { 'the build time from the .ts stamp is not reported' }
)
if ($problems) { Bad 'scripts: the live bundle comes from the log, not the newest run' ($problems -join "`n") }
else           { Ok  'scripts: the live bundle comes from the log, not the newest run' }

$flagProblems = @(
    if ($scOut -notmatch 'ModB')     { 'a mod deployed after the build was not flagged - the one case that matters' }
    if ($scOut -match '(?m)^\s+ModA') { 'a mod whose symbols are in the bundle was flagged' }
    if ($scOut -match '(?m)^\s+ModC') { 'a declaration inside a block comment was treated as a real symbol' }
    if ($scOut -match '(?m)^\s+ModD') { 'an @if-gated class for an absent mod was reported as missing' }
)
if ($flagProblems) { Bad 'scripts: only a genuinely uncompiled mod is flagged' ($flagProblems -join "`n") }
else               { Ok  'scripts: only a genuinely uncompiled mod is flagged' }

# Per-mod mode has to resolve a module-qualified symbol, or every modularised mod
# reads as missing.
$scOne = Get-AllOutput { & $scTool -GameRoot $scGame -Mod 'ModA' }
if ($scOne -match 'ModAHelper\s+in the bundle') { Ok 'scripts: a module-qualified symbol resolves for a single mod' }
else { Bad 'scripts: a module-qualified symbol resolves for a single mod' "ModAHelper was not found as Fixture.ModA.ModAHelper:`n$scOne" }

# ============================================================== install ======
#
# The destructive bug this guards: an installed copy running its own uninstaller
# deleted every cyberwise* skill link BY NAME, including links belonging to a
# different copy. On a machine where someone also had the repo linked for
# development, uninstalling the app silently removed their links too. It
# happened during the first test of the installer, on a real machine.

$homeA = Join-Path $sandbox 'agentHomeA'
$copyB = Join-Path $sandbox 'otherCopy'
New-Item -ItemType Directory -Path (Join-Path $copyB 'skills\cyberwise') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $copyB 'skills\cyberwise\SKILL.md') 'placeholder' -NoNewline
Copy-Item -LiteralPath (Join-Path $Root 'install.ps1') -Destination $copyB -Force

# Link from THIS repo into a throwaway agent home...
& (Join-Path $Root 'install.ps1') -ClaudeHome $homeA -ClaudeOnly *>$null
$before = @(Get-ChildItem (Join-Path $homeA 'skills') -Directory -ErrorAction SilentlyContinue).Count

# ...then let a DIFFERENT copy run its uninstall against the same home.
& (Join-Path $copyB 'install.ps1') -ClaudeHome $homeA -ClaudeOnly -Remove *>$null
$after = @(Get-ChildItem (Join-Path $homeA 'skills') -Directory -ErrorAction SilentlyContinue).Count

if ($before -gt 0 -and $after -eq $before) {
    Ok 'install: another copy''s uninstall leaves these links alone'
} else {
    Bad 'install: another copy''s uninstall leaves these links alone' `
        "had $before links, $after remain - an unrelated uninstall deleted them"
}

# And its own uninstall must still work, or the guard is too strong.
& (Join-Path $Root 'install.ps1') -ClaudeHome $homeA -ClaudeOnly -Remove *>$null
$own = @(Get-ChildItem (Join-Path $homeA 'skills') -Directory -ErrorAction SilentlyContinue).Count
if ($own -eq 0) { Ok 'install: a copy can still remove its own links' }
else { Bad 'install: a copy can still remove its own links' "$own links left after removing with the owning copy" }

# The silent one, and it happened for real: a link pointing at ANOTHER copy was
# reported as "already linked", so re-running the installer said everything was
# fine while both agents kept loading a stale snapshot. Nine of ten skills sat
# like that for a day. A stale link and a good one are indistinguishable until
# somebody resolves the target.
$homeC = Join-Path $sandbox 'agentHomeC'
New-Item -ItemType Directory -Path (Join-Path $homeC 'skills') -Force | Out-Null
cmd /c mklink /J "$(Join-Path $homeC 'skills\cyberwise')" "$(Join-Path $copyB 'skills\cyberwise')" | Out-Null

# Get-AllOutput, not Get-Console: the mismatch is a Write-Warning, and warnings
# are stream 3. Capturing only 6>&1 2>&1 misses it and fails this on the wrong
# grounds - which it did, first run.
$stale = Get-AllOutput { & (Join-Path $Root 'install.ps1') -ClaudeHome $homeC -ClaudeOnly }
$staleTarget = [string]@((Get-Item -LiteralPath (Join-Path $homeC 'skills\cyberwise') -Force).Target)[0]
$problems = @(
    if ($stale -match 'already linked: cyberwise\b') { 'a link to another copy was reported as already linked' }
    if ($stale -notmatch 'points at another copy')   { 'nothing said the link belongs to a different copy' }
    if ($stale -notmatch '-Relink')                  { 'the report does not say how to fix it' }
    # Reporting is the whole point: repointing somebody's links unasked is not
    # this script's decision.
    if ($staleTarget -notmatch [regex]::Escape($copyB)) { 'the link was repointed without -Relink being passed' }
)
if ($problems) { Bad 'install: a link pointing at another copy is reported, not called healthy' ($problems -join "`n") }
else           { Ok  'install: a link pointing at another copy is reported, not called healthy' }

# ...and -Relink must actually move it, or the advice above is a dead end.
& (Join-Path $Root 'install.ps1') -ClaudeHome $homeC -ClaudeOnly -Relink *>$null
$relinked = [string]@((Get-Item -LiteralPath (Join-Path $homeC 'skills\cyberwise') -Force).Target)[0]
if ($relinked -eq (Join-Path $Root 'skills\cyberwise')) { Ok 'install: -Relink repoints a link at this copy' }
else { Bad 'install: -Relink repoints a link at this copy' "still points at $relinked" }

# ============================================================== watcher ======
#
# Several independent things can start a watcher - the tray, a logon Run entry,
# a scheduled task, a person at a prompt - and none knows about the others.
# "Check, then start" is a race between any two, and losing it is quiet: two
# watchers interleaving session CSVs in one folder.

if ($Quick) {
    Skip 'watcher: only one runs per output folder' '-Quick was passed'
} else {
    $watchTool = Join-Path $Root 'skills\cyberwise-crashes\tools\Watch-Crashes.ps1'
    $wdirA = Join-Path $sandbox 'watchA'
    $wdirB = Join-Path $sandbox 'watchB'

    function Start-TestWatcher {
        param([string]$D)
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList `
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$watchTool`"", '-Dir', "`"$D`""
    }
    function Count-TestWatchers {
        param([string]$Tag)
        @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
          Where-Object { $_.CommandLine -like "*$Tag*" }).Count
    }

    Start-TestWatcher $wdirA; Start-TestWatcher $wdirA
    Start-Sleep -Seconds 4
    $a = Count-TestWatchers 'watchA'
    if ($a -eq 1) { Ok 'watcher: a second launch for the same folder exits' }
    else { Bad 'watcher: a second launch for the same folder exits' "$a watchers are running against one folder" }

    # Keyed on the folder, not globally, so two game installs each get one.
    Start-TestWatcher $wdirB
    Start-Sleep -Seconds 3
    $b = Count-TestWatchers 'watchB'
    if ($b -eq 1) { Ok 'watcher: a different folder still gets its own watcher' }
    else { Bad 'watcher: a different folder still gets its own watcher' "$b watchers for the second folder" }

    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*watchA*' -or $_.CommandLine -like '*watchB*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

# ================================================================== tray =====
#
# The tray app is the only compiled thing here, and it is what a non-technical
# user actually touches. Building it in the suite catches a C# break that no
# PowerShell test would, and --selftest exercises the detection paths end to end
# without needing anyone to look at a tray menu.

$csc = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe')
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if ($Quick) {
    Skip 'tray: builds and self-reports' '-Quick was passed'
} elseif (-not $csc) {
    Skip 'tray: builds and self-reports' 'no .NET Framework C# compiler on this machine'
} else {
    $trayOut = Join-Path $sandbox 'traybin'
    $build   = Join-Path $Root 'app\build.ps1'
    $buildLog = Get-Console { & $build -OutDir $trayOut }
    $trayExe = Join-Path $trayOut 'CyberwiseTray.exe'

    if (-not (Test-Path -LiteralPath $trayExe)) {
        Bad 'tray: builds' $buildLog
    } else {
        Ok 'tray: builds'

        # Windows shows FileDescription - not the filename - in taskbar settings
        # and Task Manager. Without the version resource it reads as
        # "CyberwiseTray.exe", which looks like something that installed itself.
        $desc = (Get-Item -LiteralPath $trayExe).VersionInfo.FileDescription
        if ($desc -eq 'Cyberwise') { Ok 'tray: the exe identifies itself as Cyberwise' }
        else { Bad 'tray: the exe identifies itself as Cyberwise' "FileDescription is '$desc'" }

        # A /target:winexe does NOT block the shell - `& $exe` returns immediately
        # and its console output cannot be piped, because AttachConsole writes to
        # the console buffer rather than to a redirectable stdout that PowerShell
        # is capturing. Start-Process -Wait with an explicit redirect gets both
        # the ordering and the text.
        $stFile = Join-Path $sandbox 'selftest.txt'
        Start-Process -FilePath $trayExe -ArgumentList '--selftest' -NoNewWindow -Wait `
            -RedirectStandardOutput $stFile
        $st = if (Test-Path -LiteralPath $stFile) { Get-Content -LiteralPath $stFile -Raw } else { '' }
        $problems = @(
            if ($st -notmatch '(?m)^\s*game root\s*:')      { 'self-test does not report a game root' }
            if ($st -notmatch '(?m)^\s*watcher\s*:')        { 'self-test does not report watcher state' }
            if ($st -notmatch '(?m)^\s*start at logon\s*:') { 'self-test does not report the autostart setting' }
            if ($st -notmatch '(?m)^\s*crashes\s*:')        { 'self-test does not report a crash count' }
        )
        if ($problems) { Bad 'tray: --selftest reports the fields support needs' ($problems -join "`n") }
        else           { Ok  'tray: --selftest reports the fields support needs' }

        # A Run entry holds an absolute path, and a moved folder breaks logon
        # startup with no error anywhere. The app has to notice that itself, or
        # it is one more thing failing quietly.
        $runK = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        $probe = 'CyberwiseTestAutostart'
        try {
            Set-ItemProperty -Path $runK -Name $probe -Value '"C:\definitely\not\here\CyberwiseTray.exe"'
            $stale = Join-Path $sandbox 'stale.txt'
            Start-Process -FilePath $trayExe -ArgumentList '--selftest', '--run-value', $probe `
                -NoNewWindow -Wait -RedirectStandardOutput $stale
            $staleTxt = if (Test-Path -LiteralPath $stale) { Get-Content -LiteralPath $stale -Raw } else { '' }
            if ($staleTxt -match 'WARNING') { Ok 'tray: a stale logon path is reported, not ignored' }
            else { Bad 'tray: a stale logon path is reported, not ignored' "no warning for a missing target:`n$staleTxt" }
        } finally {
            Remove-ItemProperty -Path $runK -Name $probe -ErrorAction SilentlyContinue
        }

        # The icon cannot be judged from source, but it CAN be checked for the
        # one failure that matters mechanically: rendering nothing at all.
        $png = Join-Path $sandbox 'icon.png'
        Start-Process -FilePath $trayExe -ArgumentList '--icon-preview', "`"$png`"" -NoNewWindow -Wait
        if (-not (Test-Path -LiteralPath $png)) {
            Bad 'tray: the icon renders' 'no preview file was produced'
        } else {
            Add-Type -AssemblyName System.Drawing
            $img = [System.Drawing.Image]::FromFile($png)
            try {
                # Sample the middle of the first state swatch; a blank render
                # would leave the background colour everywhere.
                $distinct = @{}
                for ($x = 60; $x -lt 150; $x += 3) {
                    for ($y = 40; $y -lt 130; $y += 3) { $distinct[$img.GetPixel($x, $y).ToArgb()] = 1 }
                }
                if ($distinct.Count -ge 5) { Ok 'tray: the icon renders more than a flat swatch' }
                else { Bad 'tray: the icon renders more than a flat swatch' "only $($distinct.Count) distinct colours in the sampled area" }
            } finally { $img.Dispose() }
        }

        # "Copy crash summary" is there so somebody can paste it into a help
        # channel, and Discord refuses a message over 2000 characters outright.
        # A summary that runs long therefore does not arrive short - it does not
        # arrive, and the person retypes it by hand while already stuck.
        #
        # Testing this means calling the real Paste.Fit, which is why it is a
        # public class rather than a private helper. Loading a Framework 4.8
        # assembly into pwsh (which runs on .NET 8) is not reliable, so instead a
        # tiny harness is compiled TOGETHER WITH the shipped source by the same
        # csc, with /main: choosing the entry point. What runs is the code that
        # ships, not a copy of it.
        $harnessSrc = Join-Path $sandbox 'FitHarness.cs'
        Set-Content -LiteralPath $harnessSrc -Encoding UTF8 -Value @'
using System;
using System.Text;
using Cyberwise;

internal static class FitHarness
{
    private static void Main()
    {
        var sb = new StringBuilder();
        sb.AppendLine("Cyberpunk 2077 crash summary");
        for (int i = 0; i < 20; i++) sb.AppendLine("  crash " + i + " " + new string('x', 200));
        string big = Paste.Fit(sb.ToString(), Paste.DiscordLimit);

        Console.WriteLine("LEN=" + big.Length);
        Console.WriteLine("HEADER=" + (big.StartsWith("Cyberpunk 2077 crash summary") ? "kept" : "lost"));
        Console.WriteLine("NEWEST=" + (big.Contains("crash 0 ") ? "kept" : "lost"));
        Console.WriteLine("OLDEST=" + (big.Contains("crash 19 ") ? "kept" : "dropped"));
        Console.WriteLine("SAIDSO=" + (big.Contains("more line(s)") ? "yes" : "no"));

        string small = "Cyberpunk 2077 crash summary" + Environment.NewLine + "crashes recorded: 0";
        Console.WriteLine("SHORT=" + (Paste.Fit(small, Paste.DiscordLimit) == small ? "untouched" : "mangled"));

        string oneLine = new string('y', 5000);
        Console.WriteLine("ONELINE=" + Paste.Fit(oneLine, Paste.DiscordLimit).Length);
    }
}
'@
        $fitExe = Join-Path $sandbox 'FitHarness.exe'
        $traySrc = Join-Path $Root 'app\CyberwiseTray.cs'
        & $csc /nologo /target:exe /main:FitHarness /out:"$fitExe" `
            /r:System.dll /r:System.Core.dll /r:System.Drawing.dll `
            /r:System.Windows.Forms.dll /r:System.Management.dll `
            "$harnessSrc" "$traySrc" 2>&1 | Out-Null

        if (-not (Test-Path -LiteralPath $fitExe)) {
            Bad 'tray: a pasted crash summary fits a Discord message' 'the harness would not compile against the shipped source'
        } else {
            $fitFile = Join-Path $sandbox 'fit.txt'
            Start-Process -FilePath $fitExe -NoNewWindow -Wait -RedirectStandardOutput $fitFile
            $fit = @{}
            foreach ($line in (Get-Content -LiteralPath $fitFile)) {
                if ($line -match '^(\w+)=(.*)$') { $fit[$matches[1]] = $matches[2] }
            }
            $problems = @(
                if ([int]$fit['LEN'] -gt 2000)   { "a 4KB summary came back at $($fit['LEN']) characters - Discord would refuse it" }
                if ($fit['HEADER'] -ne 'kept')   { 'the header line was trimmed away, so the paste no longer says what it is' }
                if ($fit['NEWEST'] -ne 'kept')   { 'the newest crash was dropped - trimming took from the wrong end' }
                if ($fit['OLDEST'] -ne 'dropped'){ 'nothing was actually dropped, so the length above is a coincidence' }
                if ($fit['SAIDSO'] -ne 'yes')    { 'it trimmed silently, so the reader believes they pasted everything' }
                if ($fit['SHORT'] -ne 'untouched') { 'a summary that already fits was rewritten anyway' }
                if ([int]$fit['ONELINE'] -gt 2000) { "a single 5000-character line came back at $($fit['ONELINE'])" }
            )
            if ($problems) { Bad 'tray: a pasted crash summary fits a Discord message' ($problems -join "`n") }
            else           { Ok  'tray: a pasted crash summary fits a Discord message' }
        }
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

# ================================================================= credits ====
#
# The credits page is the one report built to be SHOWN to people, which changes
# what counts as a bug. Two of the three assertions below are about honesty
# rather than crashes: a headline number that flatters, and a mod list that
# repeats itself, both look like carelessness to a reader who cannot check.

$credTool = Join-Path $Root 'skills\cyberwise-reports\tools\New-ModCredits.ps1'
$cStage   = Join-Path $sandbox 'creditstaging'
New-Item -ItemType Directory -Path $cStage -Force | Out-Null

# Two staging folders, ONE Nexus id: a FOMOD installed twice with different
# options. This is the shape that made a real run print "Preem Fixes" four
# times and claim 798 mods when it had 715.
foreach ($f in 'Preem Fixes-1111-1-0-1700000000', 'Preem Fixes-1111-1-1-1700000001',
               'Second Thing-3333-2-0-1700000002', 'Naughty Bits-2222-1-0-1700000003',
               'Hand Made Thing') {
    New-Item -ItemType Directory -Path (Join-Path $cStage $f) -Force | Out-Null
}

$cCache = Join-Path $sandbox 'credit-cache.json'
Set-Content -LiteralPath $cCache -Encoding UTF8 -Value (@{
    '1111' = @{ name = 'Preem Fixes';  author = 'Alice'; adult = $false }
    '3333' = @{ name = 'Second Thing'; author = 'Alice'; adult = $false }
    '2222' = @{ name = 'Naughty Bits'; author = 'Bob';   adult = $true  }
} | ConvertTo-Json -Depth 5)

$cHtml = Join-Path $sandbox 'credits.html'
$cMd   = Join-Path $sandbox 'credits.md'
$cOut  = Get-AllOutput { & $credTool -StagingRoot $cStage -CachePath $cCache -Html $cHtml -Md $cMd }
$cHtmlText = Get-Content -LiteralPath $cHtml -Raw

# Alice has two DISTINCT mods across three folders. Count the occurrences of the
# duplicated title rather than just looking for it - "present" was true before
# the dedupe too.
$preemCount = ([regex]::Matches($cHtmlText, 'Preem Fixes')).Count
$cProblems = @(
    if ($preemCount -ne 1) { "one mod installed as two folders is listed $preemCount times, not once" }
    # Three folders, two ids, plus the un-idd folder = 3 distinct, not 4.
    if ($cHtmlText -notmatch '<b>3</b>') { 'the headline count counts staging folders, not mods' }
    if ($cOut -notmatch '(?i)798|staged folders') { 'the folder count is not reported alongside the mod count' }
)
if ($cProblems) { Bad 'credits: one mod installed twice is one credit' ($cProblems -join "`n") }
else            { Ok  'credits: one mod installed twice is one credit' }

# Adult mods are omitted by DEFAULT - this page gets shown on streams - but the
# count is printed, because silently dropping somebody from a credits list is
# its own unkindness.
$cAdult = @(
    if ($cHtmlText -match 'Naughty Bits') { 'an adult mod is on the page without -ShowAdult' }
    if ($cHtmlText -match '\bBob\b')      { 'an adult-only author is credited without -ShowAdult' }
    if ($cOut -notmatch '(?i)1 adult mod') { 'the omitted count was not printed' }
)
if ($cAdult) { Bad 'credits: adult mods are omitted by default, and the omission is stated' ($cAdult -join "`n") }
else         { Ok  'credits: adult mods are omitted by default, and the omission is stated' }

$cHtml2 = Join-Path $sandbox 'credits-adult.html'
$null = Get-AllOutput { & $credTool -StagingRoot $cStage -CachePath $cCache -Html $cHtml2 -ShowAdult }
if ((Get-Content -LiteralPath $cHtml2 -Raw) -match 'Naughty Bits') { Ok 'credits: -ShowAdult includes them' }
else { Bad 'credits: -ShowAdult includes them' 'the adult mod was still omitted' }

# Every HTML report here has a markdown twin, for a forum post or a Discord
# message where a web page is useless. It has to carry the same facts.
$cMdText = Get-Content -LiteralPath $cMd -Raw
$cMdBad = @(
    if ($cMdText -notmatch '(?m)^\*\*Alice\*\*') { 'the markdown does not credit the author' }
    if (([regex]::Matches($cMdText, 'Preem Fixes')).Count -ne 1) { 'the markdown repeats a deduplicated mod' }
    if ($cMdText -match 'Naughty Bits') { 'the markdown includes an adult mod the HTML omitted' }
)
if ($cMdBad) { Bad 'credits: the markdown variant carries the same facts' ($cMdBad -join "`n") }
else         { Ok  'credits: the markdown variant carries the same facts' }

# A staging root the cache knows nothing about. Every mod is unattributed, so
# the roll is empty - which looks exactly like a broken tool unless the page
# says which of the two it is.
$cEmptyHtml = Join-Path $sandbox 'credits-empty.html'
$null = Get-AllOutput { & $credTool -StagingRoot $cStage -CachePath (Join-Path $sandbox 'no-such-cache.json') -Html $cEmptyHtml }
$cEmptyText = Get-Content -LiteralPath $cEmptyHtml -Raw
$cEmptyBad = @(
    if ($cEmptyText -notmatch '(?i)no authors on record') { 'an empty credits roll does not say why it is empty' }
    if ($cEmptyText -notmatch 'New-ModManifest')          { 'it does not name the tool that would fill it in' }
)
if ($cEmptyBad) { Bad 'credits: an unenriched install says so instead of rendering nothing' ($cEmptyBad -join "`n") }
else            { Ok  'credits: an unenriched install says so instead of rendering nothing' }

# ================================================================ anatomy ====
#
# The anatomy report rests on one distinction: a hash the base-game table knows
# is an OVERRIDE, one it does not is a mod-authored asset. Get that backwards
# and every number on the page inverts - a content pack reads as a mod that
# rewrites half the game.
#
# It runs against a HAND-BUILT index rather than the vendored 11 MB table. Two
# reasons: the suite must pass in a checkout that has not fetched the data, and
# the mutation harness runs this file thirty times, where a 30-second table load
# becomes a quarter of an hour. It also means the CWPX1 reader is tested against
# bytes written from the format spec rather than against itself.

function New-FixtureIndex {
    param([string] $Path, [string[]] $Paths, [int] $BlockSize = 4)

    $body = New-Object System.IO.MemoryStream
    $bw   = New-Object System.IO.BinaryWriter($body)
    $blockOffsets = New-Object System.Collections.Generic.List[uint32]
    $prev = $null
    for ($i = 0; $i -lt $Paths.Count; $i++) {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Paths[$i])
        if ($i % $BlockSize -eq 0) {
            $blockOffsets.Add([uint32]$body.Position)
            $bw.Write([uint16]$bytes.Length)
            $bw.Write($bytes)
        } else {
            # Shared prefix with the previous entry, capped at 255 - the field is
            # one byte, which is the whole reason paths are stored in order.
            $shared = 0
            $max = [math]::Min([math]::Min($prev.Length, $bytes.Length), 255)
            while ($shared -lt $max -and $prev[$shared] -eq $bytes[$shared]) { $shared++ }
            $bw.Write([byte]$shared)
            $bw.Write([uint16]($bytes.Length - $shared))
            $bw.Write($bytes, $shared, $bytes.Length - $shared)
        }
        $prev = $bytes
    }
    $bw.Flush()
    $bodyBytes = $body.ToArray()

    # Hashes are stored SIGNED and sorted signed, because the upstream table came
    # out of SQLite, which has no unsigned 64-bit integer.
    $rows = @()
    for ($i = 0; $i -lt $Paths.Count; $i++) {
        $h = Get-ResourceHash $Paths[$i]
        $rows += [pscustomobject]@{ Signed = [BitConverter]::ToInt64([BitConverter]::GetBytes($h), 0); Ordinal = $i }
    }
    $rows = @($rows | Sort-Object Signed)

    $hashBytes = New-Object byte[] ($rows.Count * 12)
    for ($i = 0; $i -lt $rows.Count; $i++) {
        [Array]::Copy([BitConverter]::GetBytes([int64]$rows[$i].Signed), 0, $hashBytes, $i * 12, 8)
        [Array]::Copy([BitConverter]::GetBytes([uint32]$rows[$i].Ordinal), 0, $hashBytes, $i * 12 + 8, 4)
    }
    $blkBytes = New-Object byte[] ($blockOffsets.Count * 4)
    for ($i = 0; $i -lt $blockOffsets.Count; $i++) {
        [Array]::Copy([BitConverter]::GetBytes([uint32]$blockOffsets[$i]), 0, $blkBytes, $i * 4, 4)
    }

    $hashOff = 37
    $blkOff  = $hashOff + $hashBytes.Length
    $bodyOff = $blkOff + $blkBytes.Length

    $out = New-Object System.IO.MemoryStream
    $ow  = New-Object System.IO.BinaryWriter($out)
    $ow.Write([Text.Encoding]::ASCII.GetBytes('CWPX1'))
    $ow.Write([uint32]$Paths.Count)
    $ow.Write([uint32]$BlockSize)
    $ow.Write([uint32]$hashOff);  $ow.Write([uint32]$hashBytes.Length)
    $ow.Write([uint32]$blkOff);   $ow.Write([uint32]$blkBytes.Length)
    $ow.Write([uint32]$bodyOff);  $ow.Write([uint32]$bodyBytes.Length)
    $ow.Write($hashBytes); $ow.Write($blkBytes); $ow.Write($bodyBytes)
    $ow.Flush()

    # The vendored file is raw-deflated and the tool inflates it to a cache keyed
    # on write time. Writing it any other way would test a path nothing uses.
    $fs = [IO.File]::Create($Path)
    $ds = New-Object IO.Compression.DeflateStream($fs, [IO.Compression.CompressionMode]::Compress)
    try { $ds.Write($out.ToArray(), 0, [int]$out.Length) } finally { $ds.Dispose(); $fs.Dispose() }
}

$anatomyTool = Join-Path $Root 'skills\cyberwise-reports\tools\New-ArchiveAnatomy.ps1'
$anGame = Join-Path $sandbox 'anatomygame'
$anMod  = Join-Path $anGame 'archive\pc\mod'
New-Item -ItemType Directory -Path (Join-Path $anGame 'bin\x64') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $anGame 'bin\x64\Cyberpunk2077.exe') 'stub' -NoNewline
New-Item -ItemType Directory -Path $anMod -Force | Out-Null

# Paths in body order, with a shared-prefix run so the block walk has something
# to rebuild - a set of unrelated strings would pass even a broken decoder.
$anPaths = @(
    'base\characters\common\skin\face\microdetail_d.xbm'
    'base\characters\common\skin\face\microdetail_n.xbm'
    'base\gameplay\static_data\database\quest.tweak'
    'base\worlds\03_night_city\sector_a.streamingsector'
    'base\worlds\03_night_city\sector_b.streamingsector'
    'engine\materials\defaults\default.sp'
)
$anIndex = Join-Path $sandbox 'fixture-paths.cwpx'
. $resolver
New-FixtureIndex -Path $anIndex -Paths $anPaths

$vanilla = @($anPaths | ForEach-Object { Get-ResourceHash $_ })
# Hashes of paths no base game ever shipped: the mod-authored side of the
# distinction, and the reason "unresolved" must not be read as "unknown".
$modmade = @(
    Get-ResourceHash 'custom\mymod\jacket.mesh'
    Get-ResourceHash 'custom\mymod\jacket.xbm'
    Get-ResourceHash 'custom\mymod\jacket.app'
)

# top.archive wins everything it shares; bottom.archive ships only files top also
# ships, so nothing of it survives; solo.archive shares nothing with either.
New-FixtureArchive -Path (Join-Path $anMod 'top.archive')    -Hashes ($vanilla[0..3] + $modmade)
New-FixtureArchive -Path (Join-Path $anMod 'bottom.archive') -Hashes ($vanilla[0..1])
New-FixtureArchive -Path (Join-Path $anMod 'solo.archive')   -Hashes ($vanilla[4..5])
Set-Content -LiteralPath (Join-Path $anMod 'modlist.txt') "top.archive`nbottom.archive`nsolo.archive`n" -NoNewline

$anHtml = Join-Path $sandbox 'anatomy.html'
$anMd   = Join-Path $sandbox 'anatomy.md'
$anOut  = Get-AllOutput { & $anatomyTool -GameRoot $anGame -IndexPath $anIndex -Html $anHtml -Md $anMd -SkipRedmod }
$anHtmlText = Get-Content -LiteralPath $anHtml -Raw
$anMdText   = Get-Content -LiteralPath $anMd -Raw

# 4+2+2 vanilla overrides, 3 mod-authored, 11 files, 9 distinct resources.
$anBad = @(
    if ($anOut -notmatch '11 files across 3 archives')  { 'the file total is wrong' }
    if ($anOut -notmatch '8 replace a base-game file')  { 'the override count is wrong - replace/add is the whole report' }
    if ($anOut -notmatch '3 are new')                   { 'mod-authored assets were not counted as new' }
    if ($anOut -notmatch '9 distinct resources')        { 'overlapping claims were not collapsed into one resource' }
)
if ($anBad) { Bad 'anatomy: it tells a replaced file from an added one' ($anBad -join "`n") }
else        { Ok  'anatomy: it tells a replaced file from an added one' }

# The breakdown is what makes the numbers mean anything - it has to name real
# areas and extensions rather than hashes.
$anGroup = @(
    if ($anHtmlText -notmatch 'base\\characters')  { 'the area breakdown does not name base\characters' }
    if ($anHtmlText -notmatch 'base\\worlds')      { 'the area breakdown does not name base\worlds' }
    if ($anHtmlText -notmatch '\.streamingsector') { 'the type breakdown does not name .streamingsector' }
    # Mod-authored paths are unknown by definition, so they must not appear in a
    # breakdown that claims to describe the base game.
    if ($anHtmlText -match 'mymod')                { 'a mod-authored path was counted as a vanilla area' }
)
if ($anGroup) { Bad 'anatomy: the breakdown names real areas and types' ($anGroup -join "`n") }
else          { Ok  'anatomy: the breakdown names real areas and types' }

# bottom.archive ships two files and loses both; solo.archive shares nothing and
# must not be reported as losing anything.
$anLoss = @(
    if ($anOut -notmatch '1 archive\(s\) fully eclipsed') { 'an archive whose every file loses was not reported as eclipsed' }
    if ($anHtmlText -notmatch 'bottom\.archive')          { 'the losing archive is not on the page' }
    if ($anMdText -notmatch 'bottom\.archive')            { 'the losing archive is not in the markdown' }
    if ($anHtmlText -match 'solo\.archive</td><td class="num">[1-9]') { 'an uncontested archive was reported as losing files' }
)
if ($anLoss) { Bad 'anatomy: it names what loses, and only what loses' ($anLoss -join "`n") }
else         { Ok  'anatomy: it names what loses, and only what loses' }

$anMdBad = @(
    if ($anMdText -notmatch '(?m)^# Archive anatomy')   { 'the markdown has no title' }
    if ($anMdText -notmatch '\*\*8\*\* files replace')  { 'the markdown disagrees with the console on the override count' }
    if ($anMdText -notmatch '(?m)^\| Area of the game') { 'the markdown has no area table' }
)
if ($anMdBad) { Bad 'anatomy: the markdown variant carries the same numbers' ($anMdBad -join "`n") }
else          { Ok  'anatomy: the markdown variant carries the same numbers' }

# ============================================================ sitebuilder ====
#
# Two rules carry this whole tool, and the tests below are almost all about
# them.
#
# 1. DO NOT FLATTEN THE DOCUMENTS. The characters are written in four different
#    in-world formats, and a renderer that turns a form into a run-on paragraph
#    or a nested list into a flat one destroys what makes them worth publishing.
#
# 2. IDENTICAL MARKUP, DIFFERENT STYLESHEET. It is CSS Zen Garden: every
#    character page emits the same structure and a per-character theme owns the
#    look. The moment the builder starts emitting different HTML per character,
#    a theme can no longer be written blind, and that is the property worth
#    defending with a test rather than a comment.
#
# The third concern is that the output works when double-clicked: no fetch, no
# absolute paths, nothing from another host.

$mdTool   = Join-Path $Root 'skills\cyberwise-sitebuilder\tools\ConvertFrom-Markdown.ps1'
$siteTool = Join-Path $Root 'skills\cyberwise-sitebuilder\tools\New-CharacterSite.ps1'
. $mdTool

# --- the markdown subset ---------------------------------------------------

$mdSrc = @'
# Doc

Some **bold**, *italic*, and `a**b` in code. 5 < 6 & Q&A.

- one
- two
    - nested
- three

| Preset | Worn |
| --- | --- |
| `Phase 1` | a \| b |

An_underscored_name.archive survives.
'@
$mdOut = ConvertTo-Html -Markdown $mdSrc

$mdBad = @(
    if ($mdOut -notmatch '(?s)<li>two\s*<ul>') { 'a nested list was emitted beside its parent item, not inside it' }
    if ($mdOut -notmatch '<code>a\*\*b</code>') { 'emphasis was applied inside a code span' }
    if ($mdOut -notmatch '<strong>bold</strong>') { 'bold did not render' }
    if ($mdOut -notmatch '<em>italic</em>')       { 'italic did not render' }
    if ($mdOut -notmatch '5 &lt; 6 &amp; Q&amp;A') { 'HTML metacharacters were not escaped' }
    if ($mdOut -match '<script')                   { 'raw HTML passed through' }
    if ($mdOut -notmatch 'An_underscored_name\.archive') { 'underscores were treated as emphasis' }
    if ($mdOut -notmatch '<td>a \| b</td>')              { 'an escaped pipe did not survive as a table cell' }
)
if ($mdBad) { Bad 'sitebuilder: the markdown subset renders what these documents contain' ($mdBad -join "`n") }
else        { Ok  'sitebuilder: the markdown subset renders what these documents contain' }

# --- the documents keep their shape ----------------------------------------

$fieldSrc = @'
SUBJECT: VALERIE AURUM CLEMENS / ID NC770416
CODENAME: VALKYRIE
AKAS: "V", "GOLDEN CHILD"

Constant across every look: palest skin, the same nose,
mouth, ears and brows, which wraps mid sentence like prose.

REF AR-NA-CI-D07-INT-0442

He was assessed at level four and the finding was filed (L4//NO-EXT) without further comment on the matter.

[Interview ended prematurely, interviewee medically subdued]
'@
$fieldOut = ConvertTo-Html -Markdown $fieldSrc
$fieldBad = @(
    if ($fieldOut -notmatch 'NC770416<br>CODENAME') { 'a field block was joined into a run-on paragraph' }
    if ($fieldOut -notmatch 'VALKYRIE<br>AKAS')     { 'a field block was joined into a run-on paragraph' }
    # ...and the opposite error, which is just as bad: hard-wrapped prose must
    # NOT gain ragged line breaks. PowerShell's -match is case-insensitive by
    # default, which once made "Constant across every look:" read as a field.
    if ($fieldOut -match 'the same nose,<br>') { 'hard-wrapped prose was broken at the source line endings' }
    # A theme cannot ask what a line is, so the class list has to say.
    if ($fieldOut -notmatch '<p class="allcaps">REF AR-NA-CI-D07-INT-0442</p>') { 'a reference line was not marked as a stamp' }
    if ($fieldOut -notmatch '<span class="cls">L4//NO-EXT</span>')              { 'a classification marker was not tagged' }
    if ($fieldOut -notmatch '<span class="redact">Interview ended prematurely') { 'a redaction was not tagged' }
    # The field block is also all capitals, and it is a FORM, not a stamp -
    # tagging it .allcaps would take its line breaks away again.
    if ($fieldOut -match '<p class="allcaps">SUBJECT') { 'the opening field block was mistaken for a stamp line' }
)
if ($fieldBad) { Bad 'sitebuilder: a document keeps its own shape' ($fieldBad -join "`n") }
else           { Ok  'sitebuilder: a document keeps its own shape' }

# --- building a site -------------------------------------------------------

$siteSrc = Join-Path $sandbox 'chars'
$siteOut = Join-Path $sandbox 'site'
foreach ($who in 'valkyrie', 'venom') {
    New-Item -ItemType Directory -Path (Join-Path $siteSrc $who) -Force | Out-Null
}
Set-Content -LiteralPath (Join-Path $siteSrc 'valkyrie\Profile - Valkyrie.md') -Value @'
# DOSSIER "VALERIE AURUM CLEMENS" AR-NA-CI-D07

SUBJECT: VALERIE AURUM CLEMENS / ID NC770416
CODENAME: VALKYRIE
STATUS: TERMINATED WITH PREJUDICE

## BACKGROUND
- Born in Charter Hill
'@
Set-Content -LiteralPath (Join-Path $siteSrc 'valkyrie\Meta - Valkyrie.md') -Value @'
# Appearance
Gold everything.
'@
New-Item -ItemType Directory -Path (Join-Path $siteSrc 'venom\media') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $siteSrc 'venom\Profile - Venom.md') -Value @'
# Too Bad, Too Bad

I have a story for you, one long enough to be chosen as the directory line rather than a label.
'@
Set-Content -LiteralPath (Join-Path $siteSrc 'venom\media\one.png') -Value 'stub' -NoNewline
# A character with no theme of its own must still get a page.
New-Item -ItemType Directory -Path (Join-Path $siteSrc 'nobody') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $siteSrc 'nobody\Profile - Nobody.md') -Value @'
# Someone Undesigned

They have no theme file and no stylesheet named after them, and the site still has to hold them.
'@
# A draft, which must not be published.
New-Item -ItemType Directory -Path (Join-Path $siteSrc '_wip') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $siteSrc '_wip\Profile - Wip.md') -Value '# Unfinished'

$siteLog = Get-AllOutput { & $siteTool -From $siteSrc -Out $siteOut -Title 'V of Night City' }
$index  = Get-Content -LiteralPath (Join-Path $siteOut 'index.html') -Raw
$valk   = Get-Content -LiteralPath (Join-Path $siteOut 'valkyrie.html') -Raw
$venom  = Get-Content -LiteralPath (Join-Path $siteOut 'venom.html') -Raw
$nobody = Get-Content -LiteralPath (Join-Path $siteOut 'nobody.html') -Raw

$siteBad = @(
    foreach ($f in 'index.html', 'valkyrie.html', 'venom.html', 'nobody.html', 'site.js',
                   'themes\_base.css', 'themes\index.css', 'themes\valkyrie.css', 'themes\default.css') {
        if (-not (Test-Path -LiteralPath (Join-Path $siteOut $f))) { "$f was not written" }
    }
    if ($index -notmatch 'href="valkyrie\.html"') { 'the index does not link to a character page' }
    if ($index -match '(?i)unfinished|_wip')      { 'a draft folder was published' }
    if ($valk -notmatch '(?i)Gold everything')    { 'the Meta document was dropped' }
    # The page headline IS the document's H1, so the body must not open with it
    # again - every page printed its own title twice.
    $valkBody = [regex]::Match($valk, '(?s)<div class="content">(.*?)</div>').Groups[1].Value
    if ($valkBody -match 'DOSSIER') { 'the document title is repeated inside the body' }
    foreach ($page in $index, $valk, $venom, $nobody) {
        if ($page -match '(?i)https?://(?!www\.w3\.org)') { 'the page loads something from another host' }
        if ($page -match '(?i)[a-z]:\\\\')                { 'an absolute Windows path leaked into the page' }
        if ($page -match "(?i)\\\\$([regex]::Escape($env:USERNAME))\b") { 'the Windows username leaked into the page' }
    }
)
if ($siteBad) { Bad 'sitebuilder: it writes a self-contained site and publishes only what it should' (($siteBad | Select-Object -Unique) -join "`n") }
else          { Ok  'sitebuilder: it writes a self-contained site and publishes only what it should' }

# --- the Zen Garden invariant ----------------------------------------------
#
# Same structure, different stylesheet. Compared as the SEQUENCE OF TAGS AND
# CLASSES with all text stripped: if two characters ever diverge structurally, a
# theme written against one of them silently misses elements on the other.

function Get-Skeleton {
    param([string] $Html)
    $body = [regex]::Match($Html, '(?s)<body.*?>(.*)</body>').Groups[1].Value
    # THE DOCUMENT ITSELF IS NOT PART OF THE CONTRACT. What goes inside .content
    # is whatever the author wrote - one character's file has tables and nested
    # lists, another is unbroken prose - so comparing that would only ever prove
    # the two documents are different, which is the point of the site. The
    # invariant is the SHELL around it, which is what a theme is written
    # against. Same reason the gallery is dropped: it is present exactly when
    # the character has images.
    $body = $body -replace '(?s)(<div class="content">).*?(</div>)', '$1$2'
    $body = $body -replace '(?s)<div class="gallery">.*?</div>', ''
    $tags = [regex]::Matches($body, '<(\w+)(?:[^>]*?\sclass="([^"]*)")?[^>]*>') |
            ForEach-Object { $_.Groups[1].Value + $(if ($_.Groups[2].Success) { '.' + $_.Groups[2].Value }) }
    # The character's own slug is in one class and legitimately differs.
    ($tags -join ' ') -replace 'is-\w+', 'is-X'
}
$skelValk  = Get-Skeleton $valk
$skelVenom = Get-Skeleton $venom

$zenBad = @(
    # Both must load the base sheet and their OWN theme, and they must differ.
    if ($valk  -notmatch 'themes/valkyrie\.css') { 'the dossier page does not load its own theme' }
    if ($venom -notmatch 'themes/venom\.css')    { 'the monologue page does not load its own theme' }
    if ($nobody -notmatch 'themes/default\.css') { 'an undesigned character did not fall back to the default theme' }
    foreach ($page in $valk, $venom, $nobody) {
        if ($page -notmatch 'themes/_base\.css') { 'a page does not load the base stylesheet' }
    }
    # Structure identical. The meta section is the one legitimate difference -
    # Valkyrie has a Meta document and Venom does not - so it is removed before
    # comparing rather than special-cased away.
    $a = $skelValk  -replace 'section\.meta.*?(?=footer)', ''
    $b = $skelVenom -replace 'section\.meta.*?(?=footer)', ''
    if ($a -ne $b) { "two characters emit different markup:`n  $a`n  $b" }
)
if ($zenBad) { Bad 'sitebuilder: identical markup, different stylesheet' (($zenBad | Select-Object -Unique) -join "`n") }
else         { Ok  'sitebuilder: identical markup, different stylesheet' }

# --- media is optional ------------------------------------------------------

$mediaBad = @(
    if ($venom -notmatch 'media/venom/one\.png') { 'a character with media did not get a gallery' }
    if (-not (Test-Path -LiteralPath (Join-Path $siteOut 'media\venom\one.png'))) { 'the image was referenced but never copied' }
    # The prototype was built for somebody with no images at all: a character
    # without media must not emit an empty <img>, which renders as a broken icon.
    if ($valk -match '<img(?![^>]*alt="">)') { 'a character with no media emitted an image tag' }
    if ($valk -notmatch 'class="gallery"' -and $valk -match 'class="gallery"') { 'unreachable' }
)
if ($mediaBad) { Bad 'sitebuilder: media is optional and its absence is not a broken image' ($mediaBad -join "`n") }
else           { Ok  'sitebuilder: media is optional and its absence is not a broken image' }

# ================================================================ anatomy ====
#
# The anatomy report rests on one distinction: a hash the base-game table knows
# is an OVERRIDE, one it does not is a mod-authored asset. Get that backwards
# and every number on the page inverts - a content pack reads as a mod that
# rewrites half the game.
#
# It runs against a HAND-BUILT index rather than the vendored 11 MB table. Two
# reasons: the suite must pass in a checkout that has not fetched the data, and
# the mutation harness runs this file thirty times, where a 30-second table load
# becomes a quarter of an hour. It also means the CWPX1 reader is tested against
# bytes written from the format spec rather than against itself.

function New-FixtureIndex {
    param([string] $Path, [string[]] $Paths, [int] $BlockSize = 4)

    $body = New-Object System.IO.MemoryStream
    $bw   = New-Object System.IO.BinaryWriter($body)
    $blockOffsets = New-Object System.Collections.Generic.List[uint32]
    $prev = $null
    for ($i = 0; $i -lt $Paths.Count; $i++) {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Paths[$i])
        if ($i % $BlockSize -eq 0) {
            $blockOffsets.Add([uint32]$body.Position)
            $bw.Write([uint16]$bytes.Length)
            $bw.Write($bytes)
        } else {
            # Shared prefix with the previous entry, capped at 255 - the field is
            # one byte, which is the whole reason paths are stored in order.
            $shared = 0
            $max = [math]::Min([math]::Min($prev.Length, $bytes.Length), 255)
            while ($shared -lt $max -and $prev[$shared] -eq $bytes[$shared]) { $shared++ }
            $bw.Write([byte]$shared)
            $bw.Write([uint16]($bytes.Length - $shared))
            $bw.Write($bytes, $shared, $bytes.Length - $shared)
        }
        $prev = $bytes
    }
    $bw.Flush()
    $bodyBytes = $body.ToArray()

    # Hashes are stored SIGNED and sorted signed, because the upstream table came
    # out of SQLite, which has no unsigned 64-bit integer.
    $rows = @()
    for ($i = 0; $i -lt $Paths.Count; $i++) {
        $h = Get-ResourceHash $Paths[$i]
        $rows += [pscustomobject]@{ Signed = [BitConverter]::ToInt64([BitConverter]::GetBytes($h), 0); Ordinal = $i }
    }
    $rows = @($rows | Sort-Object Signed)

    $hashBytes = New-Object byte[] ($rows.Count * 12)
    for ($i = 0; $i -lt $rows.Count; $i++) {
        [Array]::Copy([BitConverter]::GetBytes([int64]$rows[$i].Signed), 0, $hashBytes, $i * 12, 8)
        [Array]::Copy([BitConverter]::GetBytes([uint32]$rows[$i].Ordinal), 0, $hashBytes, $i * 12 + 8, 4)
    }
    $blkBytes = New-Object byte[] ($blockOffsets.Count * 4)
    for ($i = 0; $i -lt $blockOffsets.Count; $i++) {
        [Array]::Copy([BitConverter]::GetBytes([uint32]$blockOffsets[$i]), 0, $blkBytes, $i * 4, 4)
    }

    $hashOff = 37
    $blkOff  = $hashOff + $hashBytes.Length
    $bodyOff = $blkOff + $blkBytes.Length

    $out = New-Object System.IO.MemoryStream
    $ow  = New-Object System.IO.BinaryWriter($out)
    $ow.Write([Text.Encoding]::ASCII.GetBytes('CWPX1'))
    $ow.Write([uint32]$Paths.Count)
    $ow.Write([uint32]$BlockSize)
    $ow.Write([uint32]$hashOff);  $ow.Write([uint32]$hashBytes.Length)
    $ow.Write([uint32]$blkOff);   $ow.Write([uint32]$blkBytes.Length)
    $ow.Write([uint32]$bodyOff);  $ow.Write([uint32]$bodyBytes.Length)
    $ow.Write($hashBytes); $ow.Write($blkBytes); $ow.Write($bodyBytes)
    $ow.Flush()

    # The vendored file is raw-deflated and the tool inflates it to a cache keyed
    # on write time. Writing it any other way would test a path nothing uses.
    $fs = [IO.File]::Create($Path)
    $ds = New-Object IO.Compression.DeflateStream($fs, [IO.Compression.CompressionMode]::Compress)
    try { $ds.Write($out.ToArray(), 0, [int]$out.Length) } finally { $ds.Dispose(); $fs.Dispose() }
}

$anatomyTool = Join-Path $Root 'skills\cyberwise-reports\tools\New-ArchiveAnatomy.ps1'
$anGame = Join-Path $sandbox 'anatomygame'
$anMod  = Join-Path $anGame 'archive\pc\mod'
New-Item -ItemType Directory -Path (Join-Path $anGame 'bin\x64') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $anGame 'bin\x64\Cyberpunk2077.exe') 'stub' -NoNewline
New-Item -ItemType Directory -Path $anMod -Force | Out-Null

# Paths in body order, with a shared-prefix run so the block walk has something
# to rebuild - a set of unrelated strings would pass even a broken decoder.
$anPaths = @(
    'base\characters\common\skin\face\microdetail_d.xbm'
    'base\characters\common\skin\face\microdetail_n.xbm'
    'base\gameplay\static_data\database\quest.tweak'
    'base\worlds\03_night_city\sector_a.streamingsector'
    'base\worlds\03_night_city\sector_b.streamingsector'
    'engine\materials\defaults\default.sp'
)
$anIndex = Join-Path $sandbox 'fixture-paths.cwpx'
. $resolver
New-FixtureIndex -Path $anIndex -Paths $anPaths

$vanilla = @($anPaths | ForEach-Object { Get-ResourceHash $_ })
# Hashes of paths no base game ever shipped: the mod-authored side of the
# distinction, and the reason "unresolved" must not be read as "unknown".
$modmade = @(
    Get-ResourceHash 'custom\mymod\jacket.mesh'
    Get-ResourceHash 'custom\mymod\jacket.xbm'
    Get-ResourceHash 'custom\mymod\jacket.app'
)

# top.archive wins everything it shares; bottom.archive ships only files top also
# ships, so nothing of it survives; solo.archive shares nothing with either.
New-FixtureArchive -Path (Join-Path $anMod 'top.archive')    -Hashes ($vanilla[0..3] + $modmade)
New-FixtureArchive -Path (Join-Path $anMod 'bottom.archive') -Hashes ($vanilla[0..1])
New-FixtureArchive -Path (Join-Path $anMod 'solo.archive')   -Hashes ($vanilla[4..5])
Set-Content -LiteralPath (Join-Path $anMod 'modlist.txt') "top.archive`nbottom.archive`nsolo.archive`n" -NoNewline

$anHtml = Join-Path $sandbox 'anatomy.html'
$anMd   = Join-Path $sandbox 'anatomy.md'
$anOut  = Get-AllOutput { & $anatomyTool -GameRoot $anGame -IndexPath $anIndex -Html $anHtml -Md $anMd -SkipRedmod }
$anHtmlText = Get-Content -LiteralPath $anHtml -Raw
$anMdText   = Get-Content -LiteralPath $anMd -Raw

# 4+2+2 vanilla overrides, 3 mod-authored, 11 files, 9 distinct resources.
$anBad = @(
    if ($anOut -notmatch '11 files across 3 archives')  { 'the file total is wrong' }
    if ($anOut -notmatch '8 replace a base-game file')  { 'the override count is wrong - replace/add is the whole report' }
    if ($anOut -notmatch '3 are new')                   { 'mod-authored assets were not counted as new' }
    if ($anOut -notmatch '9 distinct resources')        { 'overlapping claims were not collapsed into one resource' }
)
if ($anBad) { Bad 'anatomy: it tells a replaced file from an added one' ($anBad -join "`n") }
else        { Ok  'anatomy: it tells a replaced file from an added one' }

# The breakdown is what makes the numbers mean anything - it has to name real
# areas and extensions rather than hashes.
$anGroup = @(
    if ($anHtmlText -notmatch 'base\\characters')  { 'the area breakdown does not name base\characters' }
    if ($anHtmlText -notmatch 'base\\worlds')      { 'the area breakdown does not name base\worlds' }
    if ($anHtmlText -notmatch '\.streamingsector') { 'the type breakdown does not name .streamingsector' }
    # Mod-authored paths are unknown by definition, so they must not appear in a
    # breakdown that claims to describe the base game.
    if ($anHtmlText -match 'mymod')                { 'a mod-authored path was counted as a vanilla area' }
)
if ($anGroup) { Bad 'anatomy: the breakdown names real areas and types' ($anGroup -join "`n") }
else          { Ok  'anatomy: the breakdown names real areas and types' }

# bottom.archive ships two files and loses both; solo.archive shares nothing and
# must not be reported as losing anything.
$anLoss = @(
    if ($anOut -notmatch '1 archive\(s\) fully eclipsed') { 'an archive whose every file loses was not reported as eclipsed' }
    if ($anHtmlText -notmatch 'bottom\.archive')          { 'the losing archive is not on the page' }
    if ($anMdText -notmatch 'bottom\.archive')            { 'the losing archive is not in the markdown' }
    if ($anHtmlText -match 'solo\.archive</td><td class="num">[1-9]') { 'an uncontested archive was reported as losing files' }
)
if ($anLoss) { Bad 'anatomy: it names what loses, and only what loses' ($anLoss -join "`n") }
else         { Ok  'anatomy: it names what loses, and only what loses' }

$anMdBad = @(
    if ($anMdText -notmatch '(?m)^# Archive anatomy')   { 'the markdown has no title' }
    if ($anMdText -notmatch '\*\*8\*\* files replace')  { 'the markdown disagrees with the console on the override count' }
    if ($anMdText -notmatch '(?m)^\| Area of the game') { 'the markdown has no area table' }
)
if ($anMdBad) { Bad 'anatomy: the markdown variant carries the same numbers' ($anMdBad -join "`n") }
else          { Ok  'anatomy: the markdown variant carries the same numbers' }

# =================================================================== report ==

Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($script:fail) { Write-Host "$($script:pass) passed, $($script:fail) FAILED" -ForegroundColor Red; exit 1 }
Write-Host "$($script:pass) passed, 0 failed" -ForegroundColor Green
exit 0
