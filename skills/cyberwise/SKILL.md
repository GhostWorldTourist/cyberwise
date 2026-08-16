---
name: cyberwise
description: Front door for diagnosing a modded Cyberpunk 2077 install - the method rules that apply to every CP2077 modding task, where each kind of mod lives on disk, and which cyberwise-* skill covers the problem at hand. Use at the start of any Cyberpunk 2077 modding question, and when unsure which part applies.
---

# Cyberwise

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> Every file under a `references/` directory carries its own verification stamp
> and a **Re-check after a patch** line naming what to re-test first. Trust those
> over this one; some areas drift much faster than others.

Field notes for diagnosing a modded Cyberpunk 2077 install, at any scale, under
any mod manager or none. This is not a modding tutorial - installing a mod and
finding a log are assumed to be covered elsewhere. What follows is the set of
things that are **counterintuitive, undocumented, or actively contradicted by
popular advice** - each one learned by getting it wrong first.

Findings here are empirical, and most of the measuring happened on one large
Vortex-managed install. Two consequences for how to use them. Where a claim is
manager-specific, it names the manager - treat the same claim on another manager
as untested rather than false. And where a worked example carries a big number,
the number is that install's, not a threshold: the mechanisms fire identically on
a twenty-mod list, they just fire less often.

## Method, before anything else

These cost the most time when skipped, and they apply to **every** task below -
they are why this front door exists rather than eight independent skills.

**Read the installed patch version before trusting anything stamped with one.**
It costs one line, so there is no excuse for skipping it:

```powershell
(Get-Item "$GameRoot\bin\x64\Cyberpunk2077.exe").VersionInfo.ProductVersion   # -> 2.31
```

These notes were verified against the version in each file's **Verified:** stamp.
If the install reports a *higher* version, say so before answering: the reasoning
still holds, but paths, record IDs and offsets may have moved, and the file's
**Re-check after a patch** line names what to re-test first. Do this whenever a
task depends on a stamped fact - save offsets, TweakDB record IDs, crash log
locations, hard-coded paths - not on every trivial question.

`ProductVersion` is the patch number directly (`2.31`); `FileVersion` is a build
string (`3.0.5294808`) and is not what anyone means by "the patch".

**Snapshot before every in-place write, and show a diff before you ask.** Nothing
in this family modifies a user's install - but *you* will, by hand: rewriting
`modlist.txt`, patching another author's `.yaml`, editing `user.ini`. Those edits
have no undo, and that - not whether the user understood the command - is the
real hazard. A confused "yes" to a read-only command costs nothing; a confused
"yes" to a modlist rewrite costs the load order.

```powershell
. tools\ModFileBackup.ps1
Show-ModFileDiff  -Path $f -NewText $updated        # preview, writes nothing
Set-ModFileContent -Path $f -NewText $updated -Note 'why'   # snapshot, then write
Restore-ModFile   -Path $f                          # undo, newest snapshot
```

**Ask for approval on the diff, not on the command.** Someone who cannot read
PowerShell can still read "this line becomes that line", and that is the only
version of consent that means anything here. Backups live under
`%LOCALAPPDATA%\cyberwise\backups` - never inside the game directory, which a
manager may purge or redeploy over.

**When a command produces nothing, prove it ran before you interpret the
nothing.** An empty result is not evidence; it is the absence of evidence, and it
looks identical whether the thing did not happen or the command never executed.
Twice in this project a silent parse failure was read as a finding - `#` treated
as a comment in `modlist.txt` produced 61 fabricated faults, and a path
containing a space made `Start-Process` fail so quietly it was mistaken for a
platform limitation. Capture stderr, check the exit code, confirm the process
exists - then interpret.

**Find out how the install is assembled before you trust the filesystem.** Manual,
Vortex, MO2 and an automated **Wabbajack modlist** present completely different
pictures on disk, and nearly every technique here reads the disk.

In particular, **an MO2 install may show you an almost empty game directory** - it
virtualises mods through USVFS and its Root Builder plugin copies files in at
launch and removes them when the game closes. On such an install "the file isn't
there" is not evidence of anything. Detection recipe and per-manager
consequences: `references/environment.md`.

**On a Wabbajack modlist, updating the list DELETES every mod that is not part of
the new version** - including any fix you add for them. Anything meant to survive
must be named `[NoDelete] ...`, and `[NoDelete]` mods re-sort alphabetically
afterwards, so the order needs to live in the name too (`[NoDelete] [0000] ...`).
Establish whether you are on one **before** building somebody a fix, or you are
handing them something with a lifespan of one update.

**Confirm the mod is actually deployed before theorising about why it fails.**
Hours have gone into explaining the behaviour of a mod that was staged in a mod
manager but never deployed to the game - and the manual-install equivalent, an
archive unpacked one folder too deep, fails just as silently. Check the file is on
disk under the game directory - or, on a virtualising setup, check the manager's
own view. Every time.

**Reproduce before bisecting.** One crash or hang is not a deterministic fault.
Confirm it repeats before halving anything, or you will bisect noise and "fix" it
by coincidence.

**Check your evidence actually discriminates.** When testing "does earlier win or
later win", make sure the two hypotheses predict *different* winners for the case
you are looking at. In CP2077 this bites constantly: mods prefixed `#`/`!` sort
early alphabetically and are usually placed early in load order too, so
"earlier-in-list wins" and "later-alphabetically wins" often predict the same
outcome. Three such cases prove nothing. Find a pair where the orders disagree.

**Never quote a mod's shipped defaults as the user's configuration.** Read the
actual settings store (see `references/environment.md`). A mod's `.reds` or `.xml`
declares what the author shipped, not what the user set. Keybinds are the worst
case - there are **five** stores, not one, and a key you cannot find is not a key
that is free (`cyberwise-hotkeys`).

**Always dereference an internal name to something the user can find.** Folder
names, TweakXL namespaces, redscript modules and archive filenames are authored by
mod authors for themselves and routinely bear no resemblance to the name the user
sees - in a manager's list, or in their own notes on a manual install. Naming only
the internal string ("`ChipwareExpansion` is doing this") leaves them unable to act.
Give the display name, and the Nexus ID where one is recoverable. Where it is *not*
recoverable - a manual install has no mapping from a deployed file back to a mod -
say that instead of guessing. Recipe per manager: `references/environment.md`.

**Do not hand your own guesses back to the user as their statements.** Naming a
mod you inferred and then writing "the mod is X, not Y" - as though they had said
Y - wastes a turn and costs trust. If you worked something out, say you worked it
out.

**What the user saw in game outranks what a mod page says.** They are running the
build; documentation describes intent. When their observation contradicts your
source, the source is what is wrong, and arguing the point is a waste of a turn.

## Know where each kind of mod lives

Not everything deploys to `archive\pc\mod`. A mod "missing" from there may simply
not belong there:

| kind | location |
|---|---|
| archives | `archive\pc\mod\` |
| REDmod | `mods\<name>\archives\` |
| ASI plugins | `bin\x64\plugins\` |
| CET mods | `bin\x64\plugins\cyber_engine_tweaks\mods\<name>\` |
| RED4ext plugins | `red4ext\plugins\<name>\` |
| redscript | `r6\scripts\<name>\` |
| TweakXL | `r6\tweaks\` |
| input binds | `r6\input\*.xml` |

All of those are relative to the game root, wherever this install put it - Steam,
GOG and Epic all differ, and the drive is whatever the user chose. Establish the
root once and build paths from it; never assume a default install location.

**Some archives are written at runtime.** At least one known mod (Dynamic Moon
Phases) generates its `.archive` from an ASI at game start, so the file appears and
vanishes between sessions. Because the mod ships no archive of its own, any check
that compares deployed archives against installed copies - a manager's staging
folders, or a manual installer's own record - reports it as an orphan. Never prune
its entry as stale, and note it still needs a permanent slot in `modlist.txt`,
because an unlisted archive sorts last and loses.

## Tools here

| tool | what it does |
|---|---|
| `tools/ModFileBackup.ps1` | snapshot / diff / restore for any file you are about to edit in place |
| `tools/ModPatchWatch.ps1` | register every patch and override, then sweep for the ones whose upstream file has changed |

**Fixing another author's mod? Register it.** `Register-ModPatch` records the hash
of their file as it was when you patched it; `Test-ModPatches` re-checks after any
mod update and reports `CHANGED`, `GONE` or `NOOVER`. Without that, an override
silently keeps winning over every fix the author ships afterwards - which is the
one failure mode that makes overriding a whole file risky at all. See
`references/environment.md`.

Dot-source it (`. tools\ModFileBackup.ps1`) and use `Set-ModFileContent` instead
of `Set-Content` for anything inside a user's install. It prints the diff, takes
a timestamped snapshot, then writes - and tells you the exact `Restore-ModFile`
command to undo it. `-WhatIf` shows the diff and stops, which is the right first
call.

It refuses files over 50 MB without `-Force`, because `.archive` files run to
gigabytes and are never hand-edited - a backup tool that fills the disk is its
own kind of damage.

## Which skill covers it

Load the one that matches. They are separate so that reading about keybinds does
not cost you anything when the question is about textures.

| skill | use it when |
|---|---|
| `cyberwise-conflicts` | a mod is installed but does nothing; textures or body parts look wrong; load order, override direction, inert archives, `.archive` internals |
| `cyberwise-crashes` | the game crashes, hangs or fails to launch; reading logs; finding which mod is responsible |
| `cyberwise-saves` | reading a save, character appearance data, ACU appearance presets |
| `cyberwise-hotkeys` | what a key is bound to, rebinding, generating a hotkey cheatsheet |
| `cyberwise-reports` | inventory the mod list, profile the machine, or generate any HTML/markdown deliverable |
| `cyberwise-tweaks` | TweakXL/TweakDB edits, CET Lua and console commands, finding game text |
| `cyberwise-reshade` | ReShade add-on builds, shader pack collisions |
| `cyberwise-backstory` | building a character - V's history, voice, roleplay decisions, a dossier |

`references/environment.md` stays here rather than in one of those, because
manager behaviour, the settings store and compile-testing bear on all of them.

**These are additive.** A hotkey sheet is also an HTML deliverable, so that job
wants `cyberwise-hotkeys` *and* `cyberwise-reports`. Load both.

`cyberwise-backstory` is the odd one out: it is about **playing** the game rather
than fixing it, and none of the method rules above apply to it. It is here
because this is where the Cyberpunk knowledge lives. If the question is about a
character rather than an install, go straight there - the diagnostic rules will
only get in the way.
