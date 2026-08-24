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
    # Left empty, Get-Hotkeys.ps1 locates the install itself (Steam / GOG / Epic
    # records, then their default folders) and errors if it cannot.
    [string] $GameRoot,
    [string] $Notes,
    [string] $Out = "$env:USERPROFILE\Downloads\cp2077_hotkeys_cheatsheet.html",

    # The same sheet as markdown, for a forum post, a wiki, or a Discord message
    # where a local HTML file is useless to whoever you are talking to.
    [string] $Md,

    # Every type size on the sheet derives from one base, so this scales the
    # whole thing without disturbing the proportions. 1.0 is sized for reading
    # from normal seating distance; go up for a TV or a glance across the desk.
    [double] $Scale = 1.0,

    # Both off by default. The mouse pad and the shared-key list are reference
    # material, not things you glance at mid-fight, and every row they add is a
    # row competing with the ones you actually came to look up.
    [switch] $ShowMousePad,
    [switch] $ShowSharedKeys,

    # Include the bindings the BASE GAME claims, from
    # r6\config\inputUserMappings.xml. Off by default for the same reason
    # Get-Hotkeys.ps1 has it off: ~99 vanilla rows swamp a sheet about mods.
    #
    # But "vanilla row" and "the key I actually use" are not the same thing, and
    # that is why this switch had to exist here at all. Several mods CHANGE
    # BEHAVIOUR ON A VANILLA MAPPING rather than registering their own input -
    # Advanced Control and Lean Anywhere both ride LeanLeft_Button/
    # LeanRight_Button (IK_Q / IK_E), and consumable and grenade cycling ride
    # UseConsumable_Button and CombatGadget_Button. Those read as base-game
    # rows and were therefore invisible on a modded install's own cheatsheet,
    # with no way to switch them on. Reported by the user, 2026-08-24.
    [switch] $IncludeBaseGame,

    # ---- the programmable-mouse layer -------------------------------------
    #
    # ON by default whenever an iCUE profile exists, and that asymmetry with
    # -IncludeBaseGame is deliberate. The ~99 vanilla rows are generic - the
    # same list every install has - so they are noise until asked for. A mouse
    # profile is the opposite: it is a description of how THIS user actually
    # plays, hand-built by them, and it exists on maybe one machine in twenty.
    # Nothing about it is boilerplate, so nothing about it should need a flag.
    #
    # -NoMouseProfile is the escape hatch for a sheet meant for somebody else.
    [switch] $NoMouseProfile,

    # Which profile, by the name shown in iCUE. Left empty, the one with the
    # most key remaps is read and the sheet SAYS which - the filenames are
    # opaque GUIDs, so a user with several profiles has no other way to tell
    # where the rows came from.
    [string] $MouseProfile,

    # Where iCUE keeps its profiles, for a machine that puts them somewhere
    # else - and for proving the graceful path against an empty folder.
    [string] $MouseProfileRoot
)

$ErrorActionPreference = 'Stop'
function esc { param([string]$s) ($s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;') }

# ==================================================================== gather ==

# Only forward -GameRoot when there is one, so an empty value does not override
# Get-Hotkeys' own detection with a blank path.
$harvestArgs = @{}
if ($GameRoot) { $harvestArgs.GameRoot = $GameRoot }
if ($IncludeBaseGame) { $harvestArgs.IncludeBaseGame = $true }
$binds = @(& (Join-Path $PSScriptRoot 'Get-Hotkeys.ps1') @harvestArgs)
Write-Host "harvested $($binds.Count) keyboard bindings" -ForegroundColor Cyan
if ($binds.Count -eq 0) {
    # Not an error: an archive-only load order declares no keys. The sheet still
    # renders, so any notes file the user passes is not silently thrown away.
    Write-Warning "no bindings on disk - the sheet will hold only whatever -Notes supplies"
}

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

# ======================================================= the mouse-key join ==
#
# A PROGRAMMABLE MOUSE IS A LAYER OVER THE FIVE STORES, NOT A SIXTH STORE.
#
# The device performs no game action. It sends a KEYSTROKE, and the game or a
# mod then interprets that keystroke exactly as if it had come from the
# keyboard. So the profile cannot be rendered beside the harvested bindings as
# another list of controls - it has to be JOINED to them:
#
#     physical button  ->  keystroke sent  ->  what that keystroke is bound to
#
# Printing only the first two is printing the label the user typed into iCUE
# months ago, which is a memory, not evidence. The third column is the whole
# value of the section, and it is the only thing that can report the failure
# that matters: a button whose keystroke is bound to NOTHING on disk. That
# button does nothing in game, it looks identical to a working one in iCUE, and
# there is no other way to find out.
#
# Two key vocabularies have to be reconciled to make the join land. iCUE names a
# key after every glyph on it (`PeriodAndBiggerThan`), Get-Hotkeys prints mod
# bindings prettified (`.`) and base-game rows as raw IK names minus the prefix
# (`Period`, `MiddleMouse`). Comparing any two of those directly finds nothing
# and reports every button dead - so everything is folded to one token first.
$keyCanon = @{
    'period'='.'; 'comma'=','; 'lbracket'='['; 'bracketleft'='['
    'rbracket'=']'; 'bracketright'=']'; 'minus'='-'; 'equals'='='
    'tilde'='`'; 'graveaccentandtilde'='`'; 'semicolon'=';'; 'singlequote'="'"
    'slash'='/'; 'backslash'='\'
    'middlemouse'='mouse-mid'; 'middleclick'='mouse-mid'; 'mouse3'='mouse-mid'
    'leftmouse'='mouse-l'; 'leftclick'='mouse-l'
    'rightmouse'='mouse-r'; 'rightclick'='mouse-r'
    'mouse4'='mouse-4'; 'mouse5'='mouse-5'
    'keypadplus'='num+'; 'numpad+'='num+'; 'num+'='num+'
    'capslock'='caps'; 'escape'='esc'
}
function Get-KeyCanon {
    param([string] $s)
    if (-not $s) { return '' }
    $t = ($s -replace '[\s_]', '').ToLower()
    if ($keyCanon.ContainsKey($t)) { return $keyCanon[$t] }
    return $t
}

# Sort the pad the way it is laid out under the thumb, not the way cereal
# happened to serialise it: G1..G12 numerically, then the named buttons, then
# actions assigned to no button at all.
function Get-ButtonRank {
    param([string] $b)
    if ($b -match '^G(\d+)$') { return [int]$matches[1] }
    if ($b) { return 900 }
    return 999
}

$mouseRows   = @()
$mouseName   = ''
$mouseDev    = ''
$mouseOther  = @()
$mouseLinked = $false
$mouseAllCount = 0
if (-not $NoMouseProfile) {
    $mpArgs = @{}
    if ($MouseProfileRoot) { $mpArgs.Root = $MouseProfileRoot }
    if ($MouseProfile)     { $mpArgs.ProfileName = $MouseProfile }

    # Warnings are collected rather than emitted. "No iCUE profiles found" is
    # the NORMAL case - most people own no Corsair device - and a warning on a
    # perfectly good run trains people to ignore warnings. It is reported below
    # as one plain line, and only becomes loud if a profile was asked for by
    # name and did not turn up, which is a real mistake.
    $mpWarn = @()
    $mouseAll = @(& (Join-Path $PSScriptRoot 'Get-MouseProfile.ps1') @mpArgs -WarningVariable mpWarn -WarningAction SilentlyContinue)

    if ($mouseAll.Count) {
        # Several profiles and no -MouseProfile. Rank them, best evidence first:
        #
        #   1. iCUE says the profile auto-activates for Cyberpunk2077.exe. That
        #      is not a guess - the user linked it to the game themselves, and
        #      it is the profile that will actually be loaded while they play.
        #   2. failing that, whichever holds the most key remaps.
        #
        # It is still a choice made on the user's behalf, which is why the sheet
        # prints the profile's NAME and how many others exist. The filenames are
        # GUIDs; someone with a Cyberpunk profile and a spreadsheet profile has
        # no other way to tell which one produced these rows.
        $byProfile = $mouseAll | Group-Object Profile | Sort-Object `
            @{e={ if ($_.Group[0].Linked -match '(?i)Cyberpunk2077\.exe') { 1 } else { 0 } }; d=$true},
            @{e={ @($_.Group | Where-Object Kind -eq 'key remap').Count }; d=$true},
            Name
        $chosen     = $byProfile[0]
        $mouseLinked = [bool]($chosen.Group[0].Linked -match '(?i)Cyberpunk2077\.exe')
        $mouseName  = $chosen.Name
        $mouseDev  = (@($chosen.Group | Where-Object Device | ForEach-Object { $_.Device } | Select-Object -Unique) -join ', ')

        foreach ($m in ($chosen.Group | Sort-Object @{e={Get-ButtonRank $_.Button}}, Order)) {
            # Only key remaps can be joined. A macro or a DPI switch emits no
            # keystroke, so nothing in the five stores could ever describe it -
            # they are held back and named separately rather than shown with an
            # empty, accusatory "bound to nothing".
            if ($m.Kind -ne 'key remap') { $mouseOther += $m; continue }
            $canon = Get-KeyCanon $m.Key
            $hits  = @($binds | Where-Object { (Get-KeyCanon $_.Key) -eq $canon })
            $mouseRows += [pscustomobject]@{
                Button   = $m.Button
                Label    = $m.Action        # what the USER called it in iCUE
                Key      = $m.Key
                Hits     = $hits
                Assigned = [bool]$m.Button
            }
        }

        $mouseAllCount = $byProfile.Count
        $extra = $byProfile.Count - 1
        Write-Host ("iCUE: read profile '$mouseName'" +
                    $(if ($mouseLinked) { ' (iCUE auto-activates it for Cyberpunk2077.exe)' }) +
                    " - $(@($mouseRows).Count) key remap(s) on $mouseDev" +
                    $(if ($extra -gt 0) { " ($extra other profile$(if ($extra -gt 1){'s'}) on this machine)" })) -ForegroundColor Cyan

        $dead = @($mouseRows | Where-Object { $_.Assigned -and -not $_.Hits.Count })
        if ($dead.Count) {
            Write-Host ("      $($dead.Count) button(s) send a key nothing on disk is bound to: " +
                        (($dead | ForEach-Object { "$($_.Button) sends '$($_.Key)'" }) -join ', ')) -ForegroundColor DarkYellow
        }
    } else {
        # Say it plainly and carry on. This is not a failure of anything.
        Write-Host "iCUE: no mouse profiles found - the mouse section is omitted" -ForegroundColor DarkGray
        if ($MouseProfile -and $mpWarn) { $mpWarn | ForEach-Object { Write-Warning $_ } }
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
#
# Keyed by the canonical key token, not the printed one, so a badge lands on a
# base-game row too - those carry raw IK names (`MiddleMouse`) while the mouse
# profile speaks glyphs (`Middle Mouse`), and the two never match literally.
$mouseFor = @{}
foreach ($m in $n.mouse) {
    $c = Get-KeyCanon $m.sends
    if (-not $mouseFor.ContainsKey($c)) { $mouseFor[$c] = "M$($m.button)" }
}
foreach ($m in $mouseRows) {
    if (-not $m.Assigned) { continue }
    $c = Get-KeyCanon $m.Key
    if (-not $mouseFor.ContainsKey($c)) { $mouseFor[$c] = $m.Button }
}
$mouseTitle = if ($mouseDev) { $mouseDev } elseif ($n.device) { [string]$n.device } else { 'programmable mouse' }

# ---- mouse panel ----
$mouseHtml = ''
# The notes-driven pad is the fallback for a vendor whose profiles cannot be
# read. When a real iCUE profile WAS read, it supersedes this entirely - showing
# both would put every thumb button on the sheet twice, once from disk and once
# from a hand-written file that may already disagree with it.
if ($n.mouse -and $ShowMousePad -and -not $mouseRows.Count) {
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
        $mbc  = Get-KeyCanon $b.Key
        $mb   = if ($mouseFor.ContainsKey($mbc)) {
            "<b class=""ms"" title=""$(esc $mouseTitle) button"">$(esc $mouseFor[$mbc])</b>"
        } else { '' }
        $mark = if ($b.Source -eq 'your setting') { '' } else { '<span class="def" title="mod default - not rebound by you">&#9679;</span>' }
        @"
      <div class="row" data-s="$(esc "$($b.Action) $($b.Mod) $($b.Key)".ToLower())">
        <span class="act">$(esc $b.Action)<em>$(esc $b.Mod)$mark</em></span>
        <span class="keys">$mb$keys</span>
      </div>
"@
    }
    # One oversized panel sets the height of the whole sheet - a category with
    # three times the rows of its neighbours leaves half the screen empty below
    # the short panels. Split a tall panel's rows into internal columns and let
    # it claim proportionally
    # more width, and every panel ends up roughly the same height.
    $big = $set.Count -gt 12
    @"
  <section class="panel$(if ($big) { ' big' })">
    <h2><span class="dot $($accent[$c])"></span>$(esc $c)</h2>
    <div class="rows">$($rows -join '')</div>
  </section>
"@
}

# ---- mouse-profile panel (the join) ----
#
# Three columns, in the order the causation runs: the button you press, the key
# it sends, what the game does with that key. Read left to right it is a
# sentence; read as a table it is checkable.
$mpHtml = ''
if ($mouseRows.Count) {
    $deadRows = @($mouseRows | Where-Object { $_.Assigned -and -not $_.Hits.Count })
    $items = foreach ($m in $mouseRows) {
        # An action left on no button is not a control. It sits in the profile
        # doing nothing, and is listed only so the user is not left wondering
        # where a label they remember creating went.
        $cls = @()
        if (-not $m.Assigned)   { $cls += 'unassigned' }
        elseif (-not $m.Hits.Count) { $cls += 'dead' }
        $btn = if ($m.Assigned) { esc $m.Button } else { '&mdash;' }

        $does = if ($m.Hits.Count) {
            (($m.Hits | Sort-Object Mod, Action | ForEach-Object {
                "<span class=""pd"">$(esc $_.Action)<em>$(esc $_.Mod)</em></span>"
            }) -join '')
        } elseif ($m.Assigned) {
            '<span class="pd pnone">nothing on disk binds this key<em>this button does nothing in game</em></span>'
        } else {
            '<span class="pd pnone">on no button, and nothing binds the key either<em>inert both ways</em></span>'
        }
        @"
      <div class="prow$(if ($cls) { ' ' + ($cls -join ' ') })">
        <span class="pbtn">$btn</span>
        <kbd class="k">$(esc $m.Key)</kbd>
        <span class="pdoes">$does</span>
        <span class="plbl">$(esc $m.Label)</span>
      </div>
"@
    }

    # Lead with the finding, per the house rule. A dead button is invisible in
    # iCUE - it looks exactly like a working one - so if there is one, it is the
    # most useful sentence on the page.
    $deadLine = if ($deadRows.Count) {
        '<p class="foot warn"><b>' + $deadRows.Count + ' button' + $(if ($deadRows.Count -gt 1) { 's send keys' } else { ' sends a key' }) +
        ' nothing on this install is bound to</b> - ' +
        (($deadRows | ForEach-Object { "$(esc $_.Button) sends <kbd class=""k"">$(esc $_.Key)</kbd>" }) -join ', ') +
        '. Rebind the mod to the key the mouse sends, or the mouse to the key the mod listens for.</p>'
    } else {
        '<p class="foot ok">Every assigned button lands on something the game or a mod is listening for.</p>'
    }

    $otherLine = if ($mouseOther.Count) {
        '<p class="foot">' + $mouseOther.Count + ' more action' + $(if ($mouseOther.Count -gt 1) { 's' }) +
        ' in this profile send no keystroke at all (macros, DPI, launchers), so nothing on disk can describe them: ' +
        (($mouseOther | ForEach-Object { esc $_.Action }) -join ' &middot; ') + '.</p>'
    } else { '' }

    $mpHtml = @"
  <section class="panel wide mp">
    <h2><span class="dot yellow"></span>Mouse buttons<b>iCUE profile &ldquo;$(esc $mouseName)&rdquo;$(if ($mouseDev) { " &middot; " + (esc $mouseDev) })$(
      # WHICH profile these rows came from, on the sheet itself. The filenames
      # are GUIDs, so a user with several profiles cannot otherwise tell - and
      # naming it is what makes the difference between "iCUE says" and "the
      # Cyberpunk profile says", which are not the same claim.
      if ($mouseLinked) { ' &middot; auto-activates for Cyberpunk2077.exe' }
      elseif ($mouseAllCount -gt 1) { " &middot; $mouseAllCount profiles here, none linked to the game - this one has the most remaps" }
    )</b></h2>
    $deadLine
    <p class="foot">The mouse never performs a game action - it sends a <b>keystroke</b>, and the game or a mod decides what that means. So each row is the join: the button, the key it sends, and what is bound to that key on this install right now. The small grey line is your own label for the button in iCUE, which is the one thing here that can go stale.</p>
    <div class="pgrid">$($items -join '')</div>
    $otherLine
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
        # Name the mod per group only when the groups differ. Repeating one mod
        # name down every group is noise; naming none of them leaves the keys
        # unattributable, which is worse.
        $gmod = if ($g.mod -and -not $oneMod) { "<em>$(esc $g.mod)</em>" } else { '' }
        "<div class=""ggroup""><h3>$(esc $g.group)$gmod</h3>$($items -join '')</div>"
    }
    # When one mod owns every gesture, it IS the section - so name the section
    # after it rather than captioning it off to one side.
    $gtitle = if ($oneMod) { "$(esc $oneMod) gestures" } else { 'Vehicle gestures<b>tap &middot; hold &middot; multi-tap</b>' }
    $gestHtml = @"
  <section class="panel wide">
    <h2><span class="dot cyan"></span>$gtitle</h2>
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
# No key counts here. How many bindings exist is not something you look up, and
# the one fact this line has to carry is how stale the sheet is.
$subline = "READ FROM DISK $stamp"

# ------------------------------------------------------------------ markdown --
#
# The HTML sheet is for a second monitor; this is for pasting. It carries the
# same bindings and drops only what is purely visual - the mouse-pad diagram and
# the colour coding, neither of which survives as text anyway.

if ($Md) {
    $mb = [Text.StringBuilder]::new()

    # A pipe in a key name or a mod title ends the cell early and the rest of the
    # row lands in the wrong column.
    $cell = { param($x) ([string]$x) -replace '\|', '\|' }
    # The backtick key is the one that breaks its own code span: `` ` `` inside
    # single backticks renders as an empty span and swallows the key. Doubling
    # the fence and padding is the only form every renderer agrees on, and it
    # matters here because ` is a real, commonly bound Cyberpunk key.
    $bt   = [string][char]96
    $code = {
        param($x)
        $s = & $cell $x
        if ($s.Contains($bt)) { "$bt$bt $s $bt$bt" } else { "$bt$s$bt" }
    }

    [void]$mb.AppendLine('# Cyberpunk 2077 - hotkeys')
    [void]$mb.AppendLine()
    [void]$mb.AppendLine("Read from disk $stamp. An asterisk means the mod's own default, not a key you chose.")
    [void]$mb.AppendLine()
    foreach ($c in $order) {
        $set = @($binds | Where-Object Context -eq $c | Sort-Object Mod, Action)
        if (-not $set) { continue }
        [void]$mb.AppendLine("## $c")
        [void]$mb.AppendLine()
        [void]$mb.AppendLine('| Key | Action | Mod |')
        [void]$mb.AppendLine('| --- | --- | --- |')
        foreach ($b in $set) {
            $dot  = if ($b.Source -eq 'your setting') { '' } else { ' *' }
            [void]$mb.AppendLine("| $(& $code $b.Key) | $(& $cell $b.Action) | $(& $cell $b.Mod)$dot |")
        }
        [void]$mb.AppendLine()
    }
    if ($mouseRows.Count) {
        [void]$mb.AppendLine("## Mouse buttons - iCUE profile ""$mouseName""$(if ($mouseDev) { " ($mouseDev)" })")
        [void]$mb.AppendLine()
        [void]$mb.AppendLine('The mouse sends a keystroke; the game decides what it means. Button, key sent, what is bound to it.')
        [void]$mb.AppendLine()
        # Three columns, matching every other table in this file. The iCUE label
        # is folded into the button cell rather than given a fourth column: it is
        # the least trustworthy value here, and a paste-target file does not have
        # the width to spend on it.
        [void]$mb.AppendLine('| Button | Sends | What that key does |')
        [void]$mb.AppendLine('| --- | --- | --- |')
        foreach ($m in $mouseRows) {
            $does = if ($m.Hits.Count) {
                (($m.Hits | Sort-Object Mod, Action | ForEach-Object { "$(& $cell $_.Action) ($(& $cell $_.Mod))" }) -join '; ')
            } elseif ($m.Assigned) { '**nothing on disk binds this key**' }
            else { 'on no button; nothing binds the key either' }
            $btn = if ($m.Assigned) { "$(& $cell $m.Button) - $(& $cell $m.Label)" } else { "- $(& $cell $m.Label)" }
            [void]$mb.AppendLine("| $btn | $(& $code $m.Key) | $does |")
        }
        [void]$mb.AppendLine()
    }
    foreach ($g in $n.gestures) {
        [void]$mb.AppendLine("## $($g.group)$(if ($g.mod) { " - $($g.mod)" })")
        [void]$mb.AppendLine()
        foreach ($i in $g.items) {
            $steps = if ($i.steps) { ' (' + (($i.steps) -join ' > ') + ')' } else { '' }
            [void]$mb.AppendLine("- ``$($i.key)`` $($i.gesture) - $($i.does)$steps")
        }
        [void]$mb.AppendLine()
    }
    if ($collisions -and $ShowSharedKeys) {
        [void]$mb.AppendLine('## Shared keys')
        [void]$mb.AppendLine()
        [void]$mb.AppendLine('Bindings scope to an input context, so most of these never fire together.')
        [void]$mb.AppendLine()
        foreach ($g in $collisions) {
            $who = ($g.Group | ForEach-Object { "$($_.Action) ($($_.Context))" }) -join '; '
            [void]$mb.AppendLine("- ``$($g.Name)`` - $who")
        }
        [void]$mb.AppendLine()
    }

    $mdText = $mb.ToString()
    Set-Content -LiteralPath $Md -Value $mdText -Encoding UTF8
    Write-Host "wrote $Md" -ForegroundColor Green

    # DISCORD REFUSES a message over 2000 characters rather than clipping it, and
    # a full key sheet is comfortably over. Somebody pasting this to ask for help
    # finds out at the worst moment, so say it here instead.
    if ($mdText.Length -gt 2000) {
        Write-Host ("  $($mdText.Length) chars - too long for one Discord message (2000 max); attach the file or paste one section" ) -ForegroundColor DarkYellow
    }
}


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
/* The mod name goes on its own line, under the action.
   Inline it competes with the action for the same line and wraps mid-phrase -
   "Toggle night vision Kiroshi Night / Vision" - which splits the action name
   in half and leaves every row a different height, so nothing scans. On its own
   line the action stays one clean line and rows stay uniform.
   It still wraps rather than being held on one line: held, a long name like
   "Character Customization Anywhere" set a hard floor on the row width and
   pushed the keycap off the page. */
.act em{display:block;font-style:normal;font-size:calc(var(--fs)*.5);color:#6a6a80;
  font-family:var(--mono);letter-spacing:.03em;margin-top:3px;line-height:1.2}
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

/* ---- mouse profile: the button -> key -> binding join ---- */
/* Wider tracks than the other grids on the sheet, and deliberately so: the
   third column can hold several bindings (one key can be claimed by the base
   game AND two mods), and at 380px those wrapped to four lines each, which set
   the height of every cell in the row. */
.pgrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:10px}
/* Two stacked paragraphs of explanation cost more vertical space than they are
   worth on a sheet that is meant to fit one screen. */
.pgrid+.foot,.foot+.foot{margin-top:-2px}
/* Three cells across the top row, the iCUE label spanning underneath. The
   button and the keycap are fixed-width so every row's third column starts at
   the same x - the whole point is scanning down "what does it actually do". */
.prow{display:grid;grid-template-columns:auto auto 1fr;gap:10px;align-items:baseline;
  background:#15151f;border:1px solid #2b2b40;border-left:3px solid var(--yellow);padding:7px 12px}
/* This panel is the last thing added to a sheet that already fitted one screen,
   so it pays for itself in millimetres: tighter prose margins here rather than
   a smaller --fs everywhere, which would shrink the keys people actually read. */
.panel.mp{padding-bottom:11px;margin-top:11px}
.panel.mp .foot{margin:7px 0 6px}
.pbtn{font-family:var(--mono);font-size:calc(var(--fs)*.62);font-weight:700;color:var(--yellow);
  background:rgba(252,238,10,.1);border:1px solid rgba(252,238,10,.45);border-radius:3px;
  padding:3px 8px;min-width:3.1em;text-align:center;white-space:nowrap}
.pdoes{display:flex;flex-direction:column;gap:4px;min-width:0}
.pd{font-size:calc(var(--fs)*.7);line-height:1.25;overflow-wrap:anywhere}
.pd em{display:block;font-style:normal;font-family:var(--mono);font-size:calc(var(--fs)*.47);
  color:#6a6a80;letter-spacing:.03em;margin-top:2px}
/* The user's own name for the button, from iCUE. Deliberately the quietest
   thing in the row: it is a note they typed, not something read from the game,
   and it is the only cell on this sheet that can be out of date. */
.plbl{grid-column:1/-1;font-family:var(--mono);font-size:calc(var(--fs)*.45);color:#5a5a70;
  letter-spacing:.08em;text-transform:uppercase;line-height:1;margin-top:2px}
/* A dead button looks identical to a working one in iCUE. On the sheet it must
   not. */
.prow.dead{border-left-color:var(--red)}
.prow.dead kbd.k{color:var(--red);border-color:#4a1024}
.prow.unassigned{border-left-color:#3a3a52;opacity:.62}
.pnone{color:var(--red)}
.prow.unassigned .pnone{color:var(--dim)}
.foot.warn{color:#ffb3c4} .foot.warn b{color:var(--red)}
.foot.ok b,.foot.ok{color:var(--green)}
.foot kbd.k{padding:2px 7px;font-size:calc(var(--fs)*.62)}

/* ---- collisions ---- */
.cgrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(340px,1fr));gap:10px}
.crow{display:flex;gap:12px;align-items:flex-start;background:#15151f;border:1px solid #2b2b40;padding:11px 13px}
.crow kbd.k{color:var(--red);border-color:#4a1024}
.cwho{flex:1;display:flex;flex-direction:column;gap:4px}
.cw{font-size:calc(var(--fs)*.68);line-height:1.3}
.cw b{font-family:var(--mono);font-size:calc(var(--fs)*.5);letter-spacing:.1em;text-transform:uppercase;
  color:var(--dim);font-weight:400;margin-right:7px}
.cw em{font-style:normal;color:var(--dim);font-size:calc(var(--fs)*.55);font-family:var(--mono)}

/* Spread across the full width instead of stacking into a cramped block in the
   corner - there is a whole empty page width down here to use. */
footer{margin-top:14px;padding-top:9px;border-top:1px solid var(--line);
  font-family:var(--mono);font-size:calc(var(--fs)*.5);color:#4c4c60;line-height:1.5;
  display:flex;flex-wrap:wrap;gap:10px 34px;align-items:baseline}
footer span:last-child{margin-left:auto}
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
  <button id="modtoggle" class="pill" title="show or hide which mod each binding belongs to">mod names</button>
  <span id="hits"></span>
</div>

<div class="cols">
$mouseHtml
$($catHtml -join '')
</div>

$mpHtml
$gestHtml
$colHtml

<footer>
  <span>Keys read from r6\input\*.xml &middot; r6\cache\inputUserMappings.xml &middot; red4ext\plugins\mod_settings\user.ini &middot; cyber_engine_tweaks\bindings.json &middot; cyber_engine_tweaks\mods\*\*.json</span>
  $(if ($mouseName) { "<span>Mouse buttons read from %APPDATA%\Corsair\CUE5\profiles &middot; profile &ldquo;$(esc $mouseName)&rdquo;</span>" })
  <span>&#9679; mod default you have not rebound</span>
  <span>Generated $stamp // CYBERWISE</span>
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
// Off by default: the keys are what you glance at, and which mod owns a binding
// only matters when you go looking for something to change.
let modsOn = false;
try { modsOn = localStorage.getItem('cw_modnames') === '1'; } catch (e) {}
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
