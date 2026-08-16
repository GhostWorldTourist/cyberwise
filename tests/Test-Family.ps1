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
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

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

Check 'every tools/*.ps1 a SKILL.md names resolves inside that skill' {
    foreach ($s in $withMd) {
        $md = Get-Content -LiteralPath (Join-Path $s.FullName 'SKILL.md') -Raw
        foreach ($m in [regex]::Matches($md, '(tools[\\/][A-Za-z0-9._-]+\.ps1)')) {
            $rel = $m.Groups[1].Value -replace '\\','/'
            if (-not (Test-Path -LiteralPath (Join-Path $s.FullName $rel))) { "$($s.Name) -> $rel does not exist" }
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

# ------------------------------------------------------------------- tools --

Check 'every shipped .ps1 parses' {
    foreach ($f in (Get-ChildItem -LiteralPath $Root -Filter *.ps1 -Recurse)) {
        $errs = $null
        [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs) | Out-Null
        if ($errs) { "$($f.Name): $($errs[0].Message)" }
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
