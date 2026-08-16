---
name: cyberwise-conflicts
description: Cyberpunk 2077 load order and mod conflicts - why earlier in modlist.txt wins, detecting archives that are installed but contributing nothing, and visual bugs that are not conflicts at all. Use when a mod is installed and enabled but does nothing, when textures or body parts look wrong or mismatched, when two mods fight, or when reading .archive internals.
---

# Cyberwise: conflicts and load order

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> **Re-check after a patch:** Confirm override direction still favours earlier entries before trusting any precedence work.

Load `cyberwise` alongside this for the method rules - especially **confirm the
mod is actually deployed** and **check your evidence discriminates**, both of
which this topic violates constantly.

Two of those are worth repeating here because getting them wrong wastes the most
time in *this* area specifically:

- **Find out how the install is assembled first.** On a virtualising setup (MO2)
  the game directory may look empty with the game closed, so "the archive isn't
  there" proves nothing.
- **Dereference internal names.** Telling someone `###AAblud.archive` is losing
  leaves them unable to find it in their manager.

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
- **`#` is a filename character, not a comment marker.** Mods use a leading `#`
  to sort early, so a parser that strips `^#` as comments silently drops real
  entries and then reports them as unlisted. Full detail and the sanity checks in
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
concluding anything from its behaviour - the compile-test recipe is in the
`cyberwise` skill's `environment.md`, not this one.

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

## Reference material

| file | covers |
|---|---|
| `references/load-order.md` | verifying override direction, precedence rules, inert detection, the `#` parsing trap |
| `references/archives.md` | RDAR index format, FNV1a-64 path hashing, hash dictionaries and their gaps |

To inventory what is actually installed before diagnosing, `cyberwise-reports`
carries the manifest tool.
