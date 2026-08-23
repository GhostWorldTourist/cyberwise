# CETMonkey - asking the running game a question

> **Verified:** CETMonkey 2.8, CET 1.36 - Cyberpunk 2077 patch 2.31, August 2026
> **Re-check after a patch:** CET binding shapes move between CET releases - which return slot holds a redscript out-param has already changed once, and native argument types (entEntityID vs GameObject) are enforced per build. The Library contract and the staging/hardlink rule are CETMonkey and Vortex behaviour, not game behaviour.

Most of this family reads an install at rest: archives, tweaks, scripts, logs.
CETMonkey is the other half - it runs Lua **inside the running game** and writes
the answer to a file this family can read. Anything about live state (what is in
the player's inventory, which status effects are applied, what a vendor actually
stocks, where an entity is standing) is answerable only here.

Treat it as a prerequisite, not an accessory. `Test-Capabilities.ps1 -For
livequery` is the gate.

## Look in the Library FIRST

```
bin\x64\plugins\cyber_engine_tweaks\mods\cetmonkey\scripts\*.lua
```

**Before writing a script, list that folder.** On 2026-08-23 a whole second CET
mod was built - hotkeys, its own output files, a duplicated defensive-read helper
- to dump an inventory, while CETMonkey sat installed with a Library that runs
scripts from a button. The user had even said "make a cetmonkey script" and it
was read as a generic noun.

The first two comment lines of every script are its title and description, so
listing the folder and reading two lines per file tells you what already exists.

## Why scripts live on disk

The CET console **strips newlines from multi-line pastes**, silently
concatenating statements into a syntax error. Anything longer than one line has
to be read from a file. This is not a preference; it is the reason CETMonkey has
a Library at all.

It also means "just paste this into the console" is only ever valid advice for a
true one-liner, and a one-liner cannot afford the per-field `pcall` that live
inspection requires (see below).

## The script contract

```lua
-- Title line, shown in the Library
-- One-line description, shown under it
--
-- Longer explanation for whoever opens the file.

local LOG, TRY, APPEND = ...
```

| helper | goes to | lifetime |
|---|---|---|
| `LOG(...)` | `output.txt` + CET console | truncated at the start of each run |
| `APPEND(line)` | `log.txt` | never truncated - use for repeated sampling |
| `TRY(label, fn)` | `output.txt` | calls a method that may not exist; logs only on success |

`LOG` flushes per line on purpose: a script that errors halfway must not lose
what it had already learned.

`APPEND` is the right choice for anything transient. Status effects expire;
sampling before and after an event and diffing the two runs is the only way to
attribute one to a cause.

Every script also gets a real hotkey registered at load, listed in CET's
Bindings tab. Nothing needs binding to be usable - the Library runs it with a
click - but a hotkey lets a sample be taken mid-combat without opening an
overlay that changes the thing being measured.

## LuaJIT, not Lua 5.4

CET is **LuaJIT (Lua 5.1)**: no `load`, no `_G`, no bitwise operators, no integer
subtype. Scripts get their helpers as chunk varargs for that reason.

## Reading live objects without dying

Two rules, both learned the hard way, and both about the same trap: **the object
worth finding is usually the one that does not resolve.**

**Wrap every field read separately.** A dump that lets one bad field throw loses
the whole run, and a dump that skips the item silently hides the only row that
mattered. `MISSING`, `<THREW>` or `NONE` in a column *is* the finding.

```lua
local function str(fn, d)
    local ok, v = pcall(fn)
    if not ok then return "<THREW>" end
    if v == nil then return d or "<nil>" end
    return tostring(v)
end
```

**Redscript out-params arrive as extra return values, and the slot moves between
versions.** Three wrong signatures were tried for `GetItemList` before this. Do
not hardcode a slot; take whichever return is indexable.

```lua
-- Call as firstArray(obj:Method(args)) so every return slot is forwarded.
local function firstArray(...)
    for i = select("#", ...), 1, -1 do      -- out-params are appended, so prefer LAST
        local c = select(i, ...)
        if c ~= nil and type(c) ~= "boolean" then
            local ok, n = pcall(function() return #c end)
            if ok and n ~= nil then return c end
        end
    end
    return nil
end
```

**Never collect the returns into a table literal first.** The obvious
`for _, c in ipairs({ b, a })` is wrong: when the call has a single return, `b`
is nil, that table has a hole at index 1, and `ipairs` stops dead on it without
ever reaching the array in slot 2. It fails as a clean "no array found" rather
than an error, so it reads as an API problem and sends you hunting for a
different method. It cost a run that reported "could not read status effects"
while a 7-element table sat in slot 1.

When a call comes back empty, **probe before guessing again**: log `type()`,
`#`, a `pairs` count and `[1]` for every return slot of each candidate call. One
probe run settles the shape; a fourth guessed signature does not.

Native signatures are strict about handle types in a way redscript is not:
`GetAppliedEffects` takes an `entEntityID`, not the `GameObject`. When a call
rejects an argument, read the error - it names the type it wanted.

## Two columns that answer "why can't I see this?"

- **`uiData` on a status effect.** An effect appears under Character > Stats only
  if its record carries `UIData`. Many modded effects are pure stat carriers and
  declare none, so they apply, and cannot be identified from the UI. `NONE` means
  the stats screen is behaving correctly.
- **`resolves` on an inventory item.** An item whose TweakDB record is gone -
  its mod uninstalled, renamed or updated - persists in the save as a live
  instance. It equips and carries stats, but renders no name, icon or appearance
  and is absent from every list that filters on display data.

A record that resolves but shows a blank slot and an odd doubled name is the
third case: a **template**. Records existing only as a `$base` for real variants
carry no `displayName` or `appearanceName`, and a loot mod that enumerates
records rather than curated lists can hand one to the player as an item.

## Writing a new script: put it in STAGING

Scripts written straight into the deployed folder are **deployment-only and are
destroyed by the next Vortex purge**. The install is hardlinked from staging, so
the test is the link count:

```bash
stat -c '%h  %n' <script>      # 2 = staged and safe, 1 = will be lost
```

Write the file into staging, then hardlink it back:

```
%APPDATA%\Vortex\cyberpunk2077\mods\CETMonkey-<ver>\bin\x64\plugins\cyber_engine_tweaks\mods\cetmonkey\scripts\
```

Editing an **existing** deployed script is safe for the opposite reason - the
hardlink means the staging copy changes with it - but only if the edit rewrites
the same inode. A tool that replaces the file breaks the link and silently
converts a staged file into a doomed one.

Add the filename to `scripts\manifest.lua` too. The Library prefers CET's
`dir()`, but falls back to that manifest on builds that do not expose it, and a
script missing from it is invisible on those installs.

## Reading the result

`output.txt` and `log.txt` sit in the cetmonkey mod folder. Read them directly -
never ask for a screenshot of something that was written to a file, and never
ask the user to transcribe a record ID.

Related: `references/environment.md`, `cyberwise-recommends`.
