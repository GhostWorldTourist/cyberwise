# CET, Lua, and console commands

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> **Re-check after a patch:** The LuaJIT 5.1 limits are stable. The console calls and the ripperdoc gate on cyberware are game-version behaviour - re-test those before recommending them.

## The sandbox is LuaJIT (Lua 5.1), not modern Lua

Every one of these has produced a confusing failure:

- **No `load`** - use `loadstring`.
- **No `_G`.** You cannot pass helpers to a loaded chunk via globals. Pass them as
  **chunk varargs** instead: `local LOG, TRY = ...`
- **No bitwise operators.** `>>`, `<<`, `&`, `|` are Lua 5.3 syntax and produce a
  *compile* error that kills the entire file, not a runtime error on that line.
- **No integer subtype**, no `math.type`.
- **64-bit hashes arrive as FFI cdata.** `tostring()` renders them exactly;
  `type(h) == "number"` would mean it had been lossily converted to a double.
- **A bare `return` mid-chunk is a syntax error.** Wrap script bodies in
  `local function main() ... end main()`.

## The console strips newlines from multi-line pastes

Pasted multi-line code arrives concatenated into one line, producing errors like
`sol: syntax error ... '=' expected near 'not'`. Anything longer than a single
statement must be **read from a file**, not pasted. A small script-runner mod that
`loadstring`s files from disk is worth building early - it turns every subsequent
investigation from guesswork into iteration.

Related: errors escaping before a flush leave a **0-byte output file and no clue**.
Flush per line. CET's per-mod log (`...\mods\<name>\<name>.log`) catches errors
thrown outside your own `pcall`.

`registerHotkey` only takes effect **while the mod is loading**. Registering
hotkeys later, or in response to UI, silently does nothing.

## Console commands: what actually works

**Give an item**

```lua
Game.AddToInventory("Items.NanoWires", 1)
```

`Game.AddToInventory` is a real CET global. Note that **base cyberware records are
not necessarily Tier 1** - `Items.NanoWires` spawns a Tier 3 monowire.

**Modify a player stat**

```lua
StrikeExecutor_ModifyStat.new():ModStatPuppet(
    Game.GetPlayer(), gamedataStatType.CarryCapacity, 1000.0, Game.GetPlayer())
```

The widely posted `Game.ModStatPlayer("CarryCapacity", "1000")` **is not a CET
global** and will fail. `ModStatPlayer` exists only as a helper method inside
certain mods. Verify a call exists before recommending it.

**Cyberware cannot be equipped or unequipped from the console.** Since 2.0 that is
ripperdoc-gated. Both of these are syntactically valid, reference real identifiers,
and silently do nothing:

```lua
-- does not work
UnequipRequest with areaType = gamedataEquipmentArea.ArmsCW
Game.GetTransactionSystem():RemoveItemFromSlot(player,
    TweakDBID.new("AttachmentSlots.ArmsCyberwareGeneralSlot"), true)
```

Send the user to a ripperdoc. Note also that the *slot* is
`AttachmentSlots.ArmsCyberwareGeneralSlot` while `ArmsCW` is a
`gamedataEquipmentArea` enum member - different identifiers, easy to confuse, and
mixing them up fails silently.

**For screenshots, change the appearance rather than the hardware.** Arm cyberware
visuals are appearance entries (`holstered_default_tpp`, `holstered_strong_tpp`,
`holstered_nanowire_tpp`), independent of what is installed.

## Quest facts

Facts live in the **save**. Setting one from the console and then loading a save
discards it. To set a fact reliably, do it from a script on game attach.

Do not guess what a fact means from its name. One named `..._reset` turned out to
be a signal that actively *suppressed* the feature it appeared to enable.

## Verifying a TweakDB value at runtime

```lua
print(#TweakDB:GetFlat("Vendors.<id>.itemStock"))
print(TweakDB:GetFlat("<YourRecord>.item"))
```

Read-only and safe; the fastest way to confirm a tweak actually applied.
