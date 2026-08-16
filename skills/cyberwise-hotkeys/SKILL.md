---
name: cyberwise-hotkeys
description: Find what every key is actually bound to on a modded Cyberpunk 2077 install, across the five separate stores that hold bindings, and generate a hotkey cheatsheet from what is really on disk. Use when asked what a key does, whether a key is free, how to rebind something, or for a keybind reference or cheatsheet.
---

# Cyberwise: input bindings

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> **Re-check after a patch:** Confirm the merged input cache is still regenerated at launch, and that CET still packs virtual-key codes at bits 48-55. Both are internal formats with no compatibility promise.

Load `cyberwise` alongside this for the method rules - in particular **never
quote a mod's shipped defaults as the user's configuration**, of which this whole
topic is the worst case.

## Never hand-transcribe a keybind. There are five stores.

They disagree on format, and only one of them holds what the player actually
pressed last:

| store | holds |
|---|---|
| `r6\input\*.xml` | per-mod **defaults** plus an `overridableUI` id |
| `r6\cache\inputUserMappings.xml` | the merged output; the only place `buttonGroup` ids resolve |
| `red4ext\plugins\mod_settings\user.ini` | the user's **actual** rebinds. **Wins.** |
| `cyber_engine_tweaks\bindings.json` | CET hotkeys, as packed VK codes |
| `cyber_engine_tweaks\mods\<mod>\**\*.json` | CET mods keeping their **own** config |

**The fifth is the trap.** Nothing obliges a CET mod to use CET's registry, so a
key can be live in game and absent from all four other stores. On one install
that was three mods out of roughly 150 - and one of them was a night-vision
toggle sitting on top of two other bindings, invisible to every generated sheet.

> **A binding you cannot find is not evidence the key is free.**

`user.ini` is applied at runtime, so it is **not** reflected in the merged cache.
Read the cache alone and you get the mod author's defaults and learn nothing
about what the user changed.

Full format detail - `overridableUI` linkage, `buttonGroup` indirection, the CET
packing, per-mod json conventions: `references/input-bindings.md`.

## Tools

```powershell
tools\Get-Hotkeys.ps1 -GameRoot '<path>'          # every binding, all five stores
tools\New-HotkeySheet.ps1 -GameRoot '<path>' -Out sheet.html
```

`Get-Hotkeys.ps1` resolves the install itself from Steam/GOG/Epic records if
`-GameRoot` is omitted, and errors rather than guessing. Zero bindings is a valid
result - an archives-only load order declares no keys.

`New-HotkeySheet.ps1` renders a self-contained sheet. Anything genuinely not on
disk - a programmable mouse's hardware mapping, a mod's tap/hold semantics - goes
in a small notes json passed with `-Notes`, and actions are re-resolved from the
harvested bindings on every run, so a rebind in game propagates without editing
the notes.

**Hardware sits outside all five stores.** A programmable mouse sends
*keystrokes*; the game never knows a device button was pressed, and the vendor
configurator keeps its profiles in its own database. Do not assume the user has
one - most do not, and the harvested bindings are the whole answer for them.

**The sheet is an HTML deliverable**, so load `cyberwise-reports` too when
generating one: it carries the house style, the viewport probe and the fit
measurement, and a sheet sized for a guessed viewport is the failure mode that
produces rounds of "still too small".

## Reference material

| file | covers |
|---|---|
| `references/input-bindings.md` | the five stores, `overridableUI` overrides, CET's packed key codes, per-mod json |
