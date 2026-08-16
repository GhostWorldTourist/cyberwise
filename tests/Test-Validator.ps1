# Test-Validator.ps1 -- proves Test-Family.ps1 can actually fail.
#
#     .\tests\Test-Validator.ps1
#
# A validator that has only ever returned green is indistinguishable from one
# that returns green unconditionally. This copies the family to a temp directory,
# injects one real fault at a time, and asserts that THE CHECK THAT SHOULD CATCH
# IT is the one that reports - not merely that the exit code went non-zero, which
# a fault can trip by accident through an unrelated check.
#
# It also asserts the clean copy passes, both before the run and after every
# restore, so a validator that fails on everything is caught too.
#
# The faults are real ones: the dangling reference is the bug the family split
# actually produced, and the hardcoded user path is the leak the generalization
# audit found.
#
# NOTE ON WRITING THIS FILE: it lives inside the tree the validator scans, so a
# literal user path here - `C:\Users\<name>\` in placeholder form - would trip the
# privacy check on the clean copy and make every result below meaningless. The
# path fault is assembled from fragments at runtime for exactly that reason, and
# this comment uses the angle-bracket form the check deliberately allows.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repo      = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $PSScriptRoot 'Test-Family.ps1'
$tmp       = Join-Path ([IO.Path]::GetTempPath()) ("cw-validator-" + [guid]::NewGuid().ToString('N').Substring(0,8))

New-Item -ItemType Directory -Path $tmp -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'skills') -Destination $tmp -Recurse -Force

function Invoke-Validator {
    # 6>&1 is load-bearing: the validator reports with Write-Host, which writes to
    # the INFORMATION stream, not stdout. Capturing only 2>&1 yields an empty
    # string, and then every "did the right check fire?" assertion below silently
    # fails no matter what the validator actually printed.
    $out = & $validator -Root $tmp 6>&1 2>&1 | Out-String
    [pscustomobject]@{ Code = $LASTEXITCODE; Text = $out }
}

$script:pass = 0
$script:fail = 0

# $Expect is a distinctive fragment of the check's name, so this asserts the
# right check fired rather than just "something did".
function Assert-Catches {
    param(
        [string]      $Name,
        [string]      $Expect,
        [scriptblock] $Break,
        [scriptblock] $Restore
    )
    & $Break
    $broken = Invoke-Validator
    & $Restore
    $healed = Invoke-Validator

    $caught  = $broken.Code -ne 0
    $right   = $broken.Text -match "FAIL.*$([regex]::Escape($Expect))"
    $clean   = $healed.Code -eq 0

    if ($caught -and $right -and $clean) {
        $script:pass++
        Write-Host "ok    catches: $Name" -ForegroundColor DarkGreen
        return
    }
    $script:fail++
    Write-Host "FAIL  $Name" -ForegroundColor Red
    if (-not $caught)     { Write-Host "        the fault was injected and the validator still passed" -ForegroundColor DarkRed }
    elseif (-not $right)  { Write-Host "        it failed, but not on the check that should own this: expected '$Expect'" -ForegroundColor DarkRed }
    if (-not $clean)      { Write-Host "        the restore did not put the tree back - later results are unreliable" -ForegroundColor DarkRed }
}

$S = Join-Path $tmp 'skills'

Write-Host "fault injection against a copy at $tmp`n"

$base = Invoke-Validator
if ($base.Code -ne 0) {
    Write-Host 'FAIL  the clean copy does not pass - nothing below would be meaningful' -ForegroundColor Red
    Write-Host $base.Text
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}
$script:pass++
Write-Host "ok    the clean copy passes`n" -ForegroundColor DarkGreen

# -- the bug the split actually produced ------------------------------------
$ref = Join-Path $S 'cyberwise-conflicts\references\load-order.md'
Assert-Catches 'a reference a SKILL.md names but that does not exist' 'references/*.md' `
    { Rename-Item -LiteralPath $ref -NewName 'load-order.parked' } `
    { Rename-Item -LiteralPath (Join-Path (Split-Path $ref) 'load-order.parked') -NewName 'load-order.md' }

# -- frontmatter -------------------------------------------------------------
$sk     = Join-Path $S 'cyberwise-saves\SKILL.md'
$skOrig = Get-Content -LiteralPath $sk -Raw

Assert-Catches 'frontmatter name that no longer matches its directory' 'name matches the directory' `
    { $skOrig.Replace('name: cyberwise-saves', 'name: cyberwise-savegames') | Set-Content -LiteralPath $sk -NoNewline } `
    { $skOrig | Set-Content -LiteralPath $sk -NoNewline }

Assert-Catches 'a description too short to fire reliably' 'description is present' `
    { $skOrig -replace '(?m)^description:.*$', 'description: saves' | Set-Content -LiteralPath $sk -NoNewline } `
    { $skOrig | Set-Content -LiteralPath $sk -NoNewline }

# -- routing -----------------------------------------------------------------
$front     = Join-Path $S 'cyberwise\SKILL.md'
$frontOrig = Get-Content -LiteralPath $front -Raw

Assert-Catches 'the front door routing to a skill that does not exist' 'front door routes to' `
    { ($frontOrig + "`n| ``cyberwise-textures`` | retexture work |`n") | Set-Content -LiteralPath $front -NoNewline } `
    { $frontOrig | Set-Content -LiteralPath $front -NoNewline }

# Drop every mention rather than renaming one: a rename would ALSO trip the
# route check above, and then this test would pass without proving anything.
Assert-Catches 'a topic skill the front door never mentions' 'reachable from the front door' `
    { (($frontOrig -split "`r?`n" | Where-Object { $_ -notmatch 'cyberwise-reshade' }) -join "`n") | Set-Content -LiteralPath $front -NoNewline } `
    { $frontOrig | Set-Content -LiteralPath $front -NoNewline }

# -- provenance --------------------------------------------------------------
$rs     = Join-Path $S 'cyberwise-reshade\references\reshade.md'
$rsOrig = Get-Content -LiteralPath $rs -Raw

Assert-Catches 'a reference with no Verified/Re-check stamp' 'Verified + Re-check' `
    { $rsOrig -replace '(?m)^> \*\*Verified:.*$', '' | Set-Content -LiteralPath $rs -NoNewline } `
    { $rsOrig | Set-Content -LiteralPath $rs -NoNewline }

# -- tools -------------------------------------------------------------------
$ps     = Join-Path $S 'cyberwise-reports\tools\Measure-PageFit.ps1'
$psOrig = Get-Content -LiteralPath $ps -Raw

Assert-Catches 'a .ps1 that no longer parses' 'parses' `
    { ($psOrig + "`nfunction Broken { if (`$x -eq ) { } }`n") | Set-Content -LiteralPath $ps -NoNewline } `
    { $psOrig | Set-Content -LiteralPath $ps -NoNewline }

# -- privacy -----------------------------------------------------------------
# Assembled at runtime; see the note at the top of this file.
$leak = 'C:' + '\Users\' + 'someone' + '\repos\thing'
Assert-Catches 'a hardcoded absolute user path' 'no absolute user' `
    { ($frontOrig + "`nRun it from $leak.`n") | Set-Content -LiteralPath $front -NoNewline } `
    { $frontOrig | Set-Content -LiteralPath $front -NoNewline }

# -- safe edits ---------------------------------------------------------------
# The regression that matters: somebody tidies the "snapshot before you write"
# paragraph out of a skill that tells the model to rewrite modlist.txt, and the
# only thing standing between a user and an unrecoverable edit disappears
# quietly. Reference files are read in isolation, so a rule stated only in the
# front door is not protection.
$conf     = Join-Path $S 'cyberwise-conflicts\SKILL.md'
$confOrig = Get-Content -LiteralPath $conf -Raw

Assert-Catches 'a skill that rewrites a game file with the backup advice removed' 'backup helper' `
    { (($confOrig -split "`r?`n" | Where-Object { $_ -notmatch 'ModFileBackup|Set-ModFileContent|Restore-ModFile' }) -join "`n") |
        Set-Content -LiteralPath $conf -NoNewline } `
    { $confOrig | Set-Content -LiteralPath $conf -NoNewline }

# -- codex --------------------------------------------------------------------
$yaml     = Join-Path $S 'cyberwise-hotkeys\agents\openai.yaml'
$yamlOrig = Get-Content -LiteralPath $yaml -Raw

Assert-Catches 'a skill with no Codex manifest' 'Codex manifest' `
    { Rename-Item -LiteralPath $yaml -NewName 'openai.parked' } `
    { Rename-Item -LiteralPath (Join-Path (Split-Path $yaml) 'openai.parked') -NewName 'openai.yaml' }

# A copy-pasted manifest that kept another skill's name points Codex elsewhere,
# which is worse than a missing one: it looks correct and routes wrong.
Assert-Catches 'a Codex manifest whose default_prompt names another skill' 'Codex manifest' `
    { $yamlOrig.Replace('$cyberwise-hotkeys', '$cyberwise-saves') | Set-Content -LiteralPath $yaml -NoNewline } `
    { $yamlOrig | Set-Content -LiteralPath $yaml -NoNewline }

# -- structure ---------------------------------------------------------------
$doomed     = Join-Path $S 'cyberwise-tweaks\SKILL.md'
$doomedOrig = Get-Content -LiteralPath $doomed -Raw

Assert-Catches 'a skill directory with no SKILL.md at all' 'has a SKILL.md' `
    { Remove-Item -LiteralPath $doomed -Force } `
    { $doomedOrig | Set-Content -LiteralPath $doomed -NoNewline }

# ----------------------------------------------------------------------------
Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($script:fail) {
    Write-Host "$($script:pass) passed, $($script:fail) FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "$($script:pass) passed, 0 failed - every check detects the fault it owns" -ForegroundColor Green
exit 0
