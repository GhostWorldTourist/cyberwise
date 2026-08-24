---
type: Engine Mechanic
title: There are two load-order systems, and a conflict scan only sees one of them
description: Loose archives are ordered by modlist.txt; REDmod archives are ordered by the REDmod deploy. Nothing ranks one domain against the other, so a mod can win or lose a file without appearing in a load-order report at all.
tags: [load-order, redmod, archive, modlist, conflicts]
status: stable
generated: { by: "claude", at: "2026-08-24T18:30:00-04:00" }
---

# There are two load-order systems, and a conflict scan only sees one of them

Many mods ship both a "default" build and a "REDmod" build of identical content.
The choice is not cosmetic, and it is not about which is newer or more official.

| | default / loose | REDmod |
|---|---|---|
| lands in | `archive\pc\mod\` | `mods\<name>\archives\` |
| ordered by | `modlist.txt`, explicit and editable | the REDmod deploy order |
| deploy step | none | required after every change |
| visible to a `modlist.txt` conflict scan | yes | **no** |

## Default is the right answer unless the mod needs REDmod

The list of things that genuinely need it is short: **custom audio** - new `.wav`
sounds are only supported through REDmod - mods shipping REDmod-only scripts or
tweaks, and mods that offer no other build. Everything else gains nothing and
costs visibility.

## The cost is diagnostic, and it is the part people miss

Two mods contesting a file are only comparable when **one list orders both of
them**. `modlist.txt` orders the loose archives; the REDmod deploy orders the
others. Nothing ranks across the boundary.

So a REDmod can win or lose a file without appearing in a load-order report at
all, and "no conflicts" then means "no conflicts *among the ones I looked at*" -
which is a much weaker statement than it sounds, and indistinguishable from the
strong one in a report that does not say which it made.

Cross-domain contests should be reported **without ranking them**, because
nothing available establishes which domain wins. On one install that surfaced 63
files contested between a REDmod framework and loose retexture archives, on a
load order that had been reported clean for months. Test in game, or remove one
copy; do not guess a winner.

## The usual cause is one mod installed both ways

Somebody tries the REDmod build, then the default one, and both remain. Neither
manager nor game complains, because from each domain's point of view nothing is
wrong.

## An archive with no `modlist.txt` entry sorts last and loses

Order is by list position, and an unlisted archive is not at the end of the list
by intent - it is outside it. It loses every file it contests, quietly, until
somebody notices.

This matters for a case that looks like a bug: **some archives are written at
runtime.** At least one known mod generates its `.archive` from a native plugin
at game start, so the file appears and vanishes between sessions. Because the
mod ships no archive of its own, any check comparing deployed archives against
installed copies reports it as an orphan. Never prune its entry as stale - it
still needs a permanent slot in the list, for exactly the reason above.
