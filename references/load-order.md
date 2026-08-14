# Load order

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
| `Preem Skin` (65) vs `###Ultra Skin` (66) | Preem first | Ultra first | Preem | Preem |

Both models say Preem. Mods prefixed `#`, `!` or `~` sort early alphabetically
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
