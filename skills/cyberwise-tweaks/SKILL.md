---
name: cyberwise-tweaks
description: Author Cyberpunk 2077 mods that are code rather than assets - TweakXL/TweakDB records, CET Lua, and redscript that changes world state. Covers finding the real record ID rather than guessing it, what the CET console can and cannot do, reading the game's own shipped script dump for real signatures, and locating in-game text. Use when writing or repairing a .yaml tweak or a .reds script, running console commands, or hunting for an in-game string or record.
---

# Cyberwise: TweakDB and CET Lua

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> **Re-check after a patch:** Record IDs and the string blob move between versions - re-extract rather than reusing a noted ID.

Load `cyberwise` alongside this for the method rules.

**Check the patch version before reusing any noted record ID:**

```powershell
(Get-Item "$GameRoot\bin\x64\Cyberpunk2077.exe").VersionInfo.ProductVersion
```

A record ID noted under one patch is a lead, not a fact, on another. If the
installed version differs from the stamp above, re-extract rather than trusting
the note - which is the same rule as below, just with a reason to apply it.

## Never patch another author's file in place without a snapshot

Repairing someone else's `.yaml` is the most common mutating job in this topic,
and a mod update silently reverts it - so the patch has to be re-appliable and
the original has to survive. Use the front door's helper:

```powershell
. <path-to>\cyberwise\tools\ModFileBackup.ps1
Show-ModFileDiff   -Path $yaml -NewText $fixed          # get agreement on THIS
Set-ModFileContent -Path $yaml -NewText $fixed -Note 'fix <mod> <what>'
```

Then **write down what you changed and why**, somewhere outside the mod folder.
A hand-patch you cannot re-apply after an update is a fix with a short life and
no memory of itself.

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
| `references/redscript.md` | writing `.reds` that changes world state - the shipped script dump, addressing objects, undoing only your own change |
