# Diagnosing a broken install

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> **Re-check after a patch:** Log paths move when RED4ext, ArchiveXL, TweakXL or CET update. Verify each path exists before concluding a log is empty rather than relocated - or simply absent because that framework was never installed here.

## Which log says what

| log | tells you |
|---|---|
| `red4ext\logs\red4ext.log` | plugin load order and versions - the reliable place to check what version a plugin actually is |
| `red4ext\plugins\ArchiveXL\ArchiveXL-*.log` | whether `.xl` patches applied. Read this after **every** `.xl` change |
| `red4ext\plugins\TweakXL\TweakXL-*.log` | whether a `.yaml` was read and whether it errored |
| `r6\logs\redscript_*.log` | redscript compilation. Rotates at 5 files |
| `r6\logs\scripting.log` | runtime script errors |
| `bin\x64\plugins\cyber_engine_tweaks\cyber_engine_tweaks.log` | CET framework |
| `...\cyber_engine_tweaks\mods\<name>\<name>.log` | per-CET-mod errors, including ones thrown outside your own pcall |

**Every path above is relative to the game root** - the folder containing
`bin\x64\Cyberpunk2077.exe`, wherever this particular Steam, GOG or Epic install
happens to live. Establish that root once, ask if it is not obvious, and join
everything to it. Never assume a drive letter or a library path.

**A missing log is not a silent log.** None of these frameworks ship with the game:
REDscript, RED4ext, CET, ArchiveXL and TweakXL are separate downloads, usually
pulled in as dependencies by whichever mods need them, and no install has all of
them by default. A list of twenty archive-only retextures legitimately has none,
and `r6\logs\` may not exist at all. Work out which frameworks are actually present
before reading meaning into an absent log - and before proposing a fix that assumes
one is there.

**ArchiveXL's log is the one people forget.** A sector patch that fails logs
"No patches have been applied" and reverts *everything* in that file - so a single
malformed entry looks exactly like total mod failure.

## Locate a visual symptom before theorising about it

**Establish where the camera is.** "All the NPCs are grey" and "NPCs are grey in a
mirror" are different bugs with completely disjoint suspect lists. In one case the
report was scene-wide, the reality was a single NPC seen in one bathroom mirror, and
several rounds were lost proposing scene-wide causes. The culprit was a **mirror
mod**, and the symptom only ever existed in reflections.

Three surfaces worth separating, because each has its own suspects:

| where it looks wrong | look at |
|---|---|
| world rendering | skin/body texture mods, load order |
| mirrors and reflections | mirror and reflection mods |
| character creator / paperdoll | UV frameworks, appearance-mod facial archives, paperdoll overrides |

Character-creator faults in particular - black skin, missing body parts, missing
teeth - are usually **not** caused by the skin textures you would suspect from the
world view. Known causes have included a UV framework build (fixed by switching to
its REDmod version) and an appearance mod's facial/paperdoll archives.

## Failure shapes

**Game hangs at new game / loading** - a quest or scene mod. Bisect by disabling
groups, but reproduce first. A single hang is not proof.

**Game reaches gameplay then dies after ~30-60 seconds with nothing in any log** -
if ReShade is installed, suspect an incompatible add-on there before suspecting
game mods. See `reshade.md`. (Ask whether ReShade is in play; it is an injector
installed outside any mod manager, so it will not appear in a mod list.)

**Mod installed, no error anywhere, no effect** - almost always load order (inert
archive) or a `.xl` that failed silently. Check ArchiveXL's log, then check whether
the archive owns any of its own files.

**Visual mismatch between body parts** - not a conflict. See `archives.md`.

**A setting does nothing** - verify you are reading the user's real settings store,
not a mod's shipped defaults. See `environment.md`.

## ArchiveXL `nodeDeletions`, the two rules

Both learned by breaking a working file:

1. **`type` must be the node's real `$type` from the sector.** Mesh props are often
   `worldMeshNode`, **not** `worldStaticMeshNode` - their `debugName` reads
   "[Static Mesh] ..." which is actively misleading. Generate the type from the
   sector data; never type it by hand.
2. **One bad entry voids the entire sector patch.** Every deletion in the file
   reverts, and the log says "No patches have been applied". A single wrong type
   therefore presents as "the whole mod stopped working".

Always re-read the ArchiveXL log after editing a sector patch.

**It works on another mod's sector, not just a vanilla one.** `nodeDeletions` is
documented against vanilla sector paths, but pointing it at a path a *mod* added
works too - confirmed in game by deleting props from a modded interior.

That is worth knowing for what it saves: removing objects from someone else's mod
needs **no repacking of their archive at all**. Ship a companion `.xl` that sorts
after theirs, and the edit survives every update of the mod it modifies, because
their files are never touched. Editing their archive instead is undone by the
next update and has to be redone by hand each time.

## Bisecting responsibly

- Reproduce the fault at least twice before halving anything.
- Change one variable per test and write down what you changed.
- Prefer disabling *groups* by function (all appearance mods, all quest mods) over
  alphabetical halves - related mods fail together.
- When a suspect is found, confirm by **re-enabling it alone**, not just by the
  absence of the fault.
- On a short mod list, do not halve anything - start from what changed most
  recently. Full method and how it scales up and down: `bisecting.md`.

## Things that look like mod bugs and are not

- **Quest facts live in the save.** Setting a fact from the console and then loading
  a save discards the change. Fact edits must happen on game attach, from a script.
- **Vendor inventories are rolled once and persisted.** A TweakDB change to stock
  will not appear until the vendor restocks (skip ~24 in-game hours).
- **Input mappings load at startup.** Editing `r6\input\*.xml` requires a full game
  restart, not a save reload.
- **Cyberware cannot be changed outside a ripperdoc** since 2.0, including from the
  console. See `cet-lua.md`.
