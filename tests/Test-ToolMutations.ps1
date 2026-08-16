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

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$tmp  = Join-Path ([IO.Path]::GetTempPath()) ("cw-mutate-" + [guid]::NewGuid().ToString('N').Substring(0,8))

New-Item -ItemType Directory -Path $tmp -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'skills') -Destination $tmp -Recurse -Force
Copy-Item -LiteralPath (Join-Path $repo 'tests')  -Destination $tmp -Recurse -Force

$suite = Join-Path $tmp 'tests\Test-Tools.ps1'

function Invoke-Suite {
    # A FRESH PROCESS EACH TIME, and this is not optional. Expand-Save.ps1 compiles
    # its LZ4 decoder with Add-Type, and a compiled type cannot be replaced once
    # loaded - so an in-process re-run silently keeps the FIRST version's decoder.
    # Running the baseline and then a mutated copy in one session made the LZ4
    # mutation appear undetectable when the test detects it perfectly well.
    # -Quick drops the headless-browser checks: no mutation here can reach them,
    # and this function runs nine times.
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
$hotkeyRel  = 'skills\cyberwise-hotkeys\tools\Get-Hotkeys.ps1'
Save-Original $profileRel
Save-Original $saveRel
Save-Original $presetRel
Save-Original $hotkeyRel

function Assert-Detects {
    param([string]$Name, [string]$Rel, [string]$From, [string]$To, [string]$Expect)

    $path = Join-Path $tmp $Rel
    $text = Get-Content -LiteralPath $path -Raw
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

Assert-Detects "user.ini overrides ignored, so shipped defaults are reported as the user's" $hotkeyRel `
    'if ($ov -and $overrides.ContainsKey($ov)) {' `
    'if ($false -and $ov -and $overrides.ContainsKey($ov)) {' `
    "rebind beats the mod's shipped default"

Assert-Detects 'bindings.json parsed without -AsHashtable, which throws on case-colliding keys' $hotkeyRel `
    'ConvertFrom-Json -AsHashtable' `
    'ConvertFrom-Json' `
    'case-colliding bindings.json'

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
