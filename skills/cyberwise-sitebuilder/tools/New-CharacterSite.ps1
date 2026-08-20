# New-CharacterSite.ps1 -- a website from a folder of character documents.
#
#     .\New-CharacterSite.ps1 -From <characters folder> -Out <site folder>
#     .\New-CharacterSite.ps1 -From .\characters -Out .\site -Open
#
# WHAT IT IS FOR
#
# Somebody has written their V. It is sitting in a Markdown file nobody will ever
# read, because "read this .md" is a thing you can only ask of other developers.
# This turns the folder into a website: plain HTML, CSS and one small script,
# no build step, no runtime, no account. Copy the output folder anywhere - a web
# host, a USB stick, a Discord attachment - or double-click index.html and it
# works from the filesystem.
#
# THE ONE DESIGN RULE: DO NOT FLATTEN THE DOCUMENTS.
#
# These are not four copies of one form. On the install this was built against,
# one V is a classified Arasaka personnel dossier, one is a monologue spoken to a
# dying man, one is a journalist's interview by a campfire, one is a transcript
# of an AI being interrogated about its own records. The formats ARE the
# characterisation. So this renders each document as written and styles around
# it, rather than extracting fields into a template that would make all four the
# same shape.
#
# WHAT IT READS
#
# Every subfolder of -From is a character:
#
#   characters\valkyrie\Profile - Valkyrie.md    the document (required)
#   characters\valkyrie\Meta - Valkyrie.md       optional second section
#   characters\valkyrie\media\*.jpg|png|webp     optional images
#
# Anything else in the folder is ignored, so presets, backups and notes can live
# alongside without being published.
#
# MEDIA IS OPTIONAL AND THE PAGE MUST NOT LOOK BROKEN WITHOUT IT. The prototype
# was built for somebody who has no images yet, so a character with no media gets
# a lettered tile rather than a gap where a photo should be.

[CmdletBinding()]
param(
    # The folder whose subfolders are characters.
    [string] $From = (Join-Path (Get-Location) 'characters'),

    # Where the finished site goes. Everything needed is inside it.
    [string] $Out = (Join-Path (Get-Location) 'site'),

    [string] $Title = 'Night City Files',
    [string] $Tagline = 'Character records',

    # Open the finished index in the default browser.
    [switch] $Open,

    # Publish a document even if its folder name starts with an underscore,
    # which is otherwise the way to keep a work in progress out of the site.
    [switch] $IncludeDrafts
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'ConvertFrom-Markdown.ps1')

if (-not (Test-Path -LiteralPath $From)) { throw "No such folder: $From" }

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

    # "Profile - X.md" by convention, but fall back to the only markdown file in
    # the folder. A convention nobody was told about is a trap; a fallback that
    # picks the obvious file is not.
    $profile = @(Get-ChildItem -LiteralPath $dir.FullName -Filter 'Profile*.md' -File) |
               Select-Object -First 1
    if (-not $profile) {
        $mds = @(Get-ChildItem -LiteralPath $dir.FullName -Filter '*.md' -File |
                 Where-Object { $_.Name -notlike 'Meta*' })
        if ($mds.Count -eq 1) { $profile = $mds[0] }
    }
    if (-not $profile) {
        Write-Warning "$($dir.Name): no profile document found, skipped"
        continue
    }

    $meta = @(Get-ChildItem -LiteralPath $dir.FullName -Filter 'Meta*.md' -File) | Select-Object -First 1
    $mediaDir = Join-Path $dir.FullName 'media'
    $media = @()
    if (Test-Path -LiteralPath $mediaDir) {
        $media = @(Get-ChildItem -LiteralPath $mediaDir -File |
                   Where-Object { $_.Extension -match '(?i)^\.(jpe?g|png|webp|gif|avif)$' } |
                   Sort-Object Name)
    }

    $raw = Get-Content -LiteralPath $profile.FullName -Raw
    $lines = ($raw -replace "`r`n", "`n") -split "`n"

    # The document's own H1 is its title. It is usually not the character's name
    # - "Too Bad, Too Bad", "Campfire Myth", a case number - and that is exactly
    # what should be on the card, because it tells you what KIND of document it
    # is before you open it.
    $docTitle = ($lines | Where-Object { $_ -match '^#\s+\S' } | Select-Object -First 1) -replace '^#\s+', ''
    if (-not $docTitle) { $docTitle = $dir.Name }

    # A pull quote for the card. "First non-heading line" is wrong for the
    # structured formats: it picked "BEGIN TRANSCRIPT:" and "SUBJECT: VALERIE
    # AURUM CLEMENS / ID NC770416", which are labels, not hooks. So prefer the
    # first line long enough to be a SENTENCE, and only fall back to the first
    # line of any kind when a document has none.
    $candidates = @($lines | Select-Object -First 40 | Where-Object {
        $_.Trim() -and $_ -notmatch '^#' -and $_ -notmatch '^[-*|>]'
    })
    $lead = @($candidates | Where-Object { $_.Trim().Length -ge 70 } | Select-Object -First 1)
    if (-not $lead) { $lead = @($candidates | Select-Object -First 1) }
    $lead = (($lead | Select-Object -First 1) -replace '\*\*', '' -replace '\*', '').Trim()
    if ($lead.Length -gt 240) { $lead = $lead.Substring(0, 237).TrimEnd() + '...' }

    # Cycled from a fixed palette rather than derived from the name: a hash of
    # the name gives colours nobody chose, and these four are meant to be told
    # apart at a glance. Edit site.css to retune the whole set.
    $palette = @('#fcee0a', '#00e5ff', '#7dff6b', '#ff5cc8', '#ff9f45', '#b39dff')
    $chars.Add([pscustomobject]@{
        Accent    = $palette[$chars.Count % $palette.Count]
        Name      = (Get-Culture).TextInfo.ToTitleCase($dir.Name)
        Slug      = Get-Slug $dir.Name
        DocTitle  = $docTitle
        Lead      = $lead
        Body      = ConvertTo-Html -Markdown $raw
        MetaBody  = if ($meta) { ConvertTo-Html -Markdown (Get-Content -LiteralPath $meta.FullName -Raw) } else { $null }
        # Parenthesised: inside a hashtable entry the comma of a two-argument
        # -replace is read as the next element, and the parse error it throws
        # names a line four lines away from the mistake.
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
    Write-Host ("  {0,-14} {1,-34} {2,6} words, {3}" -f $c.Name, $c.DocTitle, $c.Words, $m) -ForegroundColor DarkGray
}

# ------------------------------------------------------------------- write ---

if (-not (Test-Path -LiteralPath $Out)) { New-Item -ItemType Directory -Path $Out -Force | Out-Null }

$stamp = Get-Date -Format 'yyyy-MM-dd'

# One stylesheet, one script, both readable and both meant to be edited. This is
# the whole "theme": there is no template language to learn.
Set-Content -LiteralPath (Join-Path $Out 'site.css') -Encoding UTF8 -Value @'
:root {
  --bg:#07080b; --panel:#0e1118; --line:#1b2130; --text:#d3dae6; --dim:#7d8899;
  --accent:#fcee0a; --accent2:#00e5ff; --red:#ff5c5c;
  --serif:"Iowan Old Style","Palatino Linotype",Georgia,serif;
  --mono:"Consolas","SF Mono",monospace;
  --sans:"Segoe UI",system-ui,sans-serif;
}
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--text); font:16px/1.65 var(--sans); }
a { color:var(--accent2); }

/* ---- top bar, on every page so the site never traps you ---- */
.top { position:sticky; top:0; z-index:9; display:flex; align-items:center; gap:16px;
       padding:14px 26px; background:rgba(7,8,11,.92); border-bottom:1px solid var(--line);
       backdrop-filter:blur(8px); }
.top a.home { color:var(--accent); font:600 14px/1 var(--mono); letter-spacing:.14em;
              text-transform:uppercase; text-decoration:none; }
.top .crumb { color:var(--dim); font:12px/1 var(--mono); letter-spacing:.08em; }
.top .spacer { flex:1; }
.top input { background:#11151d; border:1px solid var(--line); color:var(--text);
             padding:7px 12px; font:13px var(--sans); min-width:200px; border-radius:2px; }

/* ---- index ---- */
.hero { padding:64px 26px 30px; max-width:1180px; margin:0 auto; }
.hero h1 { margin:0; font:700 clamp(32px,6vw,60px)/1.05 var(--sans); letter-spacing:-.03em; }
.hero p { color:var(--dim); margin:10px 0 0; font-size:17px; }
.grid { display:grid; gap:20px; grid-template-columns:repeat(auto-fill,minmax(330px,1fr));
        max-width:1180px; margin:0 auto; padding:26px 26px 80px; }
.card { display:flex; flex-direction:column; background:var(--panel); border:1px solid var(--line);
        text-decoration:none; color:inherit; transition:border-color .15s, transform .15s; }
.card { --c:var(--accent); }
.card:hover { border-color:var(--c); transform:translateY(-2px); }
.card h2 { color:var(--c); }
.card .sub { display:block; color:var(--dim); font:11px/1.45 var(--mono); letter-spacing:.06em;
             text-transform:uppercase; margin-top:7px; }
.card .nameplate { font:700 clamp(22px,3.4vw,34px)/1 var(--mono); letter-spacing:.16em;
                   color:var(--c); opacity:.32; }
.card .shot { aspect-ratio:3/2; background:#0a0d13; display:flex; align-items:center;
              justify-content:center; overflow:hidden; border-bottom:1px solid var(--line); }
.card .shot img { width:100%; height:100%; object-fit:cover; }
/* No image yet? A monogram, not a broken frame. */
.card .mono { font:700 68px/1 var(--mono); color:var(--accent); opacity:.5; letter-spacing:-.04em; }
.card .body { padding:18px 20px 22px; }
.card h2 { margin:0; font:600 20px/1.25 var(--sans); }
.card .kicker { color:var(--accent); font:600 11px/1 var(--mono); letter-spacing:.18em;
                text-transform:uppercase; margin-bottom:9px; }
.card p { color:var(--dim); font-size:14px; margin:10px 0 0; }
.card .meta { color:var(--dim); font:11px/1 var(--mono); letter-spacing:.08em; margin-top:14px; }

/* ---- a document ---- */
.doc { max-width:760px; margin:0 auto; padding:52px 26px 100px; }
.doc .kicker { color:var(--accent); font:600 11px/1 var(--mono); letter-spacing:.2em;
               text-transform:uppercase; }
.doc h1 { font:700 clamp(26px,4.5vw,42px)/1.15 var(--sans); letter-spacing:-.02em; margin:12px 0 28px; }
.doc h2 { font:600 13px/1.3 var(--mono); letter-spacing:.14em; text-transform:uppercase;
          color:var(--accent2); margin:44px 0 12px; padding-top:16px; border-top:1px solid var(--line); }
.doc h3 { font:600 16px/1.3 var(--sans); margin:28px 0 8px; }
.doc h4 { font:600 13px/1.3 var(--mono); color:var(--dim); margin:20px 0 6px; letter-spacing:.06em; }
.doc p { margin:0 0 18px; font-family:var(--serif); font-size:18px; line-height:1.72; }
.doc li { font-family:var(--serif); font-size:17px; line-height:1.6; margin:4px 0; }
.doc ul { padding-left:22px; }
.doc code { font:13px var(--mono); background:#151a24; padding:1px 5px; border-radius:2px; color:var(--accent2); }
.doc blockquote { border-left:2px solid var(--accent); margin:0 0 18px; padding:2px 0 2px 18px;
                  color:var(--dim); font-family:var(--serif); font-style:italic; }
.doc hr { border:none; border-top:1px solid var(--line); margin:34px 0; }
.doc table { width:100%; border-collapse:collapse; margin:0 0 22px; font-size:14px; }
.doc th { text-align:left; font:600 11px/1 var(--mono); letter-spacing:.1em; text-transform:uppercase;
          color:var(--dim); padding:8px 10px; border-bottom:1px solid var(--line); }
.doc td { padding:8px 10px; border-bottom:1px solid var(--line); vertical-align:top; }
.doc strong { color:#fff; }

/* Long documents are a wall without this: the first line of each section gets
   room to breathe, and the reading column never runs full width on a monitor. */
.doc h2 + p, .doc h2 + ul { margin-top:14px; }

.gallery { display:grid; gap:12px; grid-template-columns:repeat(auto-fill,minmax(220px,1fr)); margin:0 0 30px; }
.gallery img { width:100%; border:1px solid var(--line); cursor:zoom-in; }
.lightbox { position:fixed; inset:0; background:rgba(3,4,6,.94); display:none;
            align-items:center; justify-content:center; z-index:50; padding:30px; }
.lightbox.on { display:flex; }
.lightbox img { max-width:100%; max-height:100%; }

footer { border-top:1px solid var(--line); color:var(--dim); font:12px/1.8 var(--mono);
         padding:22px 26px 40px; max-width:1180px; margin:0 auto; }

@media print {
  .top, .gallery, footer { display:none; }
  body { background:#fff; color:#000; }
  .doc { max-width:none; padding:0; }
  .doc h2 { color:#000; }
}
'@

Set-Content -LiteralPath (Join-Path $Out 'site.js') -Encoding UTF8 -Value @'
// Everything here degrades to nothing if JS is off, and none of it fetches:
// the site has to work when opened straight off the filesystem, where fetch()
// is blocked by the browser's file:// origin rules.

// Index: filter the cards as you type.
var box = document.getElementById('filter');
if (box) {
  box.addEventListener('input', function () {
    var q = box.value.toLowerCase();
    document.querySelectorAll('.card').forEach(function (c) {
      c.style.display = c.innerText.toLowerCase().indexOf(q) === -1 ? 'none' : '';
    });
  });
}

// Document: click an image to see it whole.
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
    param([string] $File, [string] $PageTitle, [string] $Crumb, [string] $Body, [string] $Extra = '')
    $doc = @"
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$(Get-Esc $PageTitle)</title>
<link rel="stylesheet" href="site.css">
</head><body>
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

# ---- one page per character ----
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
        $metaSection = "<hr><h2>$(Get-Esc $c.MetaTitle)</h2>$($c.MetaBody)"
    }

    $body = @"
<div class="doc">
  <div class="kicker" style="color:$($c.Accent)">$(Get-Esc $c.Name)</div>
  $gallery
  $($c.Body)
  $metaSection
</div>
<div class="lightbox"><img alt=""></div>
<footer>$(Get-Esc $c.DocTitle) &middot; $($c.Words) words &middot; built $stamp</footer>
"@
    Write-Page -File "$($c.Slug).html" -PageTitle "$($c.Name) - $($c.DocTitle)" -Crumb $c.Name -Body $body
}

# ---- index ----
$cards = foreach ($c in $chars) {
    # A MONOGRAM IS USELESS HERE. Every character on the install this was built
    # against is a V - Valkyrie, Vanish, Venom, Vindicator - so a first-letter
    # tile drew the same glyph four times. The name itself is the artwork until
    # there are photographs, and the accent colour carries the difference.
    $shot = if ($c.Media.Count) {
        "<img src=""media/$($c.Slug)/$([uri]::EscapeDataString($c.Media[0].Name))"" alt=""$(Get-Esc $c.Name)"">"
    } else {
        "<span class=""nameplate"">$(Get-Esc $c.Name.ToUpper())</span>"
    }
    @"
  <a class="card" href="$($c.Slug).html" style="--c:$($c.Accent)">
    <span class="shot">$shot</span>
    <span class="body">
      <h2>$(Get-Esc $c.Name)</h2>
      <span class="sub">$(Get-Esc $c.DocTitle)</span>
      <p>$(Get-Esc $c.Lead)</p>
      <span class="meta">$($c.Words) words$(if ($c.Media.Count) { " &middot; $($c.Media.Count) images" })</span>
    </span>
  </a>
"@
}

$indexBody = @"
<div class="hero">
  <h1>$(Get-Esc $Title)</h1>
  <p>$(Get-Esc $Tagline)</p>
</div>
<div class="grid">
$($cards -join "`n")
</div>
<footer>$($chars.Count) records &middot; built $stamp &middot; no tracking, no scripts from anywhere else, works offline</footer>
"@
Write-Page -File 'index.html' -PageTitle $Title -Crumb '' -Body $indexBody `
           -Extra '<input id="filter" type="search" placeholder="filter" aria-label="filter records">'

Write-Host ''
Write-Host "site written to $((Resolve-Path -LiteralPath $Out).Path)" -ForegroundColor Green
Write-Host "  open index.html, or copy the whole folder to any web host" -ForegroundColor DarkGray

if ($Open) { Start-Process (Join-Path $Out 'index.html') }
exit 0
