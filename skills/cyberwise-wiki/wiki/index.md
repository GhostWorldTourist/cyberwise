---
okf_version: "0.2"
---

# Cyberwise base wiki

Game, engine and format knowledge for a modded Cyberpunk 2077 install, plus
cross-mod interaction patterns that are really facts about the game's data
model, and the process knowledge that keeps work about an install trustworthy.

**This bundle ships.** Knowledge about a specific mod - its settings, how it
works, what its author wrote - belongs to the per-user bundle beside the game's
own data, and never ships. See `cyberwise-wiki` for the boundary and
`Test-Wiki.ps1 -Base` for the check that enforces it.

## Patterns

Facts about the data model that surface as mod conflicts.

- [A mod that enumerates records will hand the player abstract templates](/patterns/record-enumeration-leaks-templates) - why an item can equip, carry stats, and have no name
- [A settings file the game rewrites answers "what is set", never "what is default"](/patterns/live-state-is-not-defaults) - two disjoint settings stores
- [A mod's shipped defaults are not proof a human chose anything](/patterns/defaults-can-be-written-by-code) - mods seed their own settings at runtime
- [An "allow nothing" flag short-circuits every other option, and shows no symptom](/patterns/override-flag-silences-the-filter-chain)
- [A shared core that announces its own add-ons turns "is this installed" into a lookup](/patterns/shared-core-announces-its-addons)
- [all patterns](/patterns/index)

## Engine

How the game and its script layers behave, independent of any mod.

- [A .reds file on disk is not code the game is running](/engine/compiled-script-bundle) - the compiled bundle and the three false absences
- [An archived redscript log is named for the run that replaced it](/engine/redscript-log-names-the-wrong-run)
- [Reading live game objects from CET Lua without losing the row that mattered](/engine/cet-lua-runtime)
- [There are two load-order systems, and a conflict scan only sees one of them](/engine/two-load-order-domains)
- [The game's own option registry outranks any mod's account of an engine setting](/engine/option-registry-is-the-authority)
- [all engine articles](/engine/index)

## Installs and mod managers

What each way of assembling an install makes untrue about the files on disk.

- [What the game directory shows you depends on how the mods got there](/install/how-the-install-is-assembled)
- [Fixing a bug in someone else's mod](/install/overriding-another-authors-mod)
- [Two downloads from one mod page may not be alternatives](/install/two-builds-of-one-filename)
- [all install articles](/install/index)

## Process

How to do the work so the result survives review.

- [Documenting a large mod list without producing a report nobody can trust](/process/running-a-documentation-pass)
- [A capacity read from the wrong API comes back plausible, and nothing about it looks wrong](/process/a-capacity-read-from-the-wrong-api) - saturation and enumeration, and why a wrong number that looks right propagates
- [all process articles](/process/index)

*Still sitting in skill reference files and not yet migrated: appearance stored
by index rather than name, and what that does to CCXL lists; the ACU `.preset`
format; RDAR archive layout.*

## Log

- [log.md](/log) - what changed here and why
