---
name: cyberwise-forensics
description: Reconstruct what changed on a modded Cyberpunk 2077 install after the fact, without a snapshot - answer "it worked in December and it is broken now", find which mod ships a given file, and list every version of a mod ever downloaded. Use when a regression has no obvious cause, when a log names a file and you need the mod behind it, or when you need to know what changed between two dates.
---

# Cyberwise: install forensics

> **Verified:** Cyberpunk 2077 patch 2.31, Vortex - August 2026
> **Re-check after a patch:** nothing here reads game data, so a game patch
> cannot break it. Re-check if **Vortex** changes how it names staging folders
> or download archives, because both name formats are parsed here.

Load `cyberwise` alongside this for the method rules.

## What this is for

`cyberwise-crashes` has `New-InstallSnapshot` / `Compare-InstallSnapshot`, and
they are the right tools **when somebody took a snapshot first**. Nobody ever
has. The report is always "it worked in December", and December is gone.

It is not, quite. The install remembers in four independent places:

| evidence | answers |
|---|---|
| staging folder mtime | when that mod was last installed or updated |
| downloads file mtime | when you fetched the archive |
| **downloads file NAME** | when Nexus published it |
| deployed file mtime | when it last reached the game folder |

The third is the one people miss. **Vortex never deletes an archive you have
downloaded**, so the downloads folder is a version history you did not know you
were keeping. Two archives for one mod six months apart means that mod changed
under you, and the second date is when.

## This skill never writes

Every tool here is read-only. It reads Vortex's staging and downloads folders
and reports. It does not touch the game folder - it does not even locate it -
so there is nothing to back up and no `ModFileBackup.ps1` dance to do. If a
finding leads to a change, that change belongs to whichever skill owns it.

## The three questions

```powershell
skills\cyberwise-forensics\tools\Get-InstallHistory.ps1 -WorkingOn '2025-12-01'
skills\cyberwise-forensics\tools\Get-InstallHistory.ps1 -Owns 'nativeInteractions.xl'
skills\cyberwise-forensics\tools\Get-InstallHistory.ps1 -Mod 'Longer Lockdown'
```

| switch | |
|---|---|
| `-WorkingOn <date>` | it worked then; everything since is a suspect, newest first |
| `-From` / `-To` | an explicit window instead |
| `-Owns <filename>` | which staged mod ships this file, with its Nexus link |
| `-Mod <name>` | one mod: layers, install time, and every version ever downloaded |
| `-Touching <text>` | **the one that actually narrows things** - see below |
| `-BehaviourOnly` | drop pure art; scripts, tweaks, xl, quests and CET only |
| `-Top <n>` | cap the ranked lists (default 20) |

## -Touching is the point of the tool

A window query on a real install returns hundreds of events, because people
update forty mods in one sitting. Ranking cannot fix that: there is no ordering
of ninety simultaneous updates that puts the culprit first.

Intersection can. If you can name **anything** the symptom implicates - a
TweakDB record, a NodeRef, a method name, a resource path - then ask which of
the mods that changed also mentions it:

```powershell
Get-InstallHistory.ps1 -From '2026-07-28' -To '2026-08-05' `
    -Touching 'parent: cyberpunk2077.quest'
```

On the install this was built against, that window held **267 events**. The
intersection returned **two mods**. Both were the answer.

This is the shape of the query to reach for: *narrow by symptom, not by date*.
The date only decides which haystack.

## What it will not tell you

**Which version is currently staged.** It cannot be known from disk. Vortex
updates a mod **over the top of the previous one**, keeping the original folder
name while replacing the files, so a folder ending `-1-26-1` routinely holds
1.27.1. The tool reports the
newest download at or before the install time and labels it *likely*. If you
need certainty, check the framework's own log for the version it announces, or
compare file sizes against the archives in downloads.

**Whether a change caused anything.** It produces suspects. A mod appearing in
the output is a lead, not a verdict, and the only thing that settles it is
removing it and looking.

## Traps

**A folder name is not a version.** Stated three times in this file because it
has cost real afternoons. Every version the tool prints comes from a downloads
*filename*; staging entries are reported by mtime alone.

**`-Touching` uses `.Contains()`, deliberately.** A needle like `[NetSec]` is a
character class to `-like`, which silently matches nothing. This is the single
easiest way to write a log or file search that finds zero of the 1,534 hits
sitting in front of it.

**An empty `-Touching` result is a real answer.** It rules the window out. Do
not treat it as the tool failing - check the needle appears somewhere on disk at
all, then believe it.

**Mass-update days flatten the signal.** If the window contains one, say so
plainly rather than presenting the top of an arbitrary ranking as a finding.

## Related

- `cyberwise-crashes` - snapshots, and the bisect loop once you have a suspect
- `cyberwise-conflicts` - which mod wins when two touch the same thing
- `cyberwise-modbase` - what is deployed right now, rather than what changed
