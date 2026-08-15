# New-HotkeySheet.ps1 -- build a self-contained hotkey cheatsheet from the
# bindings actually present in a Cyberpunk install.
#
#     .\New-HotkeySheet.ps1 -Out ~\Downloads\hotkeys.html
#
# Keys come from Get-Hotkeys.ps1, which reads them off disk - no hand-typed
# bindings, so the sheet cannot drift from the game the way a hand-written one
# does. Anything that genuinely is not on disk (mouse hardware mapping, tap/hold
# semantics) lives in a small notes json and is merged over the top; pass it with
# -Notes. Everything is inlined, so the file works offline and on a phone
# propped next to the keyboard.
#
# Optimised for reading at a glance mid-game: big keycaps, one accent colour per
# situation, no information that only appears on hover.

[CmdletBinding()]
param(
    [string] $GameRoot = 'C:\Games\Steam\steamapps\common\Cyberpunk 2077',
    [string] $Notes,
    [string] $Out = "$env:USERPROFILE\Downloads\cp2077_hotkeys_cheatsheet.html",

    # Every type size on the sheet derives from one base, so this scales the
    # whole thing without disturbing the proportions. 1.0 is sized for reading
    # from normal seating distance; go up for a TV or a glance across the desk.
    [double] $Scale = 1.0,

    # Both off by default. The mouse pad and the shared-key list are reference
    # material, not things you glance at mid-fight, and every row they add is a
    # row competing with the ones you actually came to look up.
    [switch] $ShowMousePad,
    [switch] $ShowSharedKeys
)

$ErrorActionPreference = 'Stop'
function esc { param([string]$s) ($s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;') }

# ==================================================================== gather ==

$binds = & (Join-Path $PSScriptRoot 'Get-Hotkeys.ps1') -GameRoot $GameRoot
Write-Host "harvested $($binds.Count) keyboard bindings" -ForegroundColor Cyan

$n = $null
if ($Notes -and (Test-Path -LiteralPath $Notes)) {
    $n = Get-Content -LiteralPath $Notes -Raw | ConvertFrom-Json
    Write-Host "merged notes from $Notes" -ForegroundColor Cyan
}

foreach ($e in $n.extra) {
    $binds += [pscustomobject]@{
        Mod=$e.mod; Action=$e.action; Key=$e.key; Pad=''
        Context=$e.context; Scope=''; Source='manual'; System='notes'
    }
}

# Which categories exist, in the order a player would want them.
$order  = 'Combat','Driving','Stealth & Loot','World','Tools'
$accent = @{ 'Combat'='red'; 'Driving'='cyan'; 'Stealth & Loot'='green'
             'World'='yellow'; 'Tools'='purple' }

# Keys carrying more than one meaning. Most are harmless - the game scopes
# bindings by input context, so 'R' can reload, renew a chip and pick a pocket
# without conflict - but a couple genuinely overlap and are worth seeing.
$collisions = $binds | Group-Object Key | Where-Object Count -gt 1 | Sort-Object Name

# ===================================================================== render ==

$sb = [Text.StringBuilder]::new()
function w { param([string]$s) [void]$sb.AppendLine($s) }

# Which thumb button sends a given key. The mouse panel listed every one of
# these a second time - "Next consumable / ]" as a mouse cell and again as an
# Advanced Control row - so instead the button rides along on the row it
# duplicates, as a badge next to the keycap.
$mouseFor = @{}
foreach ($m in $n.mouse) { if (-not $mouseFor.ContainsKey($m.sends)) { $mouseFor[$m.sends] = $m.button } }

# ---- mouse panel ----
$mouseHtml = ''
if ($n.mouse -and $ShowMousePad) {
    $cells = foreach ($m in $n.mouse) {
        # Resolve what this key actually does from the harvested data, so a
        # rebind in game shows up here without editing the notes file.
        #
        # Only worth printing where it disagrees with the hand-written label -
        # "Flashlight / Toggle flashlight" is noise, while "Night vision /
        # Toggle minimap" is the sheet telling you the label has gone stale.
        $flat = { param($s) ($s -replace '[^a-z0-9]','').ToLower() }
        $lbl  = & $flat $m.label
        $hits = @($binds | Where-Object { $_.Key -eq $m.sends } | Where-Object {
            $a = & $flat $_.Action
            -not ($a.Contains($lbl) -or $lbl.Contains($a))
        })
        $via  = if ($hits) { ($hits | ForEach-Object { "$($_.Action)" } | Select-Object -Unique) -join ' &middot; ' } else { '' }
        @"
    <div class="mbtn">
      <span class="mnum">$($m.button)</span>
      <kbd class="k">$(esc $m.sends)</kbd>
      <span class="mlbl">$(esc $m.label)</span>
      $(if ($via) { "<span class=""mvia"">$via</span>" })
    </div>
"@
    }
    $mouseHtml = @"
  <section class="panel mouse">
    <h2><span class="dot yellow"></span>$(esc $n.device)<b>thumb pad</b></h2>
    <div class="mgrid">$($cells -join '')</div>
    <p class="foot">Hardware mapping - the mouse sends these keys, and the grey line is what the game currently does with them.</p>
  </section>
"@
}

# ---- category panels ----
$catHtml = foreach ($c in $order) {
    $set = @($binds | Where-Object Context -eq $c | Sort-Object Mod, Action)
    if (-not $set) { continue }
    $rows = foreach ($b in $set) {
        $keys = ($b.Key -split ' / ' | ForEach-Object { "<kbd class=""k"">$(esc $_)</kbd>" }) -join '<i>/</i>'
        $mb   = if ($mouseFor.ContainsKey($b.Key)) {
            "<b class=""ms"" title=""$(esc $n.device) thumb button"">M$($mouseFor[$b.Key])</b>"
        } else { '' }
        $mark = if ($b.Source -eq 'your setting') { '' } else { '<span class="def" title="mod default - not rebound by you">&#9679;</span>' }
        @"
      <div class="row" data-s="$(esc "$($b.Action) $($b.Mod) $($b.Key)".ToLower())">
        <span class="act">$(esc $b.Action)<em>$(esc $b.Mod)$mark</em></span>
        <span class="keys">$mb$keys</span>
      </div>
"@
    }
    # One oversized panel sets the height of the whole sheet - Combat's 21 rows
    # against Tools' 7 left half the screen empty below the short panels. Split
    # a tall panel's rows into internal columns and let it claim proportionally
    # more width, and every panel ends up roughly the same height.
    $big = $set.Count -gt 12
    @"
  <section class="panel$(if ($big) { ' big' })">
    <h2><span class="dot $($accent[$c])"></span>$(esc $c)<b>$($set.Count)</b></h2>
    <div class="rows">$($rows -join '')</div>
  </section>
"@
}

# ---- gesture panel ----
$gestHtml = ''
if ($n.gestures) {
    # If every group credits the same mod, say it once in the panel heading.
    $mods   = @($n.gestures | ForEach-Object { $_.mod } | Where-Object { $_ } | Select-Object -Unique)
    $oneMod = if ($mods.Count -eq 1) { $mods[0] } else { $null }
    $groups = foreach ($g in $n.gestures) {
        $items = foreach ($i in $g.items) {
            $steps = if ($i.steps) {
                '<span class="steps">' + (($i.steps | ForEach-Object { "<b>$(esc $_)</b>" }) -join '<i>&rsaquo;</i>') + '</span>'
            } else { '' }
            @"
        <div class="grow">
          <span class="gkey"><kbd class="k">$(esc $i.key)</kbd><span class="ges">$(esc $i.gesture)</span></span>
          <span class="gdoes">$(esc $i.does)$steps</span>
        </div>
"@
        }
        # Name the mod per group only when they differ. Every gesture here comes
        # from one mod today, so repeating it three times would be noise - but
        # the panel said nothing at all, which left the keys unattributable.
        $gmod = if ($g.mod -and -not $oneMod) { "<em>$(esc $g.mod)</em>" } else { '' }
        "<div class=""ggroup""><h3>$(esc $g.group)$gmod</h3>$($items -join '')</div>"
    }
    $credit = if ($oneMod) { "<b>$(esc $oneMod)</b>" } else { '<b>tap &middot; hold &middot; multi-tap</b>' }
    $gestHtml = @"
  <section class="panel wide">
    <h2><span class="dot cyan"></span>Vehicle gestures$credit</h2>
    <div class="ggrid">$($groups -join '')</div>
  </section>
"@
}

# ---- collision panel ----
$colHtml = ''
if ($collisions -and $ShowSharedKeys) {
    $items = foreach ($g in $collisions) {
        $who = ($g.Group | ForEach-Object { "<span class=""cw""><b>$(esc $_.Context)</b>$(esc $_.Action) <em>$(esc $_.Mod)</em></span>" }) -join ''
        "<div class=""crow""><kbd class=""k"">$(esc $g.Name)</kbd><div class=""cwho"">$who</div></div>"
    }
    $colHtml = @"
  <section class="panel wide">
    <h2><span class="dot red"></span>Shared keys<b>$($collisions.Count)</b></h2>
    <p class="foot">Bindings scope to an input context, so most of these never fire at the same time - a key can reload a gun and open a door because you are never doing both. Worth a glance anyway when something does not respond the way you expect.</p>
    <div class="cgrid">$($items -join '')</div>
  </section>
"@
}

$stamp   = Get-Date -Format 'yyyy-MM-dd HH:mm'
$yours   = @($binds | Where-Object Source -eq 'your setting').Count
$subline = "$($binds.Count) BOUND KEYS &nbsp;//&nbsp; $yours FROM YOUR SETTINGS &nbsp;//&nbsp; READ FROM DISK $stamp"

$html = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Cyberpunk 2077 Hotkeys</title>
<style>
:root{
  --yellow:#fcee0a; --cyan:#00f0ff; --red:#ff003c; --green:#39ff88; --purple:#b56cff;
  --bg:#07070a; --panel:#101018; --line:#26263a; --text:#e4e4ee; --dim:#8a8aa2;
  --mono:'Consolas','SF Mono','DejaVu Sans Mono',monospace;
  --sans:'Segoe UI',system-ui,-apple-system,sans-serif;
  /* Single type base. Every size below is a ratio of this, so the sheet scales
     as one piece instead of drifting out of proportion. */
  --fs:__FS__px;
}
*{box-sizing:border-box}
html,body{margin:0;padding:0}
body{
  background:var(--bg); color:var(--text); font-family:var(--sans);
  font-size:var(--fs); line-height:1.3;
  background-image:
    linear-gradient(rgba(252,238,10,.02) 1px,transparent 1px),
    linear-gradient(90deg,rgba(252,238,10,.02) 1px,transparent 1px);
  background-size:46px 46px;
}
/* No max-width. This is meant to be parked on a second monitor, so a centred
   column on an ultrawide wastes the whole point - spreading wide buys more
   columns, which buys a shorter page, which is what "at a glance" means. */
.wrap{margin:0 auto;padding:0 22px 10px}

header{position:relative;padding:12px 0 9px;overflow:hidden;border-bottom:1px solid var(--line)}
/* Scanlines are confined to the masthead. Over a page you actually read from,
   they fight the text; over a title block they just set the tone. */
header::after{content:'';position:absolute;inset:0;pointer-events:none;
  background:repeating-linear-gradient(0deg,rgba(0,0,0,.34) 0 1px,transparent 1px 3px)}
h1{font-family:var(--mono);font-size:calc(var(--fs)*1.7);font-weight:700;margin:0;
  letter-spacing:.09em;text-transform:uppercase;color:var(--yellow);
  text-shadow:2px 0 var(--red),-2px 0 var(--cyan)}
h1 span{color:var(--text);text-shadow:none}
.sub{font-family:var(--mono);font-size:calc(var(--fs)*.56);letter-spacing:.15em;color:var(--dim);margin-top:6px}

.bar{position:sticky;top:0;z-index:9;padding:8px 0;
  background:linear-gradient(180deg,var(--bg) 76%,transparent);display:flex;gap:12px;align-items:center}
#q{flex:1 1 auto;background:var(--panel);color:var(--text);border:1px solid var(--line);
  border-left:3px solid var(--yellow);padding:13px 16px;font-family:var(--mono);
  font-size:calc(var(--fs)*.78);outline:none}
#q:focus{border-color:var(--cyan);border-left-color:var(--cyan)}
#q::placeholder{color:#4c4c60}
#hits{font-family:var(--mono);font-size:calc(var(--fs)*.55);color:var(--dim);white-space:nowrap}
.pill{font-family:var(--mono);font-size:calc(var(--fs)*.5);letter-spacing:.1em;cursor:pointer;
  background:var(--panel);color:var(--dim);border:1px solid var(--line);padding:10px 14px;
  text-transform:uppercase;white-space:nowrap;transition:.12s}
.pill:hover{color:var(--text);border-color:#3a3a54}
.pill.on{background:var(--yellow);color:#07070a;border-color:var(--yellow);font-weight:700}
/* Hiding the mod name drops every row to a single line - the densest the sheet
   gets, for when you know your mods and only want the keys. */
body.nomods .act em{display:none}

/* Flex rather than CSS multi-column. Multicol balances content across a count
   it derives itself, and on a wide monitor it decided two columns were enough
   and left two thirds of the screen empty. Flex just fills the row. */
.cols{display:flex;flex-wrap:wrap;align-items:flex-start;gap:14px}
/* The bottom padding has to clear the 14px corner bevel below - at 6px the
   last row of a panel was being sliced by the clip-path. */
.panel{background:var(--panel);border:1px solid var(--line);padding:11px 16px 14px;
  flex:1 1 400px; min-width:0;
  clip-path:polygon(0 0,calc(100% - 14px) 0,100% 14px,100% 100%,14px 100%,0 calc(100% - 14px))}
.panel.wide{flex-basis:100%;margin-top:14px}
/* A tall panel splits internally and takes proportionally more width, so no
   single category dictates the height of the page. */
.panel.big{flex-grow:2;flex-basis:820px}
.panel.big .rows{columns:2;column-gap:22px}
.rows .row{break-inside:avoid}
h2{font-family:var(--mono);font-size:calc(var(--fs)*.6);letter-spacing:.2em;text-transform:uppercase;
  margin:0 0 6px;padding-bottom:6px;border-bottom:1px solid var(--line);
  display:flex;align-items:center;gap:10px;color:var(--text)}
h2 b{margin-left:auto;color:var(--dim);font-weight:400;font-size:calc(var(--fs)*.52);letter-spacing:.12em}
.dot{width:10px;height:10px;flex:0 0 10px;transform:rotate(45deg)}
.dot.red{background:var(--red)} .dot.cyan{background:var(--cyan)}
.dot.green{background:var(--green)} .dot.yellow{background:var(--yellow)}
.dot.purple{background:var(--purple)}

/* Keycap. The whole sheet is read at arm's length, so these stay chunky. */
kbd.k{font-family:var(--mono);font-size:calc(var(--fs)*.79);font-weight:700;color:var(--yellow);
  background:#1b1b26;border:1px solid #3a3a52;border-bottom-width:3px;border-radius:4px;
  padding:5px 12px;min-width:calc(var(--fs)*2);display:inline-block;text-align:center;white-space:nowrap}

/* One line per binding. The mod name used to sit on its own line under every
   action, which doubled the height of the entire sheet for information you
   only want when you go to change something. Inline and dimmed, it costs
   nothing and the row stays scannable. */
.row{display:flex;align-items:baseline;gap:12px;padding:4px 2px;border-bottom:1px solid #191926}
.row:last-child{border-bottom:0}
/* min-width:0 + overflow-wrap let the label give way. Without them the action
   text's longest word sets a floor on the row width, and inside a narrow
   column that floor plus a wide keycap ("Caps Lock") overflowed the page. */
.act{flex:1 1 0;min-width:0;overflow-wrap:anywhere;font-size:calc(var(--fs)*.84);line-height:1.22}
/* The mod name wraps like any other text. Held on one line it set a hard floor
   on the row's width - "Character Customization Anywhere" is wider than a Tools
   column - and the keycap next to it was pushed off the page. */
.act em{font-style:normal;font-size:calc(var(--fs)*.5);color:#6a6a80;
  font-family:var(--mono);letter-spacing:.03em;margin-left:9px}
.def{color:#4c4c60;margin-left:5px;font-size:calc(var(--fs)*.42);vertical-align:1px}
.keys{white-space:nowrap;flex:0 0 auto;display:flex;align-items:center;gap:6px}
.keys i{color:#4c4c60;font-style:normal;padding:0 2px;font-size:calc(var(--fs)*.62)}
/* Thumb-button badge, replacing the mouse panel that repeated these rows. */
.ms{font-family:var(--mono);font-size:calc(var(--fs)*.5);font-weight:700;color:#b4b4cc;
  background:rgba(138,138,162,.14);border:1px solid rgba(138,138,162,.55);
  border-radius:3px;padding:1px 4px;letter-spacing:.02em}

/* ---- mouse ---- */
.mgrid{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}
.mbtn{background:#15151f;border:1px solid #2b2b40;padding:11px 9px 9px;text-align:center;position:relative}
.mnum{position:absolute;top:4px;left:7px;font-family:var(--mono);font-size:calc(var(--fs)*.52);color:#4c4c60}
.mbtn kbd.k{margin:4px 0 6px}
.mlbl{display:block;font-size:calc(var(--fs)*.68);line-height:1.25;color:var(--text)}
.mvia{display:block;font-size:calc(var(--fs)*.53);color:var(--dim);font-family:var(--mono);
  margin-top:4px;line-height:1.3}
.foot{font-size:calc(var(--fs)*.6);color:var(--dim);line-height:1.5;margin:12px 0 8px}

/* ---- gestures ---- */
.ggrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(380px,1fr));gap:18px}
.ggroup h3{font-family:var(--mono);font-size:calc(var(--fs)*.57);letter-spacing:.16em;
  text-transform:uppercase;color:var(--cyan);margin:0 0 6px;font-weight:400}
.grow{display:flex;gap:14px;align-items:baseline;padding:7px 0;border-bottom:1px solid #191926}
.gkey{flex:0 0 auto;min-width:9.2em;display:flex;gap:8px;align-items:baseline;flex-wrap:wrap}
/* Luminous text on a dark ground, like every other accent on the sheet. Solid
   cyan behind black type was the one place that inverted, and small letter-
   spaced uppercase is exactly where that inversion reads worst. Padding drops
   by the width of the new border, so the chip occupies the same box. */
.ges{font-family:var(--mono);font-size:calc(var(--fs)*.5);letter-spacing:.11em;text-transform:uppercase;
  color:var(--cyan);background:rgba(0,240,255,.12);border:1px solid rgba(0,240,255,.45);
  padding:1px 6px;white-space:nowrap}
.gdoes{flex:1;font-size:calc(var(--fs)*.79);line-height:1.3}
.steps{display:block;margin-top:5px;font-size:calc(var(--fs)*.58);color:var(--dim);font-family:var(--mono)}
.steps b{font-weight:400;color:#a8a8bd} .steps i{font-style:normal;color:#4c4c60;padding:0 5px}

/* ---- collisions ---- */
.cgrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(340px,1fr));gap:10px}
.crow{display:flex;gap:12px;align-items:flex-start;background:#15151f;border:1px solid #2b2b40;padding:11px 13px}
.crow kbd.k{color:var(--red);border-color:#4a1024}
.cwho{flex:1;display:flex;flex-direction:column;gap:4px}
.cw{font-size:calc(var(--fs)*.68);line-height:1.3}
.cw b{font-family:var(--mono);font-size:calc(var(--fs)*.5);letter-spacing:.1em;text-transform:uppercase;
  color:var(--dim);font-weight:400;margin-right:7px}
.cw em{font-style:normal;color:var(--dim);font-size:calc(var(--fs)*.55);font-family:var(--mono)}

footer{margin-top:14px;padding-top:9px;border-top:1px solid var(--line);
  font-family:var(--mono);font-size:calc(var(--fs)*.5);color:#4c4c60;line-height:1.5}
.hide{display:none !important}

@media print{
  body{background:#fff;color:#000;--fs:12pt;background-image:none}
  .bar,footer,header::after{display:none}
  h1{color:#000;text-shadow:none}
  .panel{border:1px solid #999;background:#fff;clip-path:none;break-inside:avoid;flex-basis:45%}
  kbd.k{color:#000;background:#eee;border-color:#999}
  .act em,.mvia,.foot{color:#555}
}
</style>
</head>
<body>
<div class="wrap">

<header>
  <h1>Cyberpunk 2077 <span>Hotkeys</span></h1>
  <div class="sub">$subline</div>
</header>

<div class="bar">
  <input id="q" type="search" placeholder="filter - action, mod or key...">
  <button id="modtoggle" class="pill on" title="show or hide which mod each binding belongs to">mod names</button>
  <span id="hits"></span>
</div>

<div class="cols">
$mouseHtml
$($catHtml -join '')
</div>

$gestHtml
$colHtml

<footer>
  Keys read from r6\input\*.xml, r6\cache\inputUserMappings.xml, red4ext\plugins\mod_settings\user.ini<br>
  and bin\x64\plugins\cyber_engine_tweaks\bindings.json. &#9679; marks a mod default you have not rebound.<br>
  Generated $stamp // CYBERWISE
</footer>
</div>

<script>
// DOM filtering rather than a re-render: the sheet is static, and hiding rows
// keeps the panels and their headings where the eye already expects them.
const q = document.getElementById('q'), hits = document.getElementById('hits');
const rows = [...document.querySelectorAll('.row')];
q.addEventListener('input', () => {
  const terms = q.value.trim().toLowerCase().split(/\s+/).filter(Boolean);
  let n = 0;
  rows.forEach(r => {
    const ok = terms.every(t => r.dataset.s.includes(t));
    r.classList.toggle('hide', !ok);
    if (ok) n++;
  });
  // Drop a panel once every row in it is filtered out.
  document.querySelectorAll('.panel:not(.wide)').forEach(p => {
    const rs = p.querySelectorAll('.row');
    p.classList.toggle('hide', rs.length > 0 && ![...rs].some(r => !r.classList.contains('hide')));
  });
  hits.textContent = terms.length ? n + ' / ' + rows.length : '';
});

// Mod-name toggle. The preference sticks across regenerations where the browser
// allows it - localStorage is unavailable on some file:// origins, so treat a
// failure as "no persistence" rather than letting it break the control.
const mt = document.getElementById('modtoggle');
function setMods(on){
  document.body.classList.toggle('nomods', !on);
  mt.classList.toggle('on', on);
  try { localStorage.setItem('cw_modnames', on ? '1' : '0'); } catch (e) {}
}
let modsOn = true;
try { modsOn = localStorage.getItem('cw_modnames') !== '0'; } catch (e) {}
setMods(modsOn);
mt.addEventListener('click', () => setMods(document.body.classList.contains('nomods')));
</script>
</body>
</html>
"@

$html = $html.Replace('__FS__', [string][math]::Round(30 * $Scale, 1))

$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
Set-Content -LiteralPath $Out -Value $html -Encoding UTF8
Write-Host "wrote $Out ($([math]::Round((Get-Item -LiteralPath $Out).Length/1kb,1)) KB)" -ForegroundColor Green
