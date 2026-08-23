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

```powershell
(Get-Item "$GameRoot\bin\x64\Cyberpunk2077.exe").VersionInfo.ProductVersion   # -> 2.31
```

Every reference here carries a **Verified:** stamp. If the install reports a
higher version, say so before answering - the reasoning holds, but offsets,
record IDs and paths may have moved. (`FileVersion` is a build string and is not
what anyone means by "the patch".)

**Snapshot before every in-place write, and get approval on the DIFF, not the
command.** Nothing in this family modifies an install - but you will, by hand,
and those edits have no undo. Someone who cannot read PowerShell can still read
"this line becomes that line", and that is the only consent worth having.
`tools/ModFileBackup.ps1` does preview / snapshot / write / restore.

**When a command produces nothing, prove it ran before interpreting the
nothing.** An empty result is the *absence* of evidence and looks identical
whether the thing did not happen or the command never executed. Twice here a
silent parse failure was read as a finding - `#` treated as a comment in
`modlist.txt` produced 61 fabricated faults, and a path containing a space made
`Start-Process` fail so quietly it was mistaken for a platform limit. Capture
stderr, check the exit code, confirm the process exists.

**A negative is only as wide as the layer you searched.** "It does nothing" is a
far stronger claim than "it does X", and one grep over one file cannot carry it.
Name the layers the thing could act through - the mod's own config, the game's
option registry, another control on the same subsystem, a native plugin - and
until they are open, report "nothing in `<layer>`", not "nothing".

**Find out how the install is assembled before you trust the filesystem** -
manual, Vortex, MO2 and Wabbajack lists show completely different pictures on
disk. Two that bite hardest:

- **An MO2 install may show an almost empty game directory** (USVFS + Root
  Builder). "The file isn't there" proves nothing.
- **On a Wabbajack list, updating the list DELETES every mod not in the new
  version**, including any fix you add. Survivors must be named `[NoDelete] ...`,
  and those re-sort alphabetically, so order lives in the name too. Establish
  this *before* building anyone a fix.

Detection recipes and per-manager consequences: `references/environment.md`.

**Answer the worry, not the mechanism.** Most people here are modders, not
developers. When someone asks "is this safe", "what does that do", "will this
break my save" - answer *that*, in a sentence, without a lecture on how it works.
Offer the detail second, for the ones who want it. And **do the work yourself**:
if something needs building, installing or running, run it for them rather than
handing over commands to paste.

**Confirm the mod is actually deployed before theorising about why it fails.**
Hours have gone into explaining a mod that was staged but never deployed - and
the manual-install equivalent, an archive unpacked one folder too deep, fails
just as silently. On a virtualising setup, check the manager's own view.

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

**A mod's own labels describe the mod, not the engine.** That rule is about
values; this one is about meaning. Comments, tooltips, INI section names and
debug captions are the author's shorthand, and routinely misstate what a setting
reaches or what gates it. Treat them as a lead; the game's own option registry
declares the option itself and outranks them (`references/environment.md`).

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

**And when the source that is wrong is one of these files, that is a report, not
an embarrassment.** A note that turns out to be false is worse than no note, so a
user who can disprove one is doing the most valuable thing anybody does here.
Offer to write it up - `cyberwise-feedback` gathers the facts and hands them a
finished message. That applies just as much when the thing that got it wrong was
you rather than the notes.

**When a mod's author contradicts your reading of their mod, re-derive.** Their
word is not proof either, but it is a strong signal that a label was trusted or
a layer was never opened. Check again at the authoritative source before either
defending the reading or folding to the claim.

## Ask the running game - CETMonkey is a prerequisite

Everything else here reads an install **at rest**. Live state - what is actually
in the player's inventory, which status effects are applied, what a vendor really
stocks - is answerable only from inside the running game, and CETMonkey is how.

```
bind\plugins\cyber_engine_tweaks\mods\cetmonkey\scripts\*.lua
```

**List that folder before writing anything.** Each script's first two comment
lines are its title and description, so the Library reads as its own index. A
whole duplicate CET mod was once built to dump an inventory while CETMonkey sat
installed with a Library that runs scripts from a button - the same failure as
inventing a load-order rule without opening `modlist.txt`.

Three things that decide whether a live query works at all:

- **The CET console strips newlines from multi-line pastes**, concatenating
  statements into a syntax error. Anything past one line must be read from a
  file. "Paste this into the console" is valid advice only for a true one-liner.
- **Wrap every field read in its own `pcall`.** The record worth finding is
  usually the one that does not resolve, so `MISSING` or `<THREW>` in a column
  *is* the finding - and a dump that dies on it, or skips it silently, destroys
  the only row that mattered.
- **New scripts go in Vortex STAGING, then hardlink back.** A file written into
  the deployed folder has link count 1 and dies at the next purge.

Read `output.txt` and `log.txt` yourself. Never ask for a screenshot of something
that was written to a file.

Full contract - helpers, LuaJIT limits, the out-param return-slot trap, and the
`uiData` / `resolves` columns: `references/cetmonkey.md`.

## NEVER name a mod you have not confirmed is installed

```powershell
tools\Test-ModPresent.ps1 -GameRoot '<path>' -Name 'Immersive Gigs','Dark Future'
```

Exit 1 if any of them is absent. Run it before a report, a suspect list, or a
sentence that names mods.

**Why it matters more than it looks.** On 2026-08-23 a crash suspect list named
`AnywherePrologueUnlock`. It had been uninstalled, and the user had to say so.
The cost was not the wasted line - it was that every other name in the list
became worth less, because a diagnosis is only worth what its weakest claim is
worth. "That mod isn't even installed" is the fastest way to make somebody stop
believing the rest.

**It happens by taking a name from memory instead of from disk**, and the stale
sources all look authoritative:

| source | why it lies |
|---|---|
| a bisect park manifest | a snapshot of a PAST state, by design |
| a backup folder | things that WERE installed |
| `modlist.txt` | holds slots for disabled mods on purpose |
| the mod manager's list | staged is not deployed |
| earlier in this conversation | the install changes under you - purges, deploys, uninstalls |

That last one is the one that catches an agent. A list assembled twenty minutes
ago is not evidence about now, and on an install being actively worked on it is
frequently wrong.

## A feature that works for everyone else is not the thing to route around

**If something is supposed to work, and works for thousands of other people, and
does not work on this install - something is WRONG. Find it.** Do not design a
way to live without it.

A workaround written down becomes a rule, and the rule outlives the fault. On
2026-08-22 a CET overlay was dead for five hours. Once the cause was known - a
second keyboard emitting phantom key events - the tempting conclusion was "never
rebind CET's overlay through its UI, write the value to the file instead." CET's
UI is not broken. It works for everyone. Recording that would have taught every
future reader a false fact about CET that outlasted the broken keyboard.

A workaround is legitimate only as a **stated temporary measure while the hunt
continues**. It is never the answer, and it never goes into a skill, a reference
or a memory as guidance. When the cause turns out to be hardware or environment,
fix or remove THAT - do not adapt the practice around it.

The same rule applies to describing what happened: **what was done on the night
is history; what to do next time is guidance.** Only the second kind should read
as instruction, and only when it is actually true in general.

## For an input problem, inventory the physical inputs FIRST

One WMI query, before any software:

```powershell
cyberwise-hotkeys	ools\Get-Hotkeys.ps1 -Devices
```

It names every keyboard the machine has, flags virtual endpoints, and says what
more than one physical keyboard means. The failure that produced this rule went
through five binding stores, CET's config and state files, the D3D12 render hook,
ReShade, RTSS, Discord, DisplayFusion, Game Bar, accessibility filters, keyboard
filter drivers and 425 mods parked in a bisect round - while `Win32_Keyboard`
had been reporting **four keyboards** the entire time and nobody asked.

**A keyboard switched OFF but still cabled still enumerates and still reports.**
Its switch is the radio, not the USB interface. On plug-in or power transition a
faulty one emits a key-down with no key-up; every program running at that instant
believes the key is held for the rest of its life. That is how a hotkey binding
becomes a chord nothing can match, and how one app is unusable while others are
fine - each tracks its own copy of the key state.

**A virtual HID endpoint injects at driver level**, so its events carry no
INJECTED flag. A low-level capture showing "nothing is being injected" does not
clear them.

## Where records live - one place, agent-neutral

Anything this family must **remember about an install** goes on disk beside the
game's own data, never in the repo and never only in conversation:

```
%USERPROFILE%\Saved Games\CD Projekt Red\Cyberpunk 2077\Cyberwise\
```

**It is agent-neutral**, which is the point: Claude Code and Codex read the same
path, so work begun under one is picked up by the other. A fact held in one
agent's memory is invisible to the next and lost the moment the user switches -
and an unrecorded override is an invisible one. Rationale and the full layout:
`references/environment.md`.

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
| `tools/Test-ScriptsLive.ps1` | is a `.reds` mod's code actually in the compiled bundle the game loads |
| `tools/Test-InstallReady.ps1` | before you press Play: what is wrong, and which half launching will fix |

**Before a launch, ask what state the install is in.**

```powershell
tools\Test-InstallReady.ps1 -GameRoot '<path>'      # ~0.5s; -Deep reads the bundle
```

It sorts findings into **fixed by launching** and **launching will not fix
this**, which is the distinction that makes any of it actionable. Script mods
newer than the compiled bundle are the first kind and need no action at all;
archives with no `modlist.txt` entry are the second, and they sort last and lose
every file they contest until somebody notices. Reported together they are a wall
of warnings; reported apart, one of them is the answer.

**"The file is in `r6\scripts`" is not "the code is running."** `.reds` mods run
from a bundle compiled at launch, so a mod installed since the last launch is
enabled, correct, and doing nothing - with no sign in game. Ask the bundle:

```powershell
tools\Test-ScriptsLive.ps1 -GameRoot '<path>'            # what is stale
tools\Test-ScriptsLive.ps1 -GameRoot '<path>' -Mod 'X'   # one mod, symbol by symbol
```

It also catches the log traps that make this hard to check by hand - an archived
redscript log is named for the run that *replaced* it, and a compile test
overwrites the current one. Both in `references/script-cache.md`.

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

## Every tool in the family

**Before you write a tool, read this table.** It is the whole point of it. On
2026-08-22 a preset decoder was proposed and half-designed before anyone noticed
that `Decode-Preset.ps1` had shipped months earlier with the exact `-Compare`
mode being asked for. A second copy of a tool is worse than no tool: it splits
the tests, and whoever comes next finds whichever one they find first.

The table is **generated from the tools on disk** by
`cyberwise/tools/Get-ToolIndex.ps1`, and the test suite fails when it drifts - a
hand-kept index would be right the day it was written and quietly wrong after,
which is worse than none, because an index gets trusted.

```powershell
tools\Get-ToolIndex.ps1            # print it
tools\Get-ToolIndex.ps1 -Write     # after adding or renaming a tool
```

<!-- TOOL-INDEX:START -->
| tool | skill | what it does |
|---|---|---|
| `Get-ToolIndex.ps1` | `cyberwise` | every tool in the family, in one table. |
| `ModFileBackup.ps1` | `cyberwise` | take back the ability to undo. |
| `ModPatchWatch.ps1` | `cyberwise` | notice when a mod you patched or overrode has changed. |
| `Test-InstallReady.ps1` | `cyberwise` | if you launched right now, what would be wrong? |
| `Test-ModPresent.ps1` | `cyberwise` | is this mod actually installed right now? |
| `Test-ScriptsLive.ps1` | `cyberwise` | is a script mod's code actually in the compiled bundle? |
| `Find-QuestConflicts.ps1` | `cyberwise-conflicts` | which mods touch a quest, and which of them win. |
| `Repair-LoadOrder.ps1` | `cyberwise-conflicts` | Check (and optionally repair) the Cyberpunk 2077 archive load order. |
| `Resolve-ResourcePath.ps1` | `cyberwise-conflicts` | turn archive hashes into file paths, and back. |
| `Compare-InstallSnapshot.ps1` | `cyberwise-crashes` | answer "what changed?" |
| `Invoke-BisectRound.ps1` | `cyberwise-crashes` | park a set of mods, record the round, launch the game. |
| `New-InstallSnapshot.ps1` | `cyberwise-crashes` | record what the install looks like right now. |
| `Register-CrashWatch.ps1` | `cyberwise-crashes` | keep the crash watcher alive without a terminal. |
| `Save-CrashSnapshot.ps1` | `cyberwise-crashes` | preserve what a relaunch destroys, then state the facts. |
| `Watch-Crashes.ps1` | `cyberwise-crashes` | sample the game while it runs, and capture its own post-mortem when it dies. |
| `New-ProblemReport.ps1` | `cyberwise-feedback` | assemble a report the author can act on. |
| `Get-Hotkeys.ps1` | `cyberwise-hotkeys` | harvest the ACTUAL key bindings from a Cyberpunk install. |
| `New-HotkeySheet.ps1` | `cyberwise-hotkeys` | build a self-contained hotkey cheatsheet from the bindings actually present in a Cyberpunk install. |
| `Get-ModInventory.ps1` | `cyberwise-modbase` | every mod actually deployed, what layers it touches, and its Nexus id where one can be derived. |
| `ModPreference.ps1` | `cyberwise-recommends` | what this user has already said about being recommended things. |
| `Test-Capabilities.ps1` | `cyberwise-recommends` | what this install cannot do, and what is missing to do it. |
| `Compare-Collection.ps1` | `cyberwise-reports` | what a curated Nexus collection has that you do not. |
| `Measure-PageFit.ps1` | `cyberwise-reports` | does a page fit a given viewport without scrolling? |
| `ModManifestHtml.ps1` | `cyberwise-reports` | render a mod manifest as a self-contained HTML report. |
| `New-ArchiveAnatomy.ps1` | `cyberwise-reports` | what the archive layer actually contains. |
| `New-ModCredits.ps1` | `cyberwise-reports` | the people whose work is in your game, as end credits. |
| `New-ModDossier.ps1` | `cyberwise-reports` | everything this install knows about ONE mod. |
| `New-ModManifest.ps1` | `cyberwise-reports` | Generate a readable manifest of an installed Cyberpunk 2077 mod list. |
| `New-SystemProfile.ps1` | `cyberwise-reports` | a deterministic profile of a modded Cyberpunk 2077 install, in Discord-pasteable markdown and as an HTML report. |
| `NexusCredential.ps1` | `cyberwise-reports` | keep a Nexus API key in Windows Credential Manager instead of in a script, a config file, or a chat log. |
| `Show-ViewportProbe.ps1` | `cyberwise-reports` | ask the user's actual browser window how big it is. |
| `Decode-Preset.ps1` | `cyberwise-saves` | turn AppearanceChangeUnlocker .preset files into readable appearance fields. |
| `Expand-Save.ps1` | `cyberwise-saves` | decompress a Cyberpunk 2077 sav.dat into a flat blob. |
| `ConvertFrom-Markdown.ps1` | `cyberwise-sitebuilder` | the small Markdown subset these documents use. |
| `New-CharacterSite.ps1` | `cyberwise-sitebuilder` | a website from a folder of character documents. |
| `Test-Wiki.ps1` | `cyberwise-wiki` | does this bundle conform to OKF 0.2, and does it respect the distribution boundary? |
<!-- TOOL-INDEX:END -->

## Which skill covers it

Load the one that matches. They are separate so that reading about keybinds does
not cost you anything when the question is about textures.

| skill | use it when |
|---|---|
| `cyberwise-conflicts` | a mod is installed but does nothing; textures or body parts look wrong; load order, override direction, inert archives, `.archive` internals |
| `cyberwise-crashes` | the game crashes, hangs or fails to launch; reading logs; finding which mod is responsible |
| `cyberwise-saves` | reading a save, character appearance data, ACU appearance presets |
| `cyberwise-recommends` | a task needs a tool this install lacks; before mentioning any mod nobody asked about |
| `cyberwise-hotkeys` | what a key is bound to, rebinding, generating a hotkey cheatsheet |
| `cyberwise-reports` | inventory the mod list, profile the machine, or generate any HTML/markdown deliverable |
| `cyberwise-tweaks` | TweakXL/TweakDB edits, CET Lua and console commands, finding game text |
| `cyberwise-reshade` | ReShade add-on builds, shader pack collisions |
| `cyberwise-backstory` | building a character - V's history, voice, roleplay decisions, a dossier |
| `cyberwise-sitebuilder` | publish character documents, or anything else here, as a shareable website |
| `cyberwise-feedback` | Cyberwise itself is wrong, a tool errors, or the user wants to reach the author |
| `cyberwise-wiki` | writing down anything a later session would look up; a skill file has grown a section that is really reference material |
| `cyberwise-modbase` | what does this mod do; auditing a large load order; running a documentation pass over the install |

Two references stay here rather than in one of those, because they bear on all of
them: `references/environment.md` (manager behaviour, the settings store,
compile-testing) and `references/script-cache.md` (what is actually in the
compiled script bundle, and the log traps around it).

**These are additive.** A hotkey sheet is also an HTML deliverable, so that job
wants `cyberwise-hotkeys` *and* `cyberwise-reports`. Load both.

`cyberwise-backstory` is the odd one out: it is about **playing** the game rather
than fixing it, and none of the method rules above apply to it. It is here
because this is where the Cyberpunk knowledge lives. If the question is about a
character rather than an install, go straight there - the diagnostic rules will
only get in the way.
