---
okf_version: "0.2"
---

# Cyberwise base wiki

Game, engine and format knowledge for a modded Cyberpunk 2077 install, plus
cross-mod interaction patterns that are really facts about the game's data
model.

**This bundle ships.** Knowledge about a specific mod - its settings, how it
works, what its author wrote - belongs to the per-user bundle beside the game's
own data, and never ships. See `cyberwise-wiki` for the boundary and
`Test-Wiki.ps1 -Base` for the check that enforces it.

## Patterns

- [A mod that enumerates records will hand the player abstract templates](/patterns/record-enumeration-leaks-templates) - why an item can equip, carry stats, and have no name

## Engine

*Nothing migrated yet. Candidates sitting in skill reference files:*

- appearance stored by index rather than name, and what that does to CCXL lists
- the ACU `.preset` format
- RDAR archive layout
- load-order precedence across the two domains

## Log

- [log.md](/log) - what changed here and why
