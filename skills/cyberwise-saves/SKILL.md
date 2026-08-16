---
name: cyberwise-saves
description: Read Cyberpunk 2077 save files and character appearance data - decompressing a save, locating the appearance section, and decoding AppearanceChangeUnlocker (ACU) presets. Use when asked what a character's appearance settings are, to recover appearance data without re-recording it in game, or to read anything out of a .dat save.
---

# Cyberwise: saves and appearance

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> **Re-check after a patch:** HIGHEST drift risk in the family. The save container is an internal format with no compatibility promise - re-verify the chunk layout and the appearance section before trusting any offset.

Load `cyberwise` alongside this for the method rules.

## A save is personal data

Read the minimum needed to answer the question. Do not write decoded saves,
appearance dumps or preset decodes anywhere shareable, and never into a repo.

## What is in here

`references/saves-and-appearance.md` covers the save container (magic bytes,
the compressed chunk table, the offset trap that makes naive seeking fail), where
the appearance section lives, and the ACU preset format.

Two things worth knowing before you start:

- **`CharacetrCustomization_Appearances` is spelled that way in the game.** It is
  CDPR's own typo, not one to correct while searching.
- **An ACU `LocKey#<n>` is not a localization key.** It is a hash of the
  customization group name, which is why looking it up as a LocKey finds nothing.

## Reference material

| file | covers |
|---|---|
| `references/saves-and-appearance.md` | save decompression, appearance data, ACU preset format |
