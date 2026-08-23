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

`Get-Hotkeys.ps1` reads all five stores in the right precedence, so use it rather
than transcribing by hand. If you are decoding a packed CET value yourself, check
the patch first - the bit layout is an internal format:

```powershell
(Get-Item "$GameRoot\bin\x64\Cyberpunk2077.exe").VersionInfo.ProductVersion
```


## The CET overlay will not open

Five hours, once. It is a checklist now. Work it in this order - each step rules
out a layer, and the cheap ones come first.

**1. Is anything else attached?**

```powershell
tools\Get-Hotkeys.ps1 -Devices
```

More than one physical keyboard is the finding. See the front-door skill for why
a keyboard that is switched off still counts.

**2. Is the key free, and is the binding a single key or a chord?**

```powershell
tools\Get-Hotkeys.ps1 -CheckKey Delete
```

Then decode what CET actually stored. `bindings.json` packs a chord into four
16-bit slots, most significant first:

```powershell
$v = (Get-Content '<game>ind\plugins\cyber_engine_tweaksindings.json' -Raw |
      ConvertFrom-Json -AsHashtable).cet.overlay_key
0..3 | ForEach-Object { [math]::Floor($v / [math]::Pow(2, 48 - 16*$_)) % 65536 }
```

`46, 0, 0, 0` is Delete alone. **`255, 46, 0, 0` is the failure**: VK 255 is HID
filler, and a stored chord never matches a plain keypress. Use `-AsHashtable` -
`bindings.json` has keys differing only in case and `ConvertFrom-Json` throws
without it.

**3. Did CET's render layer ever start?**

```powershell
Select-String '<game>ind\plugins\cyber_engine_tweaks\cyber_engine_tweaks.log' -Pattern 'D3D12::Initialize'
```

A working session logs `D3D12::Initialize() - initialization successful!` about a
minute after the hooks complete. **No line means the overlay has nowhere to
draw** - the key is fine and nothing will ever appear. Wait the full minute
before concluding it is absent: the line is written late, and reading too early
produces a confident wrong answer.

**4. Does CET receive input at all?** A CET mod with `registerInput` and a
heartbeat, bound by editing `bindings.json` directly, answers this without the
overlay. Log every press AND a periodic "still alive" line - otherwise silence
cannot be told from a mod that never loaded.

**5. Only then, the software.** CET's four state files (`bindings.json`,
`config.json`, `persistent.json`, `layout.ini`) are written by CET, not the mod
manager, so they survive a purge and a reinstall. Moving them aside and letting
CET regenerate is the whole configuration surface in one launch.

### What this checklist is not for

Do not end it with a workaround. If the overlay is broken, CET is not the thing
to stop using - it works for everyone else. Find the cause.


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
tools\New-HotkeySheet.ps1 -GameRoot '<path>' -Out sheet.html -Md sheet.md
```

`Get-Hotkeys.ps1` resolves the install itself from Steam/GOG/Epic records if
`-GameRoot` is omitted, and errors rather than guessing. Zero bindings is a valid
result - an archives-only load order declares no keys.

`-Md` writes the same bindings as markdown tables, for pasting somewhere the
HTML is no use. A full sheet runs past Discord's 2000-character limit, which
refuses the message rather than truncating it, so the tool prints the length
when it is over.

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
