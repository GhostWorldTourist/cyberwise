# Test-ToolMutations.ps1 -- proves Test-Tools.ps1 can actually fail.
#
#     .\tests\Test-ToolMutations.ps1
#
# Same argument as Test-Validator.ps1, applied to the tool tests: a suite that
# has only ever been run against working code has not been shown to detect
# anything. This copies the skills and tests to a temp directory, reintroduces
# one real defect at a time, and asserts the test that owns it fails.
#
# Every mutation below is a bug that actually shipped, restored verbatim:
#
#   hash-comment  '#' stripped from modlist.txt as if it were a comment marker.
#                 Discarded 61 real entries and reported them as unlisted - a
#                 fabricated load-order fault, given to a user twice.
#   lz4-blockmove an LZ4 match copied with Buffer.BlockCopy instead of one byte
#                 at a time, which cannot express the overlapping runs LZ4 uses
#                 for repeats.
#   no-redact     redaction bypassed in a report designed to be pasted publicly.
#   drop-unknown  unrecognised preset hashes silently dropped, so a preset
#                 reports as smaller than it is rather than showing ?<hash>.
#   asi-ancestor  the guard that stops bin\x64\plugins matching as an ANCESTOR of
#                 the CET mods path, which tags every CET mod an ASI plugin too.
#   greedy-name   the folder-name pattern anchored greedily, so a mod whose name
#                 contains hyphens resolves to the wrong Nexus id.
#   ini-ignored   user.ini overrides skipped, so a mod's SHIPPED default is
#                 reported as the user's own binding - the exact failure the
#                 family's flagship method rule exists to prevent.
#   no-hashtable  bindings.json parsed without -AsHashtable, which throws outright
#                 on the case-colliding keys CET really ships.
#   order-blind   load-order move detection switched off. Not a bug that shipped,
#                 but the one finding the snapshot diff exists for: a mod whose
#                 position changed is byte-identical on disk, so if the check is
#                 wrong nothing else notices.
#
# The asi-ancestor mutation earned its place twice over: the first version of its
# test asserted on the manifest's section headings and passed WITH THE BUG
# PRESENT, because a mod is filed under its primary footprint and CET outranks
# ASI either way. Reintroducing the defect is what exposed the test as blind.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$tmp  = Join-Path ([IO.Path]::GetTempPath()) ("cw-mutate-" + [guid]::NewGuid().ToString('N').Substring(0,8))

New-Item -ItemType Directory -Path $tmp -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'skills') -Destination $tmp -Recurse -Force
Copy-Item -LiteralPath (Join-Path $repo 'tests')  -Destination $tmp -Recurse -Force

# Anything at the REPO ROOT that Test-Tools reaches for has to come too, or the
# baseline run fails and every mutation result below is meaningless. This broke
# once when Test-Tools grew install-safety tests: it began calling
# $Root\install.ps1, which was never copied, so the harness refused to proceed -
# correctly, and loudly, which is the only reason it was noticed.
foreach ($rootFile in 'install.ps1') {
    $src = Join-Path $repo $rootFile
    if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $tmp -Force }
}

$suite = Join-Path $tmp 'tests\Test-Tools.ps1'

function Invoke-Suite {
    # A FRESH PROCESS EACH TIME, and this is not optional. Expand-Save.ps1 compiles
    # its LZ4 decoder with Add-Type, and a compiled type cannot be replaced once
    # loaded - so an in-process re-run silently keeps the FIRST version's decoder.
    # Running the baseline and then a mutated copy in one session made the LZ4
    # mutation appear undetectable when the test detects it perfectly well.
    # -Quick drops the headless-browser checks: no mutation here can reach them,
    # and this runs twice per mutation plus a baseline, so the browser launches
    # would dominate the runtime for no coverage.
    $out = & pwsh -NoProfile -NonInteractive -File $suite -Root $tmp -Quick 2>&1 | Out-String
    [pscustomobject]@{ Code = $LASTEXITCODE; Text = $out }
}

$script:pass = 0
$script:fail = 0

# Mutations are applied to a pristine copy each time, so one cannot mask another.
$pristine = @{}
function Save-Original { param([string]$Rel) $pristine[$Rel] = Get-Content -LiteralPath (Join-Path $tmp $Rel) -Raw }
function Restore-All   { foreach ($k in $pristine.Keys) { $pristine[$k] | Set-Content -LiteralPath (Join-Path $tmp $k) -NoNewline } }

$profileRel = 'skills\cyberwise-reports\tools\New-SystemProfile.ps1'
$saveRel    = 'skills\cyberwise-saves\tools\Expand-Save.ps1'
$presetRel  = 'skills\cyberwise-saves\tools\Decode-Preset.ps1'
$hotkeyRel   = 'skills\cyberwise-hotkeys\tools\Get-Hotkeys.ps1'
$manifestRel = 'skills\cyberwise-reports\tools\New-ModManifest.ps1'
$backupRel   = 'skills\cyberwise\tools\ModFileBackup.ps1'
$compareRel  = 'skills\cyberwise-crashes\tools\Compare-InstallSnapshot.ps1'
$mmHtmlRel   = 'skills\cyberwise-reports\tools\ModManifestHtml.ps1'
$reportRel   = 'skills\cyberwise-feedback\tools\New-ProblemReport.ps1'
$installRel  = 'install.ps1'
$liveRel     = 'skills\cyberwise\tools\Test-ScriptsLive.ps1'
$dossierRel  = 'skills\cyberwise-reports\tools\New-ModDossier.ps1'
$bisectRel   = 'skills\cyberwise-crashes\tools\Invoke-BisectRound.ps1'
$resolveRel  = 'skills\cyberwise-conflicts\tools\Resolve-ResourcePath.ps1'
Save-Original $profileRel
Save-Original $saveRel
Save-Original $presetRel
Save-Original $hotkeyRel
Save-Original $manifestRel
Save-Original $backupRel
Save-Original $compareRel
Save-Original $mmHtmlRel
Save-Original $reportRel
Save-Original $installRel
Save-Original $liveRel
Save-Original $dossierRel
Save-Original $bisectRel
Save-Original $resolveRel

function Assert-Detects {
    param([string]$Name, [string]$Rel, [string]$From, [string]$To, [string]$Expect)

    # NORMALISE LINE ENDINGS ON BOTH SIDES BEFORE MATCHING.
    #
    # A multi-line $From is a string literal in THIS file, so it carries this
    # file's line endings - and there is no reason those match the file being
    # mutated. They did not: this file is CRLF, Invoke-BisectRound.ps1 is LF, and
    # a two-line mutation silently stopped applying. The harness reported it
    # correctly ("the code this mutation edits has changed"), which is the only
    # reason it was not read as "the tool is fine".
    #
    # Every multi-line mutation is exposed to this, so it is fixed once here
    # rather than by hand-matching endings per mutation.
    $path = Join-Path $tmp $Rel
    $text = (Get-Content -LiteralPath $path -Raw) -replace "`r`n", "`n"
    $From = $From -replace "`r`n", "`n"
    $To   = $To   -replace "`r`n", "`n"
    if ($text -notmatch [regex]::Escape($From)) {
        $script:fail++
        Write-Host "FAIL  $Name" -ForegroundColor Red
        Write-Host "        the code this mutation edits has changed - the mutation no longer applies" -ForegroundColor DarkRed
        Write-Host "        looked for: $From" -ForegroundColor DarkRed
        return
    }
    $text.Replace($From, $To) | Set-Content -LiteralPath $path -NoNewline

    $r = Invoke-Suite
    Restore-All
    $healed = Invoke-Suite

    $caught = $r.Code -ne 0
    $right  = $r.Text -match "FAIL.*$([regex]::Escape($Expect))"
    $clean  = $healed.Code -eq 0

    if ($caught -and $right -and $clean) {
        $script:pass++
        Write-Host "ok    detects: $Name" -ForegroundColor DarkGreen
        return
    }
    $script:fail++
    Write-Host "FAIL  $Name" -ForegroundColor Red
    if (-not $caught)    { Write-Host "        the bug was reintroduced and every test still passed" -ForegroundColor DarkRed }
    elseif (-not $right) { Write-Host "        it failed, but not on the test that owns this: expected '$Expect'" -ForegroundColor DarkRed }
    if (-not $clean)     { Write-Host "        the restore did not put the tree back - later results are unreliable" -ForegroundColor DarkRed }
}

Write-Host "mutating a copy at $tmp`n"

$base = Invoke-Suite
if ($base.Code -ne 0) {
    Write-Host 'FAIL  the unmutated copy does not pass - nothing below would be meaningful' -ForegroundColor Red
    Write-Host $base.Text
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}
$script:pass++
Write-Host "ok    the unmutated copy passes`n" -ForegroundColor DarkGreen

Assert-Detects 'modlist.txt parsed with # as a comment marker' $profileRel `
    'Where-Object { $_ })' `
    "Where-Object { `$_ -and -not `$_.StartsWith('#') })" `
    "'#' is a filename character"

Assert-Detects 'an LZ4 match copied as a block instead of byte-at-a-time' $saveRel `
    'for (int i = 0; i < matchLen; i++) dst[d++] = dst[m++];' `
    'Buffer.BlockCopy(dst, m, dst, d, matchLen); d += matchLen;' `
    'overlapping match'

Assert-Detects 'redaction bypassed in the public-facing report' $profileRel `
    'if ($NoRedact) { return $s }' `
    'return $s' `
    'redacts the install path'

Assert-Detects 'the diff preview reading its new text from a bad sub-expression' $backupRel `
    '$newRaw = if ($NewFile) { [IO.File]::ReadAllText($NewFile) } else { $NewText }' `
    '$newRaw = $null   # mutation: what the broken (if ...) sub-expression yielded' `
    'diff counts the actual change'

Assert-Detects 'restore overwriting without snapshotting what it replaced' $backupRel `
    'Backup-ModFile -Path $Path -Note "auto: state before restoring $($pick.SnapshotId)" -Vault $Vault -Force | Out-Null' `
    '# mutation: no pre-restore snapshot' `
    'restore snapshots the state it replaced'

Assert-Detects 'load-order move detection switched off, hiding the invisible change' $compareRel `
    'if ([Math]::Abs($d) -gt $MoveThreshold)' `
    'if ($false)' `
    'load-order move is detected'

Assert-Detects 'the ASI ancestor guard removed, tagging every CET mod as a plugin too' $manifestRel `
    "if (-not `$other) { continue }" `
    "if (-not `$other) { }" `
    'not mistaken for an ASI plugin'

Assert-Detects 'the folder-name pattern anchored greedily, so hyphenated names lose their id' $manifestRel `
    '^(?<name>.+?)-(?<id>\d+)-(?<ver>.*?)-(?<ts>\d{10})$' `
    '^(?<name>.+)-(?<id>\d+)-(?<ver>.*?)-(?<ts>\d{10})$' `
    'parse into name, id and version'

Assert-Detects "user.ini overrides ignored, so shipped defaults are reported as the user's" $hotkeyRel `
    'if ($ov -and $overrides.ContainsKey($ov)) {' `
    'if ($false -and $ov -and $overrides.ContainsKey($ov)) {' `
    "rebind beats the mod's shipped default"

Assert-Detects 'bindings.json parsed without -AsHashtable, which throws on case-colliding keys' $hotkeyRel `
    'ConvertFrom-Json -AsHashtable' `
    'ConvertFrom-Json' `
    'case-colliding bindings.json'

# Both of these fail SILENTLY in the direction that matters: the report is
# written, it looks complete, and the user only finds out it cannot be sent when
# Discord refuses the paste.
Assert-Detects 'the profile no longer saying its markdown is too long to send' $profileRel `
    'if ($chars -gt 2000) {' `
    'if ($false) {' `
    'too long to paste'

Assert-Detects 'the manifest no longer saying its markdown is too long to send' $manifestRel `
    'if ($mdChars -gt 2000) {' `
    'if ($false) {' `
    'unpasteable markdown says so'

# Both halves of the manifest, because the leak that shipped was one output
# forgetting while the other remembered - a single mutation would have proved
# only the half that was already safe.
Assert-Detects 'the manifest markdown printing the raw staging path again' $manifestRel `
    'elseif ($htmlHelperLoaded) { Get-RedactedStagingPath $StagingRoot }' `
    'elseif ($htmlHelperLoaded) { $StagingRoot }' `
    'redact the staging path by default'

Assert-Detects 'the manifest HTML header printing the raw staging path again' $mmHtmlRel `
    '$shownRoot = if ($NoRedact) { $StagingRoot } else { Get-RedactedStagingPath $StagingRoot }' `
    '$shownRoot = $StagingRoot' `
    'redact the staging path by default'

# A problem report is written for a stranger and pasted without being re-read.
# Both of these produce a file that looks completely normal.
Assert-Detects 'redaction skipped in a report written for a stranger' $reportRel `
    'if ($NoRedact -or -not $Text) { return $Text }' `
    'return $Text' `
    'pasted stack trace is redacted'

Assert-Detects 'the Discord form no longer trimmed to fit a message' $reportRel `
    '$discordText = Get-Fitted (Get-Redacted $short.ToString()) 2000' `
    '$discordText = Get-Redacted $short.ToString()' `
    'Discord form fits one message'

# PowerShell's own trap, and it shipped: $hash[$missingKey] is $null, @($null) is
# an array of ONE, and Join-Path with a null tail resolves to the root - so every
# layer a mod did NOT ship reported "1 of 1 file(s) deployed".
# The nastiest failure the path table can have: paths are front-coded, each one
# rebuilt from the one before, so a walk that is off by one returns a NEIGHBOURING
# path. Not an error, not a blank - a real, plausible, wrong filename, printed
# into a conflict report as the file a mod just lost.
Assert-Detects 'a front-coded path walk that stops one entry short' $resolveRel `
    'for ($i = 1; $i -le $within; $i++) {' `
    'for ($i = 1; $i -lt $within; $i++) {' `
    'round-trip exactly'

# The table stores hashes signed because SQLite has no unsigned 64-bit type.
# Comparing the archive's unsigned hash directly finds nothing for every hash
# above 2^63 - half of them, silently, with no error anywhere.
Assert-Detects 'the signed conversion dropped, losing half of all hashes' $resolveRel `
    '$signed = [BitConverter]::ToInt64([BitConverter]::GetBytes($Hash), 0)' `
    '$signed = $Hash' `
    'known hash resolves to its path'

# Containment is one `if`, and without it a cut list can move any file the user
# can read. Nothing errors, the round reports success, and the manifest records
# a file that was never part of the game.
Assert-Detects 'path containment removed, letting a list escape the game directory' $bisectRel `
    'if (-not (Test-InsideGameRoot $full)) {' `
    'if ($false) {' `
    'cannot escape the game directory'

# A round is armed while the manager still believes the mods are deployed, so a
# deployment puts them back without anyone noticing. Not checking is how a round
# scores a result on a configuration nobody recorded.
Assert-Detects 'a bisect status that never checks whether the manager undid the round' $bisectRel `
    'if (Test-Path -LiteralPath (Join-Path $GameRoot $item.Rel)) { $undone += "$($r.Round): $($item.Rel)" }' `
    '# mutation: no re-deploy check' `
    'manager undid is reported as void'

# The quiet one. Parking the names that happen to resolve and shrugging at the
# rest produces a round that exists in no manifest, and its result scores exactly
# like a real one.
Assert-Detects 'a bisect round arming with only the names that resolved' $bisectRel `
    'Write-Host ''Nothing was parked. Fix the list and re-run - a partly-parked round tests a configuration nobody recorded.'' -ForegroundColor Yellow
    exit 1' `
    'Write-Host ''carrying on with what resolved'' -ForegroundColor Yellow' `
    'unresolvable name refuses the whole round'

#
# BOTH lines have to go. The fix is two independent guards - a key check and a
# null filter - so removing either one alone changes nothing observable, and a
# single-line mutation "passed" while the bug it names was gone. Reintroducing a
# defect means reintroducing it fully, not deleting one of the things that would
# have prevented it.
Assert-Detects 'a dossier inventing the layers a mod does not ship' $dossierRel `
    "if (-not `$layers.Contains(`$kind)) { continue }
    `$items = @(`$layers[`$kind] | Where-Object { `$_ })" `
    '$items = @($layers[$kind])' `
    'layers a mod ships, and no others'

# Both of these make the script check LOUDER rather than quieter, which is the
# direction that gets a checker ignored. Ten of the eleven mods it first flagged
# on a real install were false alarms of exactly these two kinds.
Assert-Detects 'declarations inside comments counted as real symbols' $liveRel `
    "`$t = [regex]::Replace(`$t, '(?s)/\*.*?\*/', '')" `
    '# mutation: comments left in' `
    'only a genuinely uncompiled mod'

Assert-Detects 'the newest run trusted as the launch that built the live bundle' $liveRel `
    '$lastLaunch = $runs | Where-Object { $_.Output -and -not (Test-IsOutsideGame $_.Output) } | Select-Object -First 1' `
    '$lastLaunch = $lastRun' `
    'live bundle comes from the log'

# The install bug that hid a day of work: any existing link counted as healthy,
# so the agents kept loading a different copy and re-running the installer agreed
# that everything was fine.
Assert-Detects 'an existing link accepted without checking where it points' $installRel `
    'if ($actual -and $actual -eq [IO.Path]::GetFullPath($target)) {' `
    'if ($actual) {' `
    'not called healthy'

Assert-Detects 'unrecognised preset hashes dropped instead of shown' $presetRel `
    '$label = if ($group) { Get-Label $group } else { "?$hash" }' `
    'if (-not $group) { continue }
        $label = Get-Label $group' `
    'unknown hashes survive'

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($script:fail) { Write-Host "$($script:pass) passed, $($script:fail) FAILED" -ForegroundColor Red; exit 1 }
Write-Host "$($script:pass) passed, 0 failed - every shipped defect is detected by the test that owns it" -ForegroundColor Green
exit 0
