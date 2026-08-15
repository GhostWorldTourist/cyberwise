# Input bindings

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> **Re-check after a patch:** Confirm `r6\cache\inputUserMappings.xml` is still regenerated at launch, and that CET's `bindings.json` still packs virtual-key codes at bits 48-55. Both are internal formats with no compatibility promise.

Never hand-transcribe a keybind. Five systems own bindings, they disagree on
format, and only one of them holds what the player actually pressed last.

## The five sources

| Source | Holds | Format |
|---|---|---|
| `r6\input\*.xml` | one file per mod: its actions, the input contexts they are live in, and a **default** key | `IK_` names |
| `r6\cache\inputUserMappings.xml` | Input Loader's **merged** output, every mod plus vanilla, regenerated at launch | `IK_` names, `buttonGroup` resolved |
| `red4ext\plugins\mod_settings\user.ini` | the user's **actual** rebinds | `IK_` names, keyed by `overridableUI` id |
| `bin\x64\plugins\cyber_engine_tweaks\bindings.json` | CET hotkeys | packed VK codes |
| `...\cyber_engine_tweaks\mods\<mod>\**\*.json` | CET mods that keep their **own** config | `IK_` names |

The last one is the trap. Nothing obliges a CET mod to use CET's binding
registry, so a key can be live in game and absent from all four other stores. On
a large install this was three mods out of ~150 - but one of them was night
vision, a key pressed constantly, sitting on top of two other bindings without
appearing on any generated sheet. **A binding you cannot find is not evidence
the key is free.**

`user.ini` wins. It is applied at runtime, so it is **not** reflected in the
cache - reading the cache alone gives you the mod author's defaults and tells
you nothing about what the user changed.

The link between the two is the `overridableUI` attribute:

```xml
<mapping name="AlwaysFirstEquip_Button" type="Button">
    <button id="IK_F2" overridableUI="afeMainHotkey" />
</mapping>
```

```ini
[AlwaysFirstEquip.FirstEquipConfig]
afeMainHotkey = IK_F2
```

A `<button>` with no `overridableUI` is not rebindable in Mod Settings, so its
xml value is final.

## buttonGroup indirection

A `<button id="...">` does not have to name a key. It can name a `buttonGroup`,
which is only defined in the **merged cache**:

```xml
<buttonGroup id="DH_Keyboard_Binding"><button id="IK_L" /></buttonGroup>
```

Parse the per-mod xml alone and Dialogue History's key reads as the literal
string `DH_Keyboard_Binding`. Build the group table from the cache first, then
expand ids through it.

The cache is regenerated at launch, so a mod installed since the last session is
absent from it. That is a staleness window, not a parse failure.

## Not every id is a key

Enhanced Vehicle System invents composite ids - `IK_F1_1`, `IK_F2_2` - for its
chorded bindings. They mean "F1 then 1" and no such virtual key exists. Anything
matching `IK_<key>_<key>` is a mod-internal chord, not something to look up.

## The CET packing

`bindings.json` stores a binding as a 64-bit integer holding up to four VK codes
in 16-bit slots, first key highest. The primary key is `value >> 48`.

```
62205969853054976 >> 48 = 221 = VK_OEM_6 = ']'
27021597764222976 >> 48 =  96 = VK_NUMPAD0 = 'Num 0'
```

`0` means unbound, which most entries are - a CET mod ships its whole hotkey
table whether or not the user bound any of it. Filter zeroes or the output is
mostly noise.

**`ConvertFrom-Json` needs `-AsHashtable` here.** The file contains keys
differing only in case (`HideMeshes` and `hideMeshes`), and the default
case-insensitive object conversion throws on the collision.

## Reading a CET mod's own config

Two conventions cover most of them:

```json
{"keyboard":{"mkbBinding_1":"IK_F3","mkbBinding_2":"IK_F4","mkbBinding_keys":1}}
{"ToggleKey":"IK_Y","QuickToggleKey_1":"IK_None"}
```

- **`mkbBinding_keys` says how many slots are live.** The example above is bound
  to F3 alone; `mkbBinding_2` is a leftover from a previous binding. Report the
  chord without checking the count and you invent an F3+F4 combo that does not
  exist.
- **`IK_None` means unbound**, not a key named None.
- `padBinding_*` mirrors the same shape for the controller.
- The json key names the *slot*, not the function - `mkbBinding_1` tells you
  nothing about what the mod does. The mod folder is the only clue, so the
  action name has to be supplied.

Depth-limit the search. `mods\` also holds mods shipping megabytes of json data,
and a blind recurse reads all of it to find a handful of keys; `mods\*\*.json`
plus `mods\*\config\*.json` caught every case here.

## Do not derive categories from input contexts

Tempting and wrong, twice over.

**Mods register everywhere.** A mod that wants its key live at all times appends
itself to every context it can find. Dialogue History declares
`VehicleDriveBase`, `Locomotion`, `CameraMovement` and `UIMenu` - so a
first-match-wins classifier files a dialogue tool under "Vehicle".

**`-match` is case-insensitive.** A pattern like `'UI|Menu'` matches the `ui`
inside `AlwaysFirstEq`**`ui`**`p`. Use `-cmatch`, or anchor the pattern, or
better: do not infer the category from the context string at all.

Which situation a binding belongs to is a judgement about the *mod*. Make it one,
explicitly, and keep the raw contexts as reference data.

## Shared keys are usually fine

Bindings scope to an input context, so one key legitimately carries several
meanings - `R` can reload, renew a chip, and pick a pocket, because you are never
doing all three at once. Report shared keys, but as information rather than as
faults. The ones that matter are two mods claiming the same key in the *same*
context, and you cannot tell those apart without reading the contexts.

## Hardware sits outside all of this

A programmable mouse or keyboard sends *keystrokes*; the game never knows a
Scimitar thumb button was pressed. Its mapping lives in the vendor's own
configuration (iCUE keeps profiles in its database, not a readable file), so it
has to be supplied by hand.

Worth joining anyway: given the hardware map, resolve each key through the
harvested bindings and the chain reads end to end - *thumb button 7 sends `]`,
which Advanced Control uses for next consumable*. It also catches drift. A
hand-written sheet labelling a button "night vision" next to harvested data
saying that key toggles the minimap has just told you the label is stale.

## Tools

- `tools/Get-Hotkeys.ps1` - harvests all five sources, resolves groups, applies
  overrides, returns objects.
- `tools/New-HotkeySheet.ps1` - renders a self-contained HTML cheatsheet, merging
  a small notes json for hardware maps and tap/hold semantics.
- `tools/Measure-PageFit.ps1` - renders a page headless at a given viewport and
  reports document height, viewport height, and the class of anything
  overflowing horizontally.

## Measure a layout, do not eyeball it

A cheatsheet is only glanceable if it fits on one screen, and "looks too tall"
is not a number you can act on. Several rounds of tuning were wasted guessing a
viewport from downscaled screenshots before measuring it directly; the fixes
took one pass afterwards.

Two failures that a screenshot hides completely:

- **An element pushed clean off the page.** A long inline label with
  `white-space:nowrap` forced its row wider than the container and shoved the
  keycap past the right edge. Not clipped, not squeezed - absent. Only the
  overflow probe named it.
- **A page that "fits" because the browser default was used.** In PowerShell,
  `--window-size=$W,$H` unquoted is parsed as an **array**, so two separate
  arguments reach the browser, the flag is ignored, and it silently renders at
  800x600. The first measurement claimed a 754px viewport. Quote it.

When testing a page that restores its own state on load, do not inject that
state into the markup - a class forced onto `<body>` is stripped by the page's
own restore logic before anything is measured, and the result looks like a
feature that does nothing. Drive the real control instead:

```powershell
(Get-Content $f -Raw) -replace '(?i)</body>',
  '<script>document.getElementById("modtoggle").click();</script></body>'
```
