---
name: cyberwise
description: Diagnose Cyberpunk 2077 mod problems - load order and conflicts, archive internals, redscript and CET failures, save and appearance data, TweakDB edits, ReShade stacks. Use when a mod is installed but does nothing, when textures or body parts look wrong, when the game hangs or crashes after a mod change, or when reading CP2077 logs, .archive files, saves or ACU presets.
---

# Cyberwise

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> Every file under `references/` carries its own verification stamp and a
> **Re-check after a patch** line naming what to re-test first. Trust those over
> this one; some areas drift much faster than others.

Field notes for diagnosing a modded Cyberpunk 2077 install, at any scale, under any
mod manager or none. This is not a modding tutorial - installing a mod and finding
a log are assumed to be covered elsewhere. What follows is the set of things that
are **counterintuitive, undocumented, or actively contradicted by popular advice** -
each one learned by getting it wrong first.

Findings here are empirical, and most of the measuring happened on one large
Vortex-managed install. Two consequences for how to use them. Where a claim is
manager-specific, it names the manager - treat the same claim on another manager
as untested rather than false. And where a worked example carries a big number,
the number is that install's, not a threshold: the mechanisms fire identically on
a twenty-mod list, they just fire less often.

## Method, before anything else

These cost the most time when skipped.

**Find out how the install is assembled before you trust the filesystem.** Manual,
Vortex and MO2 present completely different pictures on disk, and nearly every
technique here reads the disk. In particular, **an MO2 install may show you an
almost empty game directory** - it virtualises mods through USVFS and its Root
Builder plugin copies files in at launch and removes them when the game closes. On
such an install "the file isn't there" is not evidence of anything. Detection recipe
and per-manager consequences: `references/environment.md`.

**Confirm the mod is actually deployed before theorising about why it fails.**
Hours have gone into explaining the behaviour of a mod that was staged in a mod
manager but never deployed to the game - and the manual-install equivalent, an
archive unpacked one folder too deep, fails just as silently. Check the file is on
disk under the game directory - or, on a virtualising setup, check the manager's
own view. Every time.

**Reproduce before bisecting.** One crash or hang is not a deterministic fault.
Confirm it repeats before halving anything, or you will bisect noise and "fix" it
by coincidence.

**Check your evidence actually discriminates.** When testing "does earlier win or
later win", make sure the two hypotheses predict *different* winners for the case
you are looking at. In CP2077 this bites constantly: mods prefixed `#`/`!` sort
early alphabetically and are usually placed early in load order too, so
"earlier-in-list wins" and "later-alphabetically wins" often predict the same
outcome. Three such cases prove nothing. Find a pair where the orders disagree.

**Never quote a mod's shipped defaults as the user's configuration.** Read the
actual settings store (see `references/environment.md`). A mod's `.reds` or `.xml`
declares what the author shipped, not what the user set.

**Keybinds are a special case of that, and there are five stores, not one.** The
mod's `r6\input\*.xml` holds only a default; `mod_settings\user.ini` holds the
rebind that beats it; CET keeps its own in packed integers; and some CET mods
ignore that registry and keep private json. Read all of them before stating what
a key does - and never conclude a key is free because you could not find it.
`references/input-bindings.md`.

**Always dereference an internal name to something the user can find.** Folder
names, TweakXL namespaces, redscript modules and archive filenames are authored by
mod authors for themselves and routinely bear no resemblance to the name the user
sees - in a manager's list, or in their own notes on a manual install. Naming only
the internal string ("`ChipwareExpansion` is doing this") leaves them unable to act.
Give the display name, and the Nexus ID where one is recoverable. Where it is *not*
recoverable - a manual install has no mapping from a deployed file back to a mod -
say that instead of guessing. Recipe per manager: `references/environment.md`.

**Do not hand your own guesses back to the user as their statements.** Naming a
mod you inferred and then writing "the mod is X, not Y" - as though they had said
Y - wastes a turn and costs trust. If you worked something out, say you worked it
out.

**What the user saw in game outranks what a mod page says.** They are running the
build; documentation describes intent. When their observation contradicts your
source, the source is what is wrong, and arguing the point is a waste of a turn.

## The load-order rule is backwards from most guides

**Earlier in `archive\pc\mod\modlist.txt` WINS.** Popular advice says to prefix a
mod with `zzz_` so it "loads last and wins". That is wrong for an install that
uses `modlist.txt`.

Whether it does is a property of the install, not of the game version: nothing in
the game writes that file, so it exists only if a manager, a conflict tool or the
user put it there. **Look for the file before applying any of this** - with no
`modlist.txt` the game falls back to alphabetical, and a manager that sequences
mods in its own UI is a third case whose specifics were not tested here. The
reasoning transfers; the specifics should be checked.

Consequences that follow where the file is in play, and they matter more than the
rule itself:

- **A catch-all AIO retexture belongs LATE in the list**, so specific mods beat it.
- **New archives get appended to the end** by whatever writes `modlist.txt`, which
  is the bottom of the priority stack. Every mod the user installs starts out
  losing every file it contests. Re-check conflicts after *any* mod change -
  install, update, uninstall or variant swap - however the install is assembled.
- `modlist.txt` is a deliberate custom order, not a fossil and not alphabetical.
  Never delete it to "fall back to alphabetical".

Full detail, including how to verify the direction on an unfamiliar install:
`references/load-order.md`.

## "Installed and enabled" is not "doing anything"

An archive whose files are *all* owned by something earlier is **inert** - present,
enabled, and contributing nothing. This is the single most common silent failure.

**Compare loss count against total file count.** Losing 1 file of 60 is a cosmetic
overlap. Losing 1 of 1 is a dead mod.

**But an inert ARCHIVE does not mean an inert MOD.** Before advising an uninstall,
check the rest of the payload. A mod's real content may be a CET Lua file, an
entSpawner registration, a `.reds` script or an `.xl` - none of which appear in an
archive conflict scan. Uninstalling on archive evidence alone has destroyed
working functionality.

**The same trap exists outside archives.** If redscript fails to compile, *every*
`.reds` mod on the install is silently off, with no in-game sign - on one install
that state went unnoticed for eight months. And a RED4ext plugin whose DLL fails to
load never compiles its scripts either. Verify the thing is actually running before
concluding anything from its behaviour. See `references/environment.md`.

## Many visual bugs are not conflicts at all

A conflict checker showing zero conflicts does not mean two mods agree. Cases seen:

- **Appearance (`.app`) overrides.** A mod can override
  `player_base_bodies\appearances\*.app` and point a body part at a different
  texture set entirely. No hash collision, completely different look.
- **Coverage gaps.** A "skin tone" patch may only ship torso and arm textures. The
  legs then keep whatever the underlying body mod supplies, and the two will never
  match. No load order change can fix missing content.
- **Patch mods layered on other mods' namespaces.** Paths like `base\4k\...`,
  `base\v_textures\...`, `base\characters\player\femme\...` are not vanilla. An
  archive full of them is a recolour layer over another mod, not a standalone
  texture, and it is useless without its base.

When a body part looks wrong, resolve *which file actually supplies it* before
touching load order. See `references/archives.md`.

**And before you promise a reorder, check the problem is one reordering can solve.**
Three situations look identical in a conflict report: a lost fight (fixable), a
coverage gap where only one mod ships the file at all (not fixable - no ordering
conjures content), and two mods claiming the same single resource where the user
wants both (impossible; say so instead of shuffling). Afterwards, **re-scan for
newly inert archives** - promoting one mod can silently kill a third party nobody
mentioned. `references/load-order.md`.

## Know where each kind of mod lives

Not everything deploys to `archive\pc\mod`. A mod "missing" from there may simply
not belong there:

| kind | location |
|---|---|
| archives | `archive\pc\mod\` |
| REDmod | `mods\<name>\archives\` |
| ASI plugins | `bin\x64\plugins\` |
| CET mods | `bin\x64\plugins\cyber_engine_tweaks\mods\<name>\` |
| RED4ext plugins | `red4ext\plugins\<name>\` |
| redscript | `r6\scripts\<name>\` |
| TweakXL | `r6\tweaks\` |
| input binds | `r6\input\*.xml` |

All of those are relative to the game root, wherever this install put it - Steam,
GOG and Epic all differ, and the drive is whatever the user chose. Establish the
root once and build paths from it; never assume a default install location.

**Some archives are written at runtime.** At least one known mod (Dynamic Moon
Phases) generates its `.archive` from an ASI at game start, so the file appears and
vanishes between sessions. Because the mod ships no archive of its own, any check
that compares deployed archives against installed copies - a manager's staging
folders, or a manual installer's own record - reports it as an orphan. Never prune
its entry as stale, and note it still needs a permanent slot in `modlist.txt`,
because an unlisted archive sorts last and loses.

## Included tools

- `tools/New-ModManifest.ps1` - inventory of an installed load order (below).
- `tools/Get-Hotkeys.ps1` - every keybind on an install, from all five stores
  that hold them. `tools/New-HotkeySheet.ps1` renders it as a cheatsheet.
  `references/input-bindings.md`.
- `tools/New-SystemProfile.ps1` - the machine and install facts that actually
  change a diagnosis, as Discord-pasteable markdown and an HTML report, led by a
  flags section saying what is likely to be the problem. Start here when someone
  arrives with "it's broken" and no detail.
- `tools/Show-ViewportProbe.ps1` - asks the user's own browser window how big it
  is, so a layout is sized for the window they will read it in.
- `tools/Measure-PageFit.ps1` - does a generated page fit a given viewport.
- `tools/NexusCredential.ps1` - Nexus API key in Windows Credential Manager.

**Pass the paths explicitly.** These scripts carry defaults for a game root, a
staging root and a viewport, and those defaults are one author's machine - a
Steam library path, a Vortex staging tree, a single monitor's resolution. Find the
real values for the install in front of you (or ask) and pass `-GameRoot`,
`-StagingRoot`, `-Width`/`-Height`. A default that happens to exist on the wrong
machine is worse than an error, because the output looks plausible.

`tools/New-ModManifest.ps1` generates a readable inventory of an installed load
order - what every mod is, what it deploys, and (with a Nexus API key) what it
does. No mod manager shows this in one place.

**It reads a manager's staging root, not the game directory.** A Vortex-style
staging root is auto-detected; anything else needs `-StagingRoot` pointed at it
(for MO2, its `mods\` folder). A fully manual install has no staging tree and no
per-mod folders, so the tool has nothing to walk - the mod-kind table above is
still a useful model there, but the script is not.

Most of it works offline because a manager that installed from Nexus encodes
`<Display Name>-<NexusID>-<version>-<timestamp>` into the staging folder name,
which yields the name, a working URL and the install date with no credentials at
all. That naming is Vortex's; MO2 folder names are whatever was set at install
time and are user-editable, so on MO2 expect the name only and no ID or date for
folders that were renamed. `-NexusApiKey` adds one-line summaries, author,
category and the real adult-content flag, cached to disk so re-runs are free.
`-HideNSFW` omits adult mods.

Two things worth knowing before trusting its NSFW filter, both measured on one
846-mod install:

- **Without an API key it is a name heuristic and it under-detects.** On that
  install it caught 17. Adult mods with innocuous names sail past.
- **Flags propagate across a shared Nexus ID**, because one Nexus page carries one
  adult flag but can ship many separately-named files. That alone caught 7 of
  those 17 - a set of character add-ons named only for the character, whose parent
  page was flagged. Any per-file heuristic that ignores the ID grouping will miss
  them.

The generated report contains the user's actual mod list. Treat it as personal:
write it outside any repo, and never commit it.

## Building an HTML deliverable? Measure it, do not eyeball it

Any generated page a user will actually live with - a cheatsheet, a manifest, a
report - has a fit requirement, and **you cannot judge it from a screenshot.**
Screenshots arrive downscaled by an unknown factor, so the viewport you are sizing
for is a guess. Guessing it wrong looks exactly like a styling problem and produces
rounds of "still too small".

**Run `tools/Measure-PageFit.ps1` after every layout change.** It renders the
page headless at a stated viewport and returns the document height, the viewport
height, and the class of anything overflowing horizontally:

```powershell
.\Measure-PageFit.ps1 -Path page.html -Width <px> -Height <px> -Screenshot -ShotPath shot.png
```

**Get the viewport from the user, not from the screen.** Run
`tools/Show-ViewportProbe.ps1`, and ask them to put the browser window on the
monitor they will actually read it on, at the size they will actually use, then
read back the number it shows. Detecting the display assumes maximised on the
primary at 100% zoom, and cannot express "the little side panel" or "half-width
on monitor 2" at all.

Then say what that viewport implies rather than silently designing to it: on a
small one, agree what earns the top of the page and accept scrolling for the
rest; on a TV, scale the type up hard. An unreadable page that fits is not a win.

And look at the output, not just the number: pass `-Screenshot` and read the
image. The measurement catches what you cannot see; the screenshot catches what a
number cannot describe. Full house style for these artefacts, both HTML and
markdown: `references/report-design.md`.

Two failure modes a screenshot cannot show you:

- **An element pushed clean off the page.** A long inline label with
  `white-space:nowrap` forced its row wider than the container and shoved a
  keycap past the right edge - not clipped, not squeezed, *absent*. Only the
  overflow probe named it.
- **A layout that "fits" because the flag was ignored.** In PowerShell,
  `--window-size=$W,$H` unquoted parses as an **array**, passing two arguments,
  so the browser silently renders at its 800x600 default. Quote it.

Also: **CSS multi-column is not a way to fill a wide screen.** It derives its own
column count and balances into it; in the case that produced this note a 3000px
container settled on two columns and left two thirds empty. Flex with `flex-wrap`
fills the row.

And when testing a page that restores its own state on load, drive the real
control - a class forced onto `<body>` is stripped by the page's restore logic
before anything is measured, which reads as a feature that does nothing.

## Reference material

| file | covers |
|---|---|
| `references/load-order.md` | verifying override direction, precedence rules, inert detection |
| `references/archives.md` | RDAR index format, FNV1a-64 path hashing, hash dictionaries and their gaps |
| `references/diagnosis.md` | which log says what, locating a visual symptom, failure shapes |
| `references/bisecting.md` | parking files, layer-first search, why automated hang detection fails |
| `references/crashes.md` | CrashInfo.json, why WER never fires, memory measurement traps |
| `references/saves-and-appearance.md` | save decompression, appearance data, ACU preset format |
| `references/cet-lua.md` | CET sandbox limits, console cheats that work and that don't |
| `references/tweakdb-and-text.md` | TweakXL authoring, finding real record IDs, locating game text |
| `references/reshade.md` | add-on build, shader pack collisions, known incompatibilities |
| `references/report-design.md` | house style for generated reports: palette, layout, Discord constraints, verifying headless |
| `references/environment.md` | mod manager behaviour, settings store, compile-testing, tooling traps |
| `references/input-bindings.md` | the five binding stores, `overridableUI` overrides, CET's packed key codes |
