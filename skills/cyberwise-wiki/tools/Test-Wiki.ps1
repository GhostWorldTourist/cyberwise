# Test-Wiki.ps1 -- does this bundle conform to OKF 0.2, and does it respect the
# distribution boundary?
#
#     .\Test-Wiki.ps1 -Bundle '<path>'
#     .\Test-Wiki.ps1 -Bundle '<path>' -Base      # also enforce "nothing user-only here"
#     .\Test-Wiki.ps1 -Bundle '<path>' -Json
#
# TWO JOBS, AND THE SECOND IS THE IMPORTANT ONE.
#
# OKF conformance is forgiving by design: a consumer MUST NOT reject a bundle for
# a missing optional field, an unknown type, an unknown extra key, a broken
# cross-link or an absent index. So most of what this checks is the small
# mandatory core - frontmatter parses, type is present, index.md and log.md keep
# their shapes. Being strict here would violate the spec, not enforce it.
#
# The second job has no counterpart in the spec and matters more here. The base
# wiki SHIPS. The user wiki does NOT, ever: it is derived from mod authors' own
# descriptions, configs and pages, and redistributing that is harvesting somebody
# else's work. Location is the boundary - base lives in the repo, user lives
# beside the game's own data - and -Base turns that boundary into a test rather
# than an intention. An intention gets forgotten; a failing check does not.

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Bundle,
    [switch] $Base,
    [switch] $Json
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Bundle)) { throw "no such bundle: $Bundle" }

# Resolve before measuring. Relative paths are the normal way to invoke this
# (-Bundle .\wiki), and FullName is always absolute - subtracting the length of
# a relative path from an absolute one silently produces a mangled prefix, which
# then shows up in every reported filename instead of failing outright.
$Bundle = (Resolve-Path -LiteralPath $Bundle).ProviderPath.TrimEnd('\', '/')

$problems = New-Object System.Collections.Generic.List[object]
function Add-Problem([string] $file, [string] $rule, [string] $detail) {
    $problems.Add([pscustomobject]@{ File = $file; Rule = $rule; Detail = $detail })
}

# The smallest frontmatter reader that answers the questions asked. Deliberately
# NOT a YAML parser: it reads the shapes OKF actually uses - scalars, one level
# of mapping, lists of scalars - and returns null for anything it cannot read,
# rather than guessing. A wrong parse that reports success is worse than no
# parser at all, because it would certify a broken bundle as conformant.
function Read-Frontmatter([string] $text) {
    if ($text -notmatch "^---\r?\n") { return $null }
    $lines = $text -split "\r?\n"
    $end = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq '---') { $end = $i; break }
    }
    if ($end -lt 0) { return $null }

    $fm = @{}
    $currentKey = $null
    $dq = [char]34
    $sq = [char]39
    for ($i = 1; $i -lt $end; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*$' -or $line -match '^\s*#') { continue }
        if ($line -match '^(\S[^:]*):\s*(.*)$') {
            $currentKey = $Matches[1].Trim()
            $val = $Matches[2].Trim()
            if ($val -eq '') { $fm[$currentKey] = @() }
            # An inline flow mapping - generated: { by: x, at: y } - is the form
            # the spec's own examples use, so a parser that treats it as a scalar
            # reports "generated requires by" on a document that has one. Flatten
            # it to the same dotted keys the block form produces.
            elseif ($val -match '^\{(.*)\}$') {
                $fm[$currentKey] = $val
                foreach ($pair in ($Matches[1] -split ',')) {
                    if ($pair -match '^\s*([^:]+):\s*(.*)$') {
                        $fm[($currentKey + '.' + $Matches[1].Trim())] = $Matches[2].Trim().Trim($dq).Trim($sq)
                    }
                }
            }
            else { $fm[$currentKey] = $val.Trim($dq).Trim($sq) }
        }
        elseif ($currentKey -and $line -match '^\s+-\s*(.*)$') {
            if ($fm[$currentKey] -isnot [array]) { $fm[$currentKey] = @() }
            $fm[$currentKey] += $Matches[1].Trim()
        }
        elseif ($currentKey -and $line -match '^\s+(\S[^:]*):\s*(.*)$') {
            $fm[($currentKey + '.' + $Matches[1].Trim())] = $Matches[2].Trim().Trim($dq).Trim($sq)
        }
    }
    return $fm
}

$isoUtc = '^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2})?(\.\d+)?(Z|[+-]\d{2}:?\d{2}))?$'
$userOnlyTypes = @('Mod Reference', 'Mod Settings', 'Mod Description')

$files = @(Get-ChildItem -LiteralPath $Bundle -Filter *.md -Recurse -File)
$concepts = 0

foreach ($f in $files) {
    $rel = ($f.FullName.Substring($Bundle.Length).TrimStart('\', '/')) -replace '\\', '/'
    $text = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue
    if ($null -eq $text) { $text = '' }
    $name = $f.Name.ToLower()

    # --- reserved names keep their own shapes and are never concepts ----------
    if ($name -eq 'index.md') {
        if ($text -match "^---\r?\n") {
            $fm = Read-Frontmatter $text
            $keys = @($fm.Keys)
            if ($rel -ne 'index.md') {
                Add-Problem $rel 'index-frontmatter' 'only a ROOT index.md may carry frontmatter'
            }
            elseif (@($keys | Where-Object { $_ -ne 'okf_version' }).Count -gt 0) {
                Add-Problem $rel 'index-frontmatter' ('root index may only declare okf_version; found: ' + ($keys -join ', '))
            }
        }
        continue
    }

    if ($name -eq 'log.md') {
        $dates = @([regex]::Matches($text, '(?m)^#{1,6}\s+(\d{4}-\d{2}-\d{2})\s*$') | ForEach-Object { $_.Groups[1].Value })
        if ($dates.Count -eq 0 -and $text.Trim() -ne '') {
            Add-Problem $rel 'log-shape' 'log.md has content but no ISO YYYY-MM-DD headings'
        }
        for ($i = 1; $i -lt $dates.Count; $i++) {
            if ([datetime]$dates[$i] -gt [datetime]$dates[$i - 1]) {
                Add-Problem $rel 'log-order' ('entries must be newest first: ' + $dates[$i] + ' appears after ' + $dates[$i - 1])
                break
            }
        }
        continue
    }

    # --- everything else is a concept -----------------------------------------
    $concepts++
    $fm = Read-Frontmatter $text
    if ($null -eq $fm) {
        Add-Problem $rel 'frontmatter' 'no parseable YAML frontmatter'
        continue
    }

    if (-not $fm.ContainsKey('type') -or [string]::IsNullOrWhiteSpace([string]$fm['type'])) {
        Add-Problem $rel 'type' 'type is the one always-mandatory key, and is missing or empty'
    }

    if ($fm.ContainsKey('status')) {
        $s = [string]$fm['status']
        if (@('draft', 'stable', 'deprecated') -notcontains $s) {
            Add-Problem $rel 'status' ('status must be draft, stable or deprecated - found ' + $s)
        }
    }

    foreach ($k in @('stale_after', 'generated.at')) {
        if ($fm.ContainsKey($k) -and ([string]$fm[$k]) -notmatch $isoUtc) {
            Add-Problem $rel 'timestamp' ($k + ' must be ISO 8601 with an explicit UTC offset - found ' + $fm[$k])
        }
    }

    if (@($fm.Keys | Where-Object { $_ -like 'generated*' }).Count -gt 0 -and -not $fm.ContainsKey('generated.by')) {
        Add-Problem $rel 'generated' 'generated requires by'
    }

    # Footnote labels are keyed to sources[].id rather than positional, because a
    # positional index misattributes SILENTLY the moment the list is reordered.
    # So an unmatched label is a real fault, even though a broken link is not.
    $labels = @([regex]::Matches($text, '(?m)\[\^([^\]]+)\]:') | ForEach-Object { $_.Groups[1].Value })
    if ($labels.Count -gt 0) {
        $ids = @()
        foreach ($m in [regex]::Matches($text, '(?m)^\s*-?\s*id:\s*(\S+)\s*$')) {
            $ids += $m.Groups[1].Value.Trim([char]34).Trim([char]39)
        }
        foreach ($l in $labels) {
            if ($ids -notcontains $l) {
                Add-Problem $rel 'footnote' ('footnote [^' + $l + '] matches no sources[].id')
            }
        }
    }

    # --- the distribution boundary --------------------------------------------
    if ($Base) {
        if ($rel -match '^mods/') {
            Add-Problem $rel 'distribution' 'mod-specific articles are user-only and must never live in the base wiki'
        }
        $t = [string]$fm['type']
        if ($userOnlyTypes -contains $t) {
            Add-Problem $rel 'distribution' ('type ' + $t + ' is derived from a mod author own work and is user-only')
        }
        if ($fm.ContainsKey('distribution') -and ([string]$fm['distribution']) -eq 'user-only') {
            Add-Problem $rel 'distribution' 'marked user-only but present in the base wiki'
        }
    }
}

# --- report -------------------------------------------------------------------
if ($Json) {
    [pscustomobject]@{
        Bundle   = $Bundle
        Files    = $files.Count
        Concepts = $concepts
        Conforms = ($problems.Count -eq 0)
        Problems = @($problems)
    } | ConvertTo-Json -Depth 5
    exit ([int]($problems.Count -gt 0))
}

$scope = ''
if ($Base) { $scope = ', base rules enforced' }
Write-Host ('wiki: ' + $Bundle)
Write-Host ('  ' + $files.Count + ' file(s), ' + $concepts + ' concept(s)' + $scope) -ForegroundColor DarkGray

if ($problems.Count -eq 0) {
    Write-Host '  conforms to OKF 0.2' -ForegroundColor Green
    exit 0
}
foreach ($p in $problems) {
    Write-Host ('  FAIL  ' + $p.File) -ForegroundColor Red
    Write-Host ('        ' + $p.Rule + ': ' + $p.Detail) -ForegroundColor DarkGray
}
Write-Host ('  ' + $problems.Count + ' problem(s)') -ForegroundColor Red
exit 1
