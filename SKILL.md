---
name: cyberwise
description: Diagnose Cyberpunk 2077 mod problems - load order and conflicts, archive internals, redscript and CET failures, save and appearance data, TweakDB edits, ReShade stacks. Use when a mod is installed but does nothing, when textures or body parts look wrong, when the game hangs or crashes after a mod change, or when reading CP2077 logs, .archive files, saves or ACU presets.
---

# Cyberwise

Field notes for diagnosing a modded Cyberpunk 2077 install. This assumes you can
already read a log and install a mod. What follows is the set of things that are
**counterintuitive, undocumented, or actively contradicted by popular advice** -
each one learned by getting it wrong first.

## Method, before anything else

These four cost the most time when skipped.

**Confirm the mod is actually deployed before theorising about why it fails.**
Hours have gone into explaining the behaviour of a mod that was staged in the mod
manager but never deployed to the game. Check the file is on disk under the game
directory. Every time.

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

## The load-order rule is backwards from most guides

**Earlier in `archive/pc/mod/modlist.txt` WINS.** Popular advice says to prefix a
mod with `zzz_` so it "loads last and wins". That is wrong for an install that
uses `modlist.txt`.

Consequences that follow, and they matter more than the rule itself:

- **A catch-all AIO retexture belongs LATE in the list**, so specific mods beat it.
- **Newly installed archives get appended to the end**, which is the bottom of the
  priority stack. Every mod the user installs starts out losing every file it
  contests. Re-check conflicts after *any* deploy.
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
vanishes between sessions. It ships nothing in staging. Never prune its entry as
stale - and note it still needs a permanent slot in `modlist.txt`, because an
unlisted archive sorts last and loses.

## Reference material

| file | covers |
|---|---|
| `references/load-order.md` | verifying override direction, precedence rules, inert detection |
| `references/archives.md` | RDAR index format, FNV1a-64 path hashing, hash dictionaries and their gaps |
| `references/diagnosis.md` | which log says what, crash vs hang, isolating a bad mod |
| `references/saves-and-appearance.md` | save decompression, appearance data, ACU preset format |
| `references/cet-lua.md` | CET sandbox limits, console cheats that work and that don't |
| `references/tweakdb-and-text.md` | TweakXL authoring, finding real record IDs, locating game text |
| `references/reshade.md` | add-on build, shader pack collisions, known incompatibilities |
| `references/environment.md` | mod manager behaviour, settings store, compile-testing, tooling traps |
