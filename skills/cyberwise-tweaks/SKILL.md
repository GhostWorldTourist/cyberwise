---
name: cyberwise-tweaks
description: Author TweakXL/TweakDB edits and CET Lua for Cyberpunk 2077 - finding the real record ID rather than guessing it, what the CET console can and cannot do, and locating the game's own text strings. Use when writing or repairing a .yaml tweak, running console commands, or hunting for an in-game string or record.
---

# Cyberwise: TweakDB and CET Lua

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> **Re-check after a patch:** Record IDs and the string blob move between versions - re-extract rather than reusing a noted ID.

Load `cyberwise` alongside this for the method rules.

## Do not guess a record ID

The single biggest time sink here is inventing a plausible-looking TweakDB ID.
Extract the real one. `references/tweakdb-and-text.md` covers how, plus locating
game text and the string blob TweakXL writes.

Also there: the `$type` versus `$base` distinction that silently breaks a
prereq record, which looks like a mod that simply does not work.

## The CET console is a sandbox

It cannot do everything the game can. `references/cet-lua.md` covers what
actually works from the console, what silently does nothing, and the sandbox
limits worth knowing before writing a script that cannot work.

## Reference material

| file | covers |
|---|---|
| `references/tweakdb-and-text.md` | TweakXL authoring, finding real record IDs, locating game text |
| `references/cet-lua.md` | CET sandbox limits, console cheats that work and that don't |
