# Load order

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> **Re-check after a patch:** Confirm override direction still favours earlier entries before trusting any precedence work. The append-on-install behaviour belongs to whatever writes modlist.txt, so it can change without a game patch.

## Verifying override direction on an unfamiliar install

Do not assume. Two models are in play and they are frequently confused:

- **`modlist.txt` present** - the file defines an explicit order and **earlier
  wins**. Tools that manage it usually say so in their own UI ("higher
  overrides").
- **`modlist.txt` absent** - the game falls back to alphabetical.

To prove which applies, you need a conflicting pair where **list order and
alphabetical order agree in direction**. If they disagree, both hypotheses predict
the same winner and the test tells you nothing.

Worked example of a *useless* test:

| pair | list order | alphabetical | earlier-wins predicts | later-alpha-wins predicts |
|---|---|---|---|---|
| `Skin Textures` (65) vs `###Better Skin` (66) | Skin Textures first | ###Better Skin first | Skin Textures | Skin Textures |

Both models name the same winner. Mods prefixed `#`, `!` or `~` sort early alphabetically
*and* tend to be placed early in the list, so this correlation is the norm, not the
exception. Three such pairs still prove nothing.

## The append trap

Whatever writes `modlist.txt` appends new archives at the **end**. Under
earlier-wins the end is the bottom of the priority stack, so:

> Every newly installed or variant-swapped mod starts out losing every file it
> contests.

This has silently killed the same retexture twice in one session - once under its
original filename, again after a variant swap produced a new filename that was
appended fresh. **Re-check after every deploy.** If the user has a load-order
repair script, run it; if not, the check is: for each archive, does it own any of
its own files?

## Detecting inert archives

An archive is inert when *every* hash it carries is also carried by something
earlier in the list.

- Parse each archive's index (see `archives.md`) into a hash set.
- Walk `modlist.txt` in order, assigning each hash to the first archive that claims it.
- Any archive that ends up owning zero of its own hashes is inert.

Cheap: roughly 700 archives parse in under 10 seconds, index-only, no decompression.

**Not all inert archives are bugs.** Two mods can ship an identical resource, in
which case the loser is merely redundant. Maintain an explicit allow-list of
known-harmless cases rather than reporting them forever - otherwise the real
problems drown in noise.

## Stale entries and unlisted archives

- **Listed but missing** - usually a disabled mod. Keep the line by default: it
  holds the slot so the mod returns to its old position if re-enabled. Only prune
  on a genuine uninstall.
- **On disk but unlisted** - it cannot be positioned and sorts last. Always fix.
- Swapping a mod variant produces **both at once**: a stale entry for the old
  filename and an unlisted archive for the new one.

## What reordering can and cannot fix

Three situations produce an identical-looking conflict report, and **only one of
them is a load-order problem.** Work out which you have before promising anything.

### 1. A lost fight - fixable by order

Both mods ship the same resource; the later one loses. Reorder and it wins. This is
the only case where load order is the answer.

### 2. A coverage gap - NOT fixable by order

Only one mod ships that resource. The other never contested it, so there is nothing
to win. No amount of reordering conjures content that isn't in the archive.

This is the one most often misdiagnosed, because the *symptom* looks like a
conflict. A skin-tone patch covering torso and arms but shipping no leg textures
leaves the legs mismatched forever - and a conflict checker shows **zero conflicts**,
because there is no contested file. Extract the archive and read its file list; if
the path isn't there, stop looking at load order.

The tell: the user reports a visual mismatch, and the scanner reports nothing wrong.

### 3. Mutually exclusive claims - not fixable at all

Two mods ship the same single resource and the user wants both to apply. That is
arithmetically impossible, and shuffling the order just moves which one is dead.

**Say so plainly rather than reordering and hoping.** Two billboard mods each
carrying one texture for the same surface is an either/or, and the useful response
is "these replace the same file, pick one" - not three rounds of load-order changes
that each silently kill the other mod.

Check that a request is *satisfiable* before you start satisfying it.

## A precedence change can create new casualties

Making X win means something else stops winning, and that something may be a third
party the user never mentioned.

A real sequence: a skin mod was promoted to beat two others, which was correct and
what the user asked for. The next scan showed a **fourth** archive had become
completely inert - all 17 of its files were now owned by the newly promoted mod.
Nobody asked for that mod to die; it was collateral.

**So: after applying a precedence rule, re-run the collision scan and diff the inert
list.** Anything newly inert is a consequence of your change and needs surfacing,
because the user may want to uninstall it, may want the rule reversed, or may not
have realised the two mods overlapped that heavily.

The same check catches the opposite case, where a mod you expected to die turns out
to still own files the winner doesn't ship - which is a coverage gap wearing a
conflict's clothing, and means both mods should stay installed.

## Standing precedence rules

When a conflict is settled by hand, record it as a machine-checkable rule
(`X must precede Y`, plus *why*). Otherwise the next deploy re-appends the archive
and quietly undoes the decision, and nobody remembers the reasoning six weeks
later. A rules table that is re-verified on every run is the difference between a
load order that stays fixed and one that has to be re-diagnosed repeatedly.

## Tooling caution

At least one conflict-checker's "enable load order re-ordering" checkbox **deletes
`modlist.txt` when unchecked**. Disabling it does not merely stop the tool from
reordering - it removes the file, dropping the install back to alphabetical order
with no explicit control at all. If a load order suddenly reverts, check the file
still exists before re-deriving anything.
