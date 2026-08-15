---
name: cyberwise
description: Diagnose Cyberpunk 2077 mod problems - load order and conflicts, archive internals, redscript and CET failures, save and appearance data, TweakDB edits, ReShade stacks. Use when a mod is installed but does nothing, when textures or body parts look wrong, when the game hangs or crashes after a mod change, or when reading CP2077 logs, .archive files, saves or ACU presets.
---

# Cyberwise

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> Every file under `references/` carries its own verification stamp and a
> **Re-check after a patch** line naming what to re-test first. Trust those over
> this one; some areas drift much faster than others.

Field notes for diagnosing a modded Cyberpunk 2077 install. This assumes you can
already read a log and install a mod. What follows is the set of things that are
**counterintuitive, undocumented, or actively contradicted by popular advice** -
each one learned by getting it wrong first.

## Method, before anything else

These four cost the most time when skipped.

**Find out how the install is assembled before you trust the filesystem.** Manual,
Vortex and MO2 present completely different pictures on disk, and nearly every
technique here reads the disk. In particular, **an MO2 install may show you an
almost empty game directory** - it virtualises mods through USVFS and its Root
Builder plugin copies files in at launch and removes them when the game closes. On
such an install "the file isn't there" is not evidence of anything. Detection recipe
and per-manager consequences: `references/environment.md`.

**Confirm the mod is actually deployed before theorising about why it fails.**
Hours have gone into explaining the behaviour of a mod that was staged in the mod
manager but never deployed to the game. Check the file is on disk under the game
directory - or, on a virtualising setup, check the manager's own view. Every time.

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

**Always dereference an internal name to what the mod manager calls it.** Folder
names, TweakXL namespaces, redscript modules and archive filenames are authored by
mod authors for themselves and routinely bear no resemblance to the name a user sees
in their manager. Telling someone "`ChipwareExpansion` is doing this" leaves them
unable to find it. Say **Neuralware - Chipware Expansion (Nexus 19798)** and they
can act. Recipe per manager: `references/environment.md`.

**Do not hand your own guesses back to the user as their statements.** Naming a
mod you inferred and then writing "the mod is X, not Y" - as though they had said
Y - wastes a turn and costs trust. If you worked something out, say you worked it
out.

**What the user saw in game outranks what a mod page says.** They are running the
build; documentation describes intent. When their observation contradicts your
source, the source is what is wrong, and arguing the point is a waste of a turn.

## The load-order rule is backwards from most guides

**Earlier in `archive/pc/mod/modlist.txt` WINS.** Popular advice says to prefix a
mod with `zzz_` so it "loads last and wins". That is wrong for an install that
uses `modlist.txt`.

Consequences that follow, and they matter more than the rule itself:

- **A catch-all AIO retexture belongs LATE in the list**, so specific mods beat it.
- **Newly installed archives get appended to the end**, which is the bottom of the
  priority stack. Every mod the user installs starts out losing every file it
  contests. Re-check conflicts after *any* mod change - install, update, uninstall
  or variant swap - however your install is assembled.
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

**Some archives are written at runtime.** At least one known mod (Dynamic Moon
Phases) generates its `.archive` from an ASI at game start, so the file appears and
vanishes between sessions. The mod ships no archive of its own, so there is nothing
to compare against wherever your installed copies live. Never prune its entry as
stale - and note it still needs a permanent slot in `modlist.txt`, because an
unlisted archive sorts last and loses.

## Included tool

`tools/New-ModManifest.ps1` generates a readable inventory of an installed load
order - what every mod is, what it deploys, and (with a Nexus API key) what it
does. No mod manager shows this in one place.

It works offline because managers encode `<Display Name>-<NexusID>-<version>-<timestamp>`
into the staging folder name, which yields the name, a working URL and the install
date with no credentials at all. `-NexusApiKey` adds one-line summaries, author,
category and the real adult-content flag, cached to disk so re-runs are free.
`-HideNSFW` omits adult mods.

Two things worth knowing before trusting its NSFW filter:

- **Without an API key it is a name heuristic and it under-detects.** On a
  846-mod list it caught 17. Adult mods with innocuous names sail past.
- **Flags propagate across a shared Nexus ID**, because one Nexus page carries one
  adult flag but can ship many separately-named files. That alone caught 7 of
  those 17 - a set of character add-ons named only for the character, whose parent
  page was flagged. Any per-file heuristic that ignores the ID grouping will miss
  them.

The generated report contains the user's actual mod list. Treat it as personal:
write it outside any repo, and never commit it.

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
| `references/environment.md` | mod manager behaviour, settings store, compile-testing, tooling traps |
| `references/input-bindings.md` | the four binding stores, `overridableUI` overrides, CET's packed key codes |
