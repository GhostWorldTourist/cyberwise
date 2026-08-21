# New-CharacterSite.ps1 -- a website from a folder of character documents.
#
#     .\New-CharacterSite.ps1 -From <characters folder> -Out <site folder> -Open
#
# WHAT IT IS FOR
#
# Somebody has written their V. It is sitting in a Markdown file nobody will ever
# read, because "read this .md" is a thing you can only ask of other developers.
# This turns the folder into a website: plain HTML, CSS and one small script, no
# build step, no runtime, no account. Copy the output folder anywhere, or
# double-click index.html.
#
# THE ARCHITECTURE IS CSS ZEN GARDEN, AND THAT IS THE WHOLE POINT.
#
# Every character page emits the SAME semantic markup - eyebrow, h1, subhead,
# content, meta, footer - and a per-character stylesheet owns everything about
# how it looks. Not a palette swap: a different world. The Arasaka dossier is
# gold leaf on a kill order, all rigid rules and classification bands. The
# monologue is wet, green, and never quite sits straight. The nomad legend is
# dust and firelight with torn edges. The AI transcript is a terminal that
# discusses a person the same way it would discuss disk usage.
#
# A theme is one CSS file in themes\. Copy default.css, rename it after the
# character, and it is a theme. That is the extension point, and it is why this
# tool does not generate CSS: generated CSS is CSS nobody can edit.
#
# WHY A CHARACTER MUST NOT BE FLATTENED INTO A TEMPLATE
#
# These documents are not four copies of one form - the format IS the
# characterisation. A builder that extracted Name / Lifepath / Backstory into
# fields would make all four the same shape, which is the one outcome that makes
# the site worse than the files it was built from.
#
# WHAT IT READS
#
#   characters\valkyrie\Profile - Valkyrie.md    the document (required)
#   characters\valkyrie\Meta - Valkyrie.md       optional second section
#   characters\valkyrie\media\*.jpg|png|webp     optional images
#   characters\valkyrie\theme.txt                optional theme name
#
# Anything else is ignored, so presets and working notes can live beside the
# document without being published. A folder starting with _ is a draft.

[CmdletBinding()]
param(
    [string] $From = (Join-Path (Get-Location) 'characters'),
    [string] $Out = (Join-Path (Get-Location) 'site'),

    [string] $Title = 'V of Night City',

    # The line under the title. It is a question rather than a description on
    # purpose - a subtitle that explains the site turns it into a brochure.
    [string] $Standing = 'Which side of the Blackwall are we on right now?',

    [switch] $Open,
    [switch] $IncludeDrafts,

    # Where the stylesheets live. Point this somewhere else to ship your own set.
    [string] $ThemeDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'themes')
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'ConvertFrom-Markdown.ps1')

if (-not (Test-Path -LiteralPath $From)) { throw "No such folder: $From" }
if (-not (Test-Path -LiteralPath $ThemeDir)) { throw "No themes folder: $ThemeDir" }

function Get-Slug {
    param([string] $Text)
    $s = ($Text -replace '[^\w\s-]', '' -replace '\s+', '-').ToLower().Trim('-')
    if (-not $s) { $s = 'page' }
    return $s
}
function Get-Esc { param([string] $s) ($s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;') }

# ------------------------------------------------------------------ gather ---

$chars = New-Object System.Collections.Generic.List[object]

foreach ($dir in (Get-ChildItem -LiteralPath $From -Directory | Sort-Object Name)) {
    if ($dir.Name.StartsWith('_') -and -not $IncludeDrafts) { continue }

    # "Profile - X.md" by convention, but a folder holding exactly one Markdown
    # file works without it. A convention nobody was told about is a trap.
    $doc = @(Get-ChildItem -LiteralPath $dir.FullName -Filter 'Profile*.md' -File) | Select-Object -First 1
    if (-not $doc) {
        $mds = @(Get-ChildItem -LiteralPath $dir.FullName -Filter '*.md' -File |
                 Where-Object { $_.Name -notlike 'Meta*' })
        if ($mds.Count -eq 1) { $doc = $mds[0] }
    }
    if (-not $doc) { Write-Warning "$($dir.Name): no profile document found, skipped"; continue }

    $meta = @(Get-ChildItem -LiteralPath $dir.FullName -Filter 'Meta*.md' -File) | Select-Object -First 1

    $media = @()
    $mediaDir = Join-Path $dir.FullName 'media'
    if (Test-Path -LiteralPath $mediaDir) {
        $media = @(Get-ChildItem -LiteralPath $mediaDir -File |
                   Where-Object { $_.Extension -match '(?i)^\.(jpe?g|png|webp|gif|avif)$' } | Sort-Object Name)
    }

    $slug = Get-Slug $dir.Name

    # Theme, in order: an explicit theme.txt, a stylesheet named after the
    # character, then default. Naming the file after the character means adding
    # a theme needs no configuration at all.
    $themeFile = Join-Path $dir.FullName 'theme.txt'
    $theme = if (Test-Path -LiteralPath $themeFile) {
        (Get-Content -LiteralPath $themeFile -Raw).Trim()
    } elseif (Test-Path -LiteralPath (Join-Path $ThemeDir "$slug.css")) {
        $slug
    } else {
        'default'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $ThemeDir "$theme.css"))) {
        Write-Warning "$($dir.Name): no theme '$theme' in $ThemeDir - using default"
        $theme = 'default'
    }

    $raw = Get-Content -LiteralPath $doc.FullName -Raw
    $lines = ($raw -replace "`r`n", "`n") -split "`n"

    # The document's own H1. It is usually NOT the character's name - "Too Bad,
    # Too Bad", "Campfire Myth", a case number - and that is the useful thing to
    # show, because it says what kind of document this is before it is opened.
    $docTitle = ($lines | Where-Object { $_ -match '^#\s+\S' } | Select-Object -First 1) -replace '^#\s+', ''
    if (-not $docTitle) { $docTitle = $dir.Name }

    # The line under the title, and ONLY when the document opens with a header
    # block - a run of LABEL: lines, the way a file or a report does.
    #
    # Taking "the first two lines" unconditionally reprinted the opening
    # paragraph of a prose document immediately above that same paragraph, and
    # on the transcript it reprinted two machine states that the body renders as
    # blocks a centimetre lower. A document that opens by simply starting does
    # not get a subhead, because it does not have one.
    $head = @()
    foreach ($l in ($lines | Select-Object -First 14)) {
        if (-not $l.Trim()) { if ($head.Count) { break } else { continue } }
        if ($l -match '^#') { continue }
        if ($l -cmatch '^[A-Z][A-Z0-9 .,/&()''"-]{0,60}:') { $head += $l.Trim() } else { break }
    }
    $subhead = ''
    if ($head.Count -ge 3) {
        $subhead = ((@($head | Select-Object -First 2) -join '  //  ') -replace '\*', '').Trim()
        if ($subhead.Length -gt 210) { $subhead = $subhead.Substring(0, 207).TrimEnd() + '...' }
    }

    # A line for the directory. Long enough to be a sentence, or the first line
    # of any kind when the document has none.
    $cand = @($lines | Select-Object -First 40 | Where-Object {
        $_.Trim() -and $_ -notmatch '^#' -and $_ -notmatch '^[-*|>]'
    })
    $lead = @($cand | Where-Object { $_.Trim().Length -ge 70 } | Select-Object -First 1)
    if (-not $lead) { $lead = @($cand | Select-Object -First 1) }
    $lead = (($lead | Select-Object -First 1) -replace '\*', '').Trim()
    if ($lead.Length -gt 190) { $lead = $lead.Substring(0, 187).TrimEnd() + '...' }

    # THE DOCUMENT'S OWN H1 BECOMES THE PAGE HEADLINE, so it must not also open
    # the body - every page printed its title twice, once in the theme's display
    # face and again as an ordinary heading a few centimetres below it.
    #
    # Done by index rather than by regex: the pattern has to eat the heading AND
    # the blank line under it, and a multi-line pattern here is one escaping
    # mistake away from silently matching nothing.
    $bodyLines = [System.Collections.Generic.List[string]] $lines
    for ($li = 0; $li -lt $bodyLines.Count; $li++) {
        if ($bodyLines[$li] -match '^#\s+\S') {
            $bodyLines.RemoveAt($li)
            while ($li -lt $bodyLines.Count -and -not $bodyLines[$li].Trim()) { $bodyLines.RemoveAt($li) }
            break
        }
    }

    $chars.Add([pscustomobject]@{
        Name      = (Get-Culture).TextInfo.ToTitleCase($dir.Name)
        Slug      = $slug
        Theme     = $theme
        DocTitle  = $docTitle
        Subhead   = $subhead
        Lead      = $lead
        Body      = ConvertTo-Html -Markdown ($bodyLines -join "`n")
        MetaBody  = if ($meta) { ConvertTo-Html -Markdown (Get-Content -LiteralPath $meta.FullName -Raw) } else { $null }
        MetaTitle = if ($meta) { ($meta.BaseName -replace '^Meta\s*-\s*', '') } else { $null }
        Media     = $media
        Words     = @(($raw -split '\s+') | Where-Object { $_ }).Count
    })
}

if (-not $chars.Count) { throw "No characters found under $From. Each character is a subfolder with a Profile*.md in it." }

Write-Host ''
Write-Host "$($chars.Count) character(s):" -ForegroundColor Cyan
foreach ($c in $chars) {
    $m = if ($c.Media.Count) { "$($c.Media.Count) image(s)" } else { 'no media' }
    Write-Host ("  {0,-13} theme:{1,-12} {2,6} words, {3}" -f $c.Name, $c.Theme, $c.Words, $m) -ForegroundColor DarkGray
}

# ------------------------------------------------------------------- write ---

if (-not (Test-Path -LiteralPath $Out)) { New-Item -ItemType Directory -Path $Out -Force | Out-Null }
$themeOut = Join-Path $Out 'themes'
if (-not (Test-Path -LiteralPath $themeOut)) { New-Item -ItemType Directory -Path $themeOut -Force | Out-Null }

foreach ($sheet in (@('_base', 'index') + @($chars.Theme) | Select-Object -Unique)) {
    $src = Join-Path $ThemeDir "$sheet.css"
    if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $themeOut "$sheet.css") -Force }
}

$stamp = Get-Date -Format 'yyyy-MM-dd'

Set-Content -LiteralPath (Join-Path $Out 'site.js') -Encoding UTF8 -Value @'
// Nothing here fetches. The site has to work opened straight off the
// filesystem, where the browser blocks fetch() from a file:// origin - and
// that is also why it carries no tracking: there is nowhere for it to phone.

var box = document.getElementById('filter');
if (box) {
  box.addEventListener('input', function () {
    var q = box.value.toLowerCase();
    document.querySelectorAll('.file').forEach(function (row) {
      row.style.display = row.innerText.toLowerCase().indexOf(q) === -1 ? 'none' : '';
    });
  });
}

var lb = document.querySelector('.lightbox');
if (lb) {
  document.querySelectorAll('.gallery img').forEach(function (img) {
    img.addEventListener('click', function () {
      lb.querySelector('img').src = img.src;
      lb.classList.add('on');
    });
  });
  lb.addEventListener('click', function () { lb.classList.remove('on'); });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') { lb.classList.remove('on'); }
  });
}
'@

function Write-Page {
    param(
        [string] $File, [string] $PageTitle, [string] $Theme,
        [string] $BodyClass, [string] $Crumb, [string] $Body, [string] $Extra = ''
    )
    $doc = @"
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$(Get-Esc $PageTitle)</title>
<link rel="stylesheet" href="themes/_base.css">
<link rel="stylesheet" href="themes/$Theme.css">
</head><body class="$BodyClass">
<a class="skip" href="#doc">Skip to the document</a>
<div class="top">
  <a class="home" href="index.html">$(Get-Esc $Title)</a>
  <span class="crumb">$(Get-Esc $Crumb)</span>
  <span class="spacer"></span>
  $Extra
</div>
$Body
<script src="site.js"></script>
</body></html>
"@
    Set-Content -LiteralPath (Join-Path $Out $File) -Value $doc -Encoding UTF8
}

# ---- one page per character, all with identical markup ----
foreach ($c in $chars) {
    $gallery = ''
    if ($c.Media.Count) {
        $mediaOut = Join-Path $Out "media\$($c.Slug)"
        New-Item -ItemType Directory -Path $mediaOut -Force | Out-Null
        $imgs = foreach ($m in $c.Media) {
            Copy-Item -LiteralPath $m.FullName -Destination (Join-Path $mediaOut $m.Name) -Force
            "<img src=""media/$($c.Slug)/$([uri]::EscapeDataString($m.Name))"" alt=""$(Get-Esc $c.Name)"" loading=""lazy"">"
        }
        $gallery = "<div class=""gallery"">$($imgs -join '')</div>"
    }

    $metaSection = ''
    if ($c.MetaBody) {
        $metaSection = "<section class=""meta""><h2><span>$(Get-Esc $c.MetaTitle)</span></h2>$($c.MetaBody)</section>"
    }

    # data-title carries the headline to the theme, which prints it a second time
    # underneath, a few pixels off - a plate out of register on a failing press.
    $body = @"
<main class="doc" id="doc">
  <p class="eyebrow">$(Get-Esc $c.Name)</p>
  <h1 data-title="$(Get-Esc $c.DocTitle)">$(Get-Esc $c.DocTitle)</h1>
  <p class="subhead">$(Get-Esc $c.Subhead)</p>
  $gallery
  <div class="content">
$($c.Body)
  </div>
  $metaSection
  <footer>$($c.Words) words &middot; built $stamp</footer>
</main>
<div class="lightbox"><img alt=""></div>
"@
    Write-Page -File "$($c.Slug).html" -PageTitle "$($c.Name) - $($c.DocTitle)" -Theme $c.Theme `
               -BodyClass "page-doc is-$($c.Slug)" -Crumb $c.Name -Body $body
}

# ---- the directory ----
$n = 0
$rows = foreach ($c in $chars) {
    $n++
    @"
  <li class="file is-$($c.Slug)">
    <a href="$($c.Slug).html">
      <span class="idx">$('{0:00}' -f $n)</span>
      <span class="name">$(Get-Esc $c.Name)<span class="doctitle">$(Get-Esc $c.DocTitle)</span></span>
      <span class="lead">$(Get-Esc $c.Lead)<span class="stat">$('{0:N0}' -f $c.Words) words</span></span>
    </a>
  </li>
"@
}

$indexBody = @"
<span class="ghost" aria-hidden="true">V</span>
<main class="hub" id="doc">
  <h1 class="wordmark"><span data-t="$(Get-Esc $Title)">$(Get-Esc $Title)</span></h1>
  <p class="standing">$(Get-Esc $Standing)</p>
  <p class="count">$($chars.Count) files &middot; built $stamp</p>
  <ol class="files">
$($rows -join "`n")
  </ol>
  <footer>Held locally. Nothing here is loaded from anywhere else.</footer>
</main>
"@
Write-Page -File 'index.html' -PageTitle $Title -Theme 'index' -BodyClass 'page-index' -Crumb '' `
           -Body $indexBody -Extra '<input id="filter" type="search" placeholder="filter" aria-label="filter files">'

Write-Host ''
Write-Host "site written to $((Resolve-Path -LiteralPath $Out).Path)" -ForegroundColor Green
Write-Host "  open index.html, or copy the whole folder to any web host" -ForegroundColor DarkGray

if ($Open) { Start-Process (Join-Path $Out 'index.html') }
exit 0
