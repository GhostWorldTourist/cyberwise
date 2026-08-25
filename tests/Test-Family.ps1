# Test-Family.ps1 -- structural validation for the cyberwise skill family.
#
#     .\tests\Test-Family.ps1            # exits 1 on any failure
#     .\tests\Test-Family.ps1 -Verbose   # also lists what passed
#
# WHAT THIS IS FOR
#
# A skill family fails silently. A dangling `references/foo.md`, a frontmatter
# name that stopped matching its directory, a route to a skill that was renamed -
# none of it errors. The skill simply loads and quietly cannot find the thing it
# told the model to read. Splitting cyberwise into eight parts produced exactly
# one of those (a reference that had moved to another skill) and it was caught by
# hand; the point of this file is that the next one is caught by the machine.
#
# NO TEST FRAMEWORK ON PURPOSE. Pester 5 would be a dependency, and the bundled
# Pester 3 does not behave the same under pwsh 7. The whole family's position is
# that PowerShell is already on the machine and nothing else should need
# installing; a test suite that violates that is the wrong test suite.

[CmdletBinding()]
param(
    [string] $Root
)

# $PSScriptRoot is EMPTY inside a param default on Windows PowerShell 5.1
# when the script is run with -File or dot-sourced - it is only populated
# under the call operator, and pwsh 7 populates it in every case. So the
# default below is resolved HERE, where it is correct on both engines and
# by every invocation route. See cyberwise/references/environment.md.

if (-not $Root) { $Root = (Split-Path -Parent $PSScriptRoot) }

$script:fail = 0
$script:pass = 0

function Check {
    param([string]$What, [scriptblock]$Test)
    $problems = @(& $Test)
    if ($problems.Count) {
        $script:fail++
        Write-Host "FAIL  $What" -ForegroundColor Red
        $problems | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkRed }
    } else {
        $script:pass++
        Write-Verbose "pass  $What"
        Write-Host "ok    $What" -ForegroundColor DarkGreen
    }
}

$skillsRoot = Join-Path $Root 'skills'
if (-not (Test-Path -LiteralPath $skillsRoot)) { Write-Host "no skills/ directory under $Root" -ForegroundColor Red; exit 1 }
$skills = @(Get-ChildItem -LiteralPath $skillsRoot -Directory | Sort-Object Name)

# Everything after the structure check reads SKILL.md. A skill missing one is
# already reported there, so the rest work from this list instead - otherwise a
# single missing file throws and takes every later check down with it, turning
# one clear failure into a stack trace.
$withMd = @($skills | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') })

$frontMd  = Join-Path $skillsRoot 'cyberwise\SKILL.md'
$frontText = if (Test-Path -LiteralPath $frontMd) { Get-Content -LiteralPath $frontMd -Raw } else { $null }

Write-Host "cyberwise family: $($skills.Count) skills under $skillsRoot`n"

# --------------------------------------------------------------- structure --

Check 'every skill directory has a SKILL.md' {
    foreach ($s in $skills) {
        if (-not (Test-Path -LiteralPath (Join-Path $s.FullName 'SKILL.md'))) { "$($s.Name) has no SKILL.md" }
    }
}

Check 'the front door exists and is named cyberwise' {
    if (-not ($skills.Name -contains 'cyberwise')) { 'no skills/cyberwise - the family has no front door' }
}

# ------------------------------------------------------------- frontmatter --

# A skill whose `name` does not match its directory is loadable but unreferenceable:
# routing tables and /slash invocations both use the directory.
Check 'frontmatter name matches the directory name' {
    foreach ($s in $withMd) {
        $md = Get-Content -LiteralPath (Join-Path $s.FullName 'SKILL.md') -Raw
        if ($md -notmatch '(?m)^name:\s*(\S+)\s*$') { "$($s.Name): no name: in frontmatter"; continue }
        if ($matches[1] -ne $s.Name) { "$($s.Name): frontmatter says name: $($matches[1])" }
    }
}

# The description is the ONLY part always in context, and it is what decides
# whether the skill fires at all. Claude Code truncates it past
# skillListingMaxDescChars (default 1536); a description short enough to be
# useless is the other failure.
Check 'every description is present and a sane length (40-1536 chars)' {
    foreach ($s in $withMd) {
        $md = Get-Content -LiteralPath (Join-Path $s.FullName 'SKILL.md') -Raw
        if ($md -notmatch '(?m)^description:\s*(.+)$') { "$($s.Name): no description:"; continue }
        $len = $matches[1].Trim().Length
        if ($len -lt 40)   { "$($s.Name): description is only $len chars - it will not fire reliably" }
        if ($len -gt 1536) { "$($s.Name): description is $len chars - truncated in the listing" }
    }
}

# ------------------------------------------------------------------- links --

# The failure this file was written for.
Check 'every references/*.md a SKILL.md names resolves inside that skill' {
    foreach ($s in $withMd) {
        $md = Get-Content -LiteralPath (Join-Path $s.FullName 'SKILL.md') -Raw
        foreach ($m in [regex]::Matches($md, '`(references/[A-Za-z0-9._-]+\.md)`')) {
            $rel = $m.Groups[1].Value
            if (-not (Test-Path -LiteralPath (Join-Path $s.FullName $rel))) { "$($s.Name) -> $rel does not exist" }
        }
    }
}

# A tool path is either in-skill (`tools/X.ps1`) or an explicit cross-skill
# reference (`cyberwise/tools/X.ps1`). Both get resolved. The cross-skill form
# exists so that one genuinely shared tool - the backup helper - can be cited by
# the skills that need it without eight copies drifting apart.
Check 'every tools/*.ps1 a SKILL.md names resolves' {
    foreach ($s in $withMd) {
        $md = Get-Content -LiteralPath (Join-Path $s.FullName 'SKILL.md') -Raw
        foreach ($m in [regex]::Matches($md, '((?:cyberwise[a-z-]*[\\/])?tools[\\/][A-Za-z0-9._-]+\.ps1)')) {
            $rel   = $m.Groups[1].Value -replace '\\','/'
            $owner = $s.FullName
            if ($rel -match '^(cyberwise[a-z-]*)/(.+)$') {
                $ownerName = $matches[1]; $rel = $matches[2]
                if ($skills.Name -notcontains $ownerName) { "$($s.Name) -> names skill '$ownerName', which does not exist"; continue }
                $owner = (Join-Path $skillsRoot $ownerName)
            }
            if (-not (Test-Path -LiteralPath (Join-Path $owner $rel))) { "$($s.Name) -> $($m.Groups[1].Value) does not exist" }
        }
    }
}

Check 'every reference file is named by the SKILL.md that owns it' {
    foreach ($s in $withMd) {
        $refDir = Join-Path $s.FullName 'references'
        if (-not (Test-Path -LiteralPath $refDir)) { continue }
        $md = Get-Content -LiteralPath (Join-Path $s.FullName 'SKILL.md') -Raw
        foreach ($f in (Get-ChildItem -LiteralPath $refDir -Filter *.md)) {
            if ($md -notmatch [regex]::Escape($f.Name)) { "$($s.Name): references/$($f.Name) is shipped but never mentioned" }
        }
    }
}

# ------------------------------------------------------------------ routes --

Check 'every cyberwise-* skill the front door routes to exists' {
    if (-not $frontText) { return }   # already reported by the front-door check
    # `cyberwise-*` is the literal glob used in prose, not a route.
    foreach ($m in [regex]::Matches($frontText, 'cyberwise-([a-z]{2,})')) {
        $name = "cyberwise-$($m.Groups[1].Value)"
        if ($skills.Name -notcontains $name) { "front door routes to $name, which does not exist" }
    }
}

Check 'every topic skill is reachable from the front door' {
    if (-not $frontText) { return }   # already reported by the front-door check
    foreach ($s in $skills) {
        if ($s.Name -eq 'cyberwise') { continue }
        if ($frontText -notmatch [regex]::Escape($s.Name)) { "$($s.Name) exists but the front door never mentions it" }
    }
}

# -------------------------------------------------------------- provenance --

# Reference files get read in isolation - a model loading crashes.md never sees
# the README - so each has to carry its own verification stamp.
Check 'every reference file carries a Verified + Re-check header' {
    foreach ($s in $skills) {
        $refDir = Join-Path $s.FullName 'references'
        if (-not (Test-Path -LiteralPath $refDir)) { continue }
        foreach ($f in (Get-ChildItem -LiteralPath $refDir -Filter *.md)) {
            $head = (Get-Content -LiteralPath $f.FullName -TotalCount 8) -join "`n"
            if ($head -notmatch '\*\*Verified:\*\*')            { "$($s.Name)/references/$($f.Name): no **Verified:** stamp" }
            if ($head -notmatch '\*\*Re-check after a patch:') { "$($s.Name)/references/$($f.Name): no **Re-check after a patch:** line" }
        }
    }
}

# A stamp is only useful if it can be compared against what the machine reports,
# so a version-bound file has to carry an actual version number - "Verified:
# recently" is not a stamp. This is what makes the one-line ProductVersion check
# in the front door actionable rather than decorative.
#
# Not every file IS version-bound: report-design.md is about browsers and human
# readers and would be dishonest carrying a game version. Those must say so
# explicitly, so the reader can tell the difference between "not patch-dependent"
# and "nobody wrote down which patch".
Check 'every Verified stamp names a patch version, or declares it needs none' {
    foreach ($s in $skills) {
        $refDir = Join-Path $s.FullName 'references'
        if (-not (Test-Path -LiteralPath $refDir)) { continue }
        foreach ($f in (Get-ChildItem -LiteralPath $refDir -Filter *.md)) {
            $head = (Get-Content -LiteralPath $f.FullName -TotalCount 8) -join "`n"
            if ($head -notmatch '\*\*Verified:\*\*([^\r\n]*)') { continue }
            if ($matches[1] -match '\d+\.\d+') { continue }
            if ($head -match '(?i)nothing here depends on a game patch|does not depend on a game patch') { continue }
            "$($s.Name)/references/$($f.Name): Verified stamp has no version, and nothing declares the file patch-independent"
        }
    }
}

# ---------------------------------------------------------------- codex -----

# The family installs into Codex as well as Claude Code. Codex reads
# agents/openai.yaml for the name and description it shows; a skill without one
# still loads but presents as a bare directory name, so a new skill that forgets
# it is invisible in one of the two agents it claims to support.
Check 'every skill carries a Codex manifest with the three interface fields' {
    foreach ($s in $skills) {
        $yaml = Join-Path $s.FullName 'agents\openai.yaml'
        if (-not (Test-Path -LiteralPath $yaml)) { "$($s.Name): no agents/openai.yaml"; continue }
        $text = Get-Content -LiteralPath $yaml -Raw
        foreach ($field in 'display_name', 'short_description', 'default_prompt') {
            if ($text -notmatch "(?m)^\s*$field\s*:\s*\S") { "$($s.Name)/agents/openai.yaml: no $field" }
        }
        # The prompt references the skill by name; a copy-paste that kept another
        # skill's name sends Codex somewhere else entirely.
        if ($text -match '(?m)^\s*default_prompt\s*:\s*"([^"]*)"' -and $matches[1] -notmatch [regex]::Escape("`$$($s.Name)")) {
            "$($s.Name)/agents/openai.yaml: default_prompt does not reference `$$($s.Name)"
        }
    }
}

# --------------------------------------------------------- upstream guard --

# THE SHIP GATE for the upstream guard.
#
# Cyberwise ships tools and instructions, and an agent mid-problem will sometimes
# edit one of those tools rather than use the affordance the family already has
# for the job. Nothing reports it, and the next session inherits a tool that no
# longer behaves the way its own documentation says.
#
# The check is deliberately NOT a verdict on the change. It fails only on a
# difference nobody wrote down, and there are two remedies - which one is right
# is a judgement no test can make:
#
#   the change IS the new upstream     -> New-UpstreamManifest.ps1 -Write
#   the change belongs to this install -> Register-CwChange, and it stops failing
#
# The first is also what you run after any legitimate edit to a shipped file,
# exactly as you rerun Get-ToolIndex.ps1 -Write after adding a tool. That is what
# keeps the manifest current instead of slowly becoming a fossil.
Check 'every shipped file matches the upstream manifest, or is in the change register' {
    $guard = Join-Path $skillsRoot 'cyberwise\tools\UpstreamGuard.ps1'
    if (-not (Test-Path -LiteralPath $guard)) { 'skills/cyberwise/tools/UpstreamGuard.ps1 is missing'; return }
    . $guard

    $r = Test-CwUpstream -Root $Root
    if ($r.Reason -eq 'nolayout')   { 'the guard could not find a skills\ directory to check'; return }
    if ($r.Reason -eq 'nomanifest') {
        # Deleting the manifest is the cheapest way to make every other
        # difference invisible, so its absence is a failure in its own right
        # rather than a reason to skip the check.
        "no upstream manifest at $($r.ManifestPath) - rebuild it with skills\cyberwise\tools\New-UpstreamManifest.ps1 -Write"
        return
    }

    foreach ($f in ($r.Findings | Where-Object { $_.State -eq 'UNREGISTERED' })) {
        "$($f.Path) differs from upstream and nothing is recorded about it"
    }
    foreach ($f in ($r.Findings | Where-Object { $_.State -eq 'MISSING' })) {
        "$($f.Path) is in the manifest but not on disk"
    }
    foreach ($f in ($r.Findings | Where-Object { $_.State -eq 'NEW' -and -not $_.Entry })) {
        "$($f.Path) is a new file in a guarded location and is not in the manifest"
    }
    if (@($r.Findings | Where-Object { $_.State -ne 'OK' -and $_.State -ne 'REGISTERED' }).Count) {
        'fix: New-UpstreamManifest.ps1 -Write if these ARE the new upstream, or Register-CwChange if they belong to this install'
    }
}

# Every tool notices on startup, because a check nobody runs is worth nothing and
# the agent most likely to edit a tool is the least likely to run this suite. A
# tool that never dot-sources the guard is a hole in the net, and it is an
# invisible one: the tool works perfectly, it simply never looks.
Check 'every family tool runs the upstream guard at startup' {
    # The guard itself, and the two scripts whose whole job is to report on it -
    # they would print the one-line advisory and then print the real report.
    $exempt = @('UpstreamGuard.ps1', 'Test-Upstream.ps1', 'New-UpstreamManifest.ps1')

    # OUTSTANDING, NOT EXEMPT. cyberwise-hotkeys was being edited by somebody
    # else when the guard was rolled out, so its tools have not had the two-line
    # snippet added yet. They are still covered by the MANIFEST - a change to one
    # is still caught by the ship gate above - they just do not carry the
    # startup advisory that makes a change noticeable without running the suite.
    #
    # This list is a debt, and it is printed on every run so that it stays
    # visible. Do not add anything to it to make a failure go away; add the
    # snippet instead. It is two lines, and the pattern is in any other tool.
    $pending = @(
        'cyberwise-hotkeys/tools/DeviceGeometry.ps1'
        'cyberwise-hotkeys/tools/Get-Hotkeys.ps1'
        'cyberwise-hotkeys/tools/Get-MouseProfile.ps1'
        'cyberwise-hotkeys/tools/KeyIdentity.ps1'
        'cyberwise-hotkeys/tools/New-HotkeySheet.ps1'
    )
    $stillPending = @()

    foreach ($s in $skills) {
        $toolsDir = Join-Path $s.FullName 'tools'
        if (-not (Test-Path -LiteralPath $toolsDir)) { continue }
        foreach ($t in (Get-ChildItem -LiteralPath $toolsDir -Filter *.ps1 -File)) {
            if ($exempt -contains $t.Name) { continue }
            $rel  = "$($s.Name)/tools/$($t.Name)"
            $text = Get-Content -LiteralPath $t.FullName -Raw
            if ($text -match 'Invoke-CwStartupGuard') { continue }
            if ($pending -contains $rel) { $stillPending += $rel; continue }
            "$rel never runs the upstream guard"
        }
    }

    if ($stillPending.Count) {
        Write-Host "      OUTSTANDING: $($stillPending.Count) tool(s) still need the startup guard snippet:" -ForegroundColor Yellow
        $stillPending | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkYellow }
    }
    # A name that has been dealt with must come off the list, or the list becomes
    # a place where things go to be forgotten.
    foreach ($p in $pending) {
        if ($stillPending -notcontains $p) { "$p now runs the guard - take it off the pending list in this test" }
    }
}

# --------------------------------------------------------------- safe edits --

# A skill that tells the model to write into a user's install must name the
# backup helper in the same file. Reference files get read in isolation, so
# "the front door says to snapshot" is not protection when the model is looking
# at this page and nothing else. Irreversible edits are the one failure mode
# here with no recovery path.
Check 'any skill that advises writing into an install names the backup helper' {
    # BOTH conditions, deliberately. Keying on write-ish words alone flagged the
    # backstory skill for saying prose is "never rewritten" - a check that cries
    # wolf gets switched off, so it has to mean a write to a real game file:
    # an actual write cmdlet or "in place", AND a concrete file it could land on.
    # `rewrit` is back in the list, and it has to be: without it the ONLY trigger
    # words in cyberwise-conflicts lived inside the backup advice itself, so
    # deleting that advice also deleted the trigger and the check passed on the
    # very regression it exists to catch. A trigger that lives in the remedy is
    # not a check. The AND with $gameFiles is what makes it safe to include -
    # prose about "never rewritten" in a skill with no game files is ignored.
    $writeVerbs = 'Set-Content|Out-File|WriteAllText|\bin place\b|rewrit'
    $gameFiles  = 'modlist\.txt|user\.ini|\.yaml|\.reds|\.archive|\.xl\b|inputUserMappings'
    foreach ($s in $withMd) {
        $md = Get-Content -LiteralPath (Join-Path $s.FullName 'SKILL.md') -Raw
        if ($md -notmatch $writeVerbs -or $md -notmatch $gameFiles) { continue }
        if ($md -notmatch 'ModFileBackup|Set-ModFileContent|Restore-ModFile') {
            "$($s.Name): advises an in-place write to a game file but never mentions ModFileBackup.ps1"
        }
    }
}

# ------------------------------------------------------------------- tools --

Check 'every shipped .ps1 parses' {
    foreach ($f in (Get-ChildItem -LiteralPath $Root -Filter *.ps1 -Recurse)) {
        $errs = $null
        [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs) | Out-Null
        if ($errs) { "$($f.Name): $($errs[0].Message)" }
    }
}

# ----------------------------------------------- a 5.1 trap in param blocks --
#
# $PSScriptRoot is EMPTY inside a param-block DEFAULT on Windows PowerShell 5.1
# whenever the script carries [CmdletBinding()] and is started with -File, or is
# dot-sourced. Under the call operator it is populated, and pwsh 7 populates it
# in every case - which is precisely why this survives review. Every tool here
# gets written and tried at a prompt, where it works, and then breaks the first
# time a scheduled task, an installer step, the tray or an agent runs it with
# -File. Six tools shipped with it before anything noticed.
#
# It fails two ways and the quiet one is worse. Split-Path and Join-Path reject
# the empty string loudly, so those at least stop; but "$PSScriptRoot	hemes"
# silently becomes "	hemes" - the root of whatever drive happens to be current.
#
# The fix is to leave the parameter undefaulted and resolve it in the BODY,
# which is correct on both engines by every route and still honours an override.
# $MyInvocation.MyCommand.Path is NOT a workaround: it is null in the same spot.
# The family's own suite runs under Windows PowerShell 5.1, so a tool that only
# works on pwsh 7 is a tool most users cannot run. `-Encoding utf8NoBOM` is the
# one that keeps reappearing: it does not exist on 5.1 and throws outright, and
# the obvious "fix" of `-Encoding UTF8` writes a BOM there - three invisible
# bytes in front of `---` that stop a front-matter parser and look like nothing.
#
# Six tools shipped with it while a seventh carried a comment explaining the
# problem, which is the argument for a check over a convention. Write through
# [System.IO.File]::WriteAllText/WriteAllLines with an explicit
# UTF8Encoding($false) instead. Comment lines are skipped, since the guidance
# has to be able to name the thing it is warning about.
#
# NOT banned here: ConvertFrom-Json -AsHashtable, which Get-Hotkeys.ps1 genuinely
# requires - bindings.json has keys differing only in case, and 5.1 cannot read
# it at all. That tool needs pwsh 7 for a real reason rather than by accident.
# A GENERATED REPORT GOES WHERE THE OTHER RECORDS GO.
#
# These defaults were scattered three ways: %USERPROFILE%\Downloads, which is a
# folder people empty; a bare relative filename; and (Get-Location), which is
# whatever directory the caller happened to be standing in - so an agent run
# from a clone wrote its reports into the repo. None of the three is a place
# anybody looks a week later, and the last one quietly littered the source tree.
#
# Get-Location is the one worth a check rather than a convention, because it
# LOOKS deliberate in a param block and its damage depends entirely on who
# called the tool.
Check 'no report defaults to Downloads or the current directory' {
    $outNames = 'Out', 'Html', 'Md', 'OutFile', 'Report'
    foreach ($f in (Get-ChildItem -LiteralPath $Root -Filter *.ps1 -Recurse)) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
        if (-not $ast -or -not $ast.ParamBlock) { continue }
        foreach ($prm in $ast.ParamBlock.Parameters) {
            if (-not $prm.DefaultValue) { continue }
            $name = $prm.Name.VariablePath.UserPath
            if ($outNames -notcontains $name) { continue }
            $txt = $prm.DefaultValue.Extent.Text
            if ($txt -like '*Downloads*' -or $txt -like '*Desktop*') {
                "$($f.Name): `$$name defaults into Downloads/Desktop; it belongs with the install's other records"
            }
            if ($txt -match 'Get-Location') {
                "$($f.Name): `$$name defaults to Get-Location, so where the report lands depends on who called the tool"
            }
        }
    }
}

Check 'no shipped tool uses the 5.1-absent no-BOM encoding name' {
    # The token is assembled from two halves so that this check's own name and
    # message do not match it. Spelling it out here would make the file its own
    # first finding, which is funny once and then just noise forever.
    $bad = 'utf8' + 'NoBOM'
    foreach ($f in (Get-ChildItem -LiteralPath $Root -Filter *.ps1 -Recurse)) {
        $n = 0
        foreach ($line in (Get-Content -LiteralPath $f.FullName)) {
            $n++
            if ($line.TrimStart().StartsWith('#')) { continue }
            if ($line -match ('-Encoding\s+' + $bad)) {
                "$($f.Name):$n passes -Encoding $bad, which throws on Windows PowerShell 5.1"
            }
        }
    }
}

Check 'no param default reads $PSScriptRoot (it is empty there on 5.1)' {
    foreach ($f in (Get-ChildItem -LiteralPath $Root -Filter *.ps1 -Recurse)) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
        if (-not $ast -or -not $ast.ParamBlock) { continue }
        # Only an ADVANCED script binds its defaults early enough to hit this.
        $cb = @($ast.ParamBlock.Attributes | Where-Object { $_.TypeName.Name -eq 'CmdletBinding' })
        if (-not $cb.Count) { continue }
        foreach ($prm in $ast.ParamBlock.Parameters) {
            if (-not $prm.DefaultValue) { continue }
            $bad = $prm.DefaultValue.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $n.VariablePath.UserPath -eq 'PSScriptRoot'
            }, $true)
            if ($bad) {
                "$($f.Name): `$$($prm.Name.VariablePath.UserPath) defaults from `$PSScriptRoot - empty on 5.1 under -File; resolve it in the body instead"
            }
        }
    }
}

# ------------------------------------------------------------ issue forms --

# GitHub issue forms fail the same way a skill does: SILENTLY. A malformed one is
# not reported anywhere the author will see - the template simply stops appearing
# in the chooser, and the first sign of trouble is that bug reports arrive with
# none of the fields anybody asked for. Nobody re-tests a template that worked
# once, because nobody opens their own issues.
#
# There is no YAML parser in PowerShell, and adding one would break the rule that
# this repo needs nothing installed. So this checks the shape GitHub actually
# requires rather than validating YAML in general: the required keys, a known
# field type, a label on every field a human fills in, unique ids, and no tab
# indentation. It cannot catch every malformation - it is a floor, not a parser.
Check 'every GitHub issue form has the shape GitHub requires' {
    $tplDir = Join-Path $Root '.github\ISSUE_TEMPLATE'
    if (-not (Test-Path -LiteralPath $tplDir)) { return }

    foreach ($f in (Get-ChildItem -LiteralPath $tplDir -Filter *.yml)) {
        $lines = @(Get-Content -LiteralPath $f.FullName)
        $text  = $lines -join "`n"
        $rel   = ".github/ISSUE_TEMPLATE/$($f.Name)"

        # A tab used as indentation makes YAML invalid outright, and an editor
        # can insert one without it being visible in a diff.
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "^ *`t") { "${rel}: line $($i + 1) is indented with a tab, which YAML forbids" }
        }

        # config.yml is the chooser page, not a form, and has its own schema.
        if ($f.Name -eq 'config.yml') {
            if ($text -notmatch '(?m)^blank_issues_enabled:\s*(true|false)\s*$') {
                "${rel}: no blank_issues_enabled: true/false"
            }
            # Entries are split by line index rather than by regex: the name
            # lives on the `- name:` line that STARTS each entry, so a pattern
            # looking for `^\s*name:` inside a block never finds it and reports
            # every well-formed link as nameless. (It did.)
            $starts = @()
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '^\s*-\s+name\s*:') { $starts += $i }
            }
            if (-not $starts.Count) { "${rel}: contact_links has no entries" }
            for ($j = 0; $j -lt $starts.Count; $j++) {
                $from  = $starts[$j]
                $to    = if ($j + 1 -lt $starts.Count) { $starts[$j + 1] - 1 } else { $lines.Count - 1 }
                $block = ($lines[$from..$to]) -join "`n"
                # GitHub drops a contact link missing any of the three, without
                # saying which one, or that it did.
                if ($block -notmatch '^\s*-\s+name\s*:\s*\S') { "${rel}: a contact link has no name" }
                foreach ($k in 'url', 'about') {
                    if ($block -notmatch "(?m)^\s*$k\s*:\s*\S") { "${rel}: a contact link has no $k" }
                }
                if ($block -notmatch '(?m)^\s*url\s*:\s*https?://') { "${rel}: a contact link url is not absolute" }
            }
            continue
        }

        foreach ($k in 'name', 'description', 'body') {
            if ($text -notmatch "(?m)^$k\s*:\s*\S") { "${rel}: no top-level ${k}:" }
        }

        $known = @('markdown', 'input', 'textarea', 'dropdown', 'checkboxes')
        $items = [regex]::Matches($text, '(?ms)^  - type:\s*(\S+).*?(?=^  - type:|\z)')
        if (-not $items.Count) { "${rel}: body has no '- type:' fields" }

        $seenIds = @{}
        foreach ($m in $items) {
            $type  = $m.Groups[1].Value
            $block = $m.Value
            if ($known -notcontains $type) { "${rel}: unknown field type '$type'"; continue }

            if ($block -notmatch '(?m)^\s+attributes:\s*$') { "${rel}: a '$type' field has no attributes: block" }

            if ($type -eq 'markdown') {
                if ($block -notmatch '(?m)^\s+value:') { "${rel}: a markdown block has no value:" }
            } elseif ($block -notmatch '(?m)^\s+label:\s*\S') {
                # The failure this is really for: a field with no label renders as
                # an unexplained empty box, and people leave it blank.
                "${rel}: a '$type' field has no label"
            }

            if (@('dropdown', 'checkboxes') -contains $type -and $block -notmatch '(?m)^\s+options:') {
                "${rel}: a '$type' field has no options:"
            }

            if ($block -match '(?m)^\s+id:\s*(\S+)') {
                $id = $matches[1]
                if ($seenIds.ContainsKey($id)) { "${rel}: duplicate field id '$id' - GitHub rejects the whole form" }
                $seenIds[$id] = $true
            }
        }
    }
}

# ----------------------------------------------------------------- privacy --

# This repo is public, and personal mod names and absolute user paths have leaked
# into it by accident before.
Check 'no absolute user or library paths are hardcoded' {
    $patterns = @(
        'C:\\Users\\[A-Za-z0-9._-]+\\'
        'C:\\Games\\'
        '/home/[a-z0-9._-]+/'
    )
    foreach ($f in (Get-ChildItem -LiteralPath $Root -Include *.ps1,*.md -Recurse -File | Where-Object { $_.FullName -notmatch '\\\.git\\' })) {
        $text = Get-Content -LiteralPath $f.FullName -Raw
        foreach ($p in $patterns) {
            foreach ($m in [regex]::Matches($text, $p)) {
                # A placeholder is fine; a real one is not.
                if ($m.Value -match '<|USERNAME|user>|example') { continue }
                "$($f.Name): $($m.Value)"
            }
        }
    }
}

# ------------------------------------------------------------------ report --

Write-Host ''
if ($script:fail) {
    Write-Host "$($script:pass) passed, $($script:fail) FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "$($script:pass) passed, 0 failed" -ForegroundColor Green
exit 0
