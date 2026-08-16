---
name: cyberwise-reshade
description: ReShade on Cyberpunk 2077 - why some mods need the add-on build rather than the standard one, and how shader packs collide when several are stacked. Use when ReShade effects fail to load, when shaders error on compile, or when combining multiple shader packs.
---

# Cyberwise: ReShade

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> **Re-check after a patch:** Re-check ReShade and shader-pack versions rather than the game version; these break on their own release cycle.

Load `cyberwise` alongside this for the method rules.

**Scope:** this is about *stacks*. A plain ReShade install with one shader pack
hits almost none of it.

Two rules that decide most of it:

- **The trigger for needing the add-on build is a file extension, not a name.**
  If there is a `.addon64` in the ReShade folder, the standard build ignores it.
- **ReShade is an injector installed outside any mod manager**, so it will not
  appear in a mod list and a manager purge will not remove it.

`references/reshade.md` covers the add-on build requirement, how two packs by the
same author ship duplicate shared headers and collide, and one observed
version-mismatch pair.

## Reference material

| file | covers |
|---|---|
| `references/reshade.md` | add-on build, shader pack collisions, known incompatibilities |
