# Cyberwise

A family of Claude Code skills for diagnosing modded **Cyberpunk 2077** installs.

It is not a modding tutorial. It is a set of field notes about the things that are
counterintuitive, undocumented, or actively contradicted by popular advice - the
ones that cost hours before they were understood. Every entry was learned by
getting it wrong first on a real install (846 mods, around 700 archives) - but the
notes are written for any install: 20 mods or 900, Vortex, MO2 or none at all,
Steam, GOG or Epic, on whatever drive. Where a finding is specific to one manager
or one scale, it says so.

## The family

`cyberwise` is the front door: the method rules that apply to every task, where
each kind of mod lives on disk, and a routing table. The topic skills are
separate so that reading about keybinds costs nothing when the question is about
textures.

| skill | use it when |
|---|---|
| `cyberwise` | always - the method rules the rest depend on |
| `cyberwise-conflicts` | a mod does nothing; textures look wrong; load order; `.archive` internals |
| `cyberwise-crashes` | crashes, hangs, failures to launch; log triage; bisecting |
| `cyberwise-saves` | reading a save, appearance data, ACU presets |
| `cyberwise-hotkeys` | what a key is bound to; generating a cheatsheet |
| `cyberwise-reports` | mod inventory, system profile, any HTML/markdown deliverable |
| `cyberwise-tweaks` | TweakXL/TweakDB edits, CET Lua, finding game text |
| `cyberwise-reshade` | ReShade add-on builds, shader pack collisions |

**They are additive** - a hotkey sheet is also an HTML deliverable, so that job
wants `cyberwise-hotkeys` and `cyberwise-reports`.

Measured on the split, per task: the front door plus one topic skill and its
reference costs **1,000-2,200 tokens less** than the old single skill did, because
the old one carried every topic's prose on every invocation. The eight
descriptions cost about 575 tokens of always-present listing, so it pays for
itself on the first use in a session.

Each skill owns its own `references/` and `tools/` outright - there is no shared
directory, because eight copies of a reference is eight things to drift.
`environment.md` is the one genuinely cross-cutting file and it lives in the
front door.

## What it covers

| topic | examples of what's in there |
|---|---|
| **Load order** | why earlier-in-list wins and `zzz_` advice is backwards; why every newly installed mod starts inert; what reordering can and cannot fix; how to test override direction without fooling yourself |
| **Archives** | reading the RDAR index with no tooling; FNV1a-64 path hashing; which hash dictionaries exist and how incomplete they are |
| **Diagnosis** | which log answers which question; why a failed ArchiveXL patch looks like total mod failure; why you must locate a visual symptom before theorising |
| **Bisecting** | where to park files and why not `%TEMP%`; searching by layer before by file; why automated hang detection cannot work |
| **Crashes** | the post-mortem the game writes itself; why Windows Error Reporting never fires; how to measure memory without inventing a leak |
| **Saves & appearance** | decompressing `sav.dat`; the logical-offset trap; CDPR's `CharacetrCustomization` typo; the ACU preset format |
| **CET & Lua** | the LuaJIT 5.1 sandbox limits; console commands that work, and popular ones that silently don't |
| **TweakDB** | never guessing record IDs; vendor stock gating; why some price records exist but are never read |
| **ReShade** | identifying the add-on build by signature; shader pack header collisions; a known silent-crash incompatibility |
| **Environment** | telling manual / Vortex / MO2 apart and why it changes everything; resolving an internal name back to a findable mod; reading real settings vs shipped defaults; redscript as an all-or-nothing gate; tooling traps |


## Nothing here modifies your install — but an assistant will

That distinction is the most important one in this repo. Every tool below only
writes its own reports. The edits that carry risk are the ones an assistant makes
by hand while following the notes: rewriting `modlist.txt`, patching another
author's `.yaml`, editing `user.ini`.

Those have no undo, and **irreversibility is the real hazard — not whether you
understood the command you approved.** A confused *yes* to a read-only command
costs nothing. A confused *yes* to a modlist rewrite costs a load order that
nothing can reconstruct. No permission dialog, in any client, fixes that.

So `cyberwise/tools/ModFileBackup.ps1` ships as part of the method:

```powershell
. tools\ModFileBackup.ps1
Show-ModFileDiff   -Path $f -NewText $updated              # preview, writes nothing
Set-ModFileContent -Path $f -NewText $updated -Note 'why'  # snapshot, then write
Restore-ModFile    -Path $f                                # undo
```

**Approval belongs on the diff, not the command.** Someone who cannot read
PowerShell can still read "this line becomes that line", and that is the only
version of consent worth having. Snapshots live under
`%LOCALAPPDATA%\cyberwise\backups` — deliberately outside the game directory,
which a mod manager may purge or redeploy over. A restore snapshots what it
replaced, so picking the wrong version is not a second dead end.

## Included tools

Tools live with the skill that uses them: `cyberwise/tools/` (the backup helper
above, which is cross-cutting), `cyberwise-hotkeys/tools/`,
`cyberwise-reports/tools/` and `cyberwise-saves/tools/`.

`New-ModManifest.ps1` builds a readable inventory of an installed load order:
every mod, what it deploys, its Nexus link and install date, and - with an API key -
a one-line description of what it actually does. `-HideNSFW` omits adult content.

It needs no credentials for the basics, because a manager that installed from Nexus
encodes `<Display Name>-<NexusID>-<version>-<timestamp>` into the staging folder
name. It reads a manager's staging root: the Vortex layout is found automatically,
MO2 needs `-StagingRoot` pointed at its `mods\` folder, and a fully manual install
has no staging tree for it to read. Folders that do not match the convention are
still listed, from the folder name alone - a mod dropped from an inventory is a
mod nobody knows they have.

`-NoNexus` guarantees it stays offline. A key stored in Credential Manager is
used automatically, so omitting `-NexusApiKey` is not the same as making no
network call.

Also included: `Get-Hotkeys.ps1` / `New-HotkeySheet.ps1` (every keybind on an
install, from all five stores that hold them, rendered as a cheatsheet),
`New-SystemProfile.ps1` (a machine and install profile that says what is likely
wrong, redacted by default because the markdown is meant for pasting in public),
`Measure-PageFit.ps1` (does a generated page fit a stated viewport) and
`NexusCredential.ps1` (stores a Nexus API key in Windows Credential Manager).

`cyberwise-crashes/tools/` carries `Watch-Crashes.ps1`, which samples the running
game to CSV and captures its own post-mortem telemetry on death, and
`Register-CrashWatch.ps1`, which registers that as a logon task so it restarts
itself and survives a reboot. The game catches its own fault and exits, so
nothing reaches Windows Error Reporting — `CrashInfo.json` is the only
first-party evidence, and it is overwritten on the next crash. **The capture is
deduped on `crashVisitId`**: an unconditional copy re-saves the same record after
every clean quit, which on one install turned 2 real crashes into 21 files and a
cluster that never happened.

`cyberwise-saves/tools/` carries `Expand-Save.ps1`, which decompresses a `sav.dat`
into one flat searchable blob, and `Decode-Preset.ps1`, which turns ACU `.preset`
files into readable appearance fields. Expand-Save hand-rolls an LZ4 **block**
decoder because .NET has none and the chunks are blocks rather than frames, so a
general LZ4 library will refuse them.

**Decoded saves are personal data.** Write them to a temp path; never into a repo.

**Pass your own paths.** These scripts carry defaults - a game root, a staging
root, a viewport - and those defaults are the author's machine, not yours. Use
`-GameRoot`, `-StagingRoot`, `-Width`/`-Height`.

## Install

Works with manual installs, Vortex and MO2 - though see the environment notes, because
MO2 virtualises the filesystem and that changes how you diagnose anything.

```powershell
git clone https://github.com/GhostWorldTourist/cyberwise ~/repos/cyberwise
cd ~/repos/cyberwise
.\install.ps1          # -Remove to unlink
```

That symlinks each skill under `skills/` into `~/.claude/skills/`, so edits to
this repo take effect immediately with no reinstall step. It falls back to a
directory junction where a symlink would need elevation. Then open `/hooks` once,
or restart, so Claude Code picks them up.

To install by hand instead, copy each directory under `skills/` into
`~/.claude/skills/` (or a project's `.claude/skills/`). Claude loads them when
you ask about Cyberpunk 2077 mod problems; you can also invoke one directly, e.g.
`/cyberwise-conflicts`.

## Tests

```powershell
.\tests\Test-Family.ps1         # structural validation of the family
.\tests\Test-Validator.ps1      # proves the validator above can actually fail
.\tests\Test-Tools.ps1          # runs the tools against synthetic installs
.\tests\Test-ToolMutations.ps1  # reintroduces shipped bugs, expects to be caught
```

The two halves check different things, and the second is the one that matters
more. **Structure is not behaviour, and parsing is not working.** Every defect
these tools have actually shipped parsed perfectly and was filed correctly.

A skill family breaks *silently*. A `references/foo.md` that no longer exists, a
frontmatter `name` that stopped matching its directory, a route to a renamed
skill - none of it errors. The skill loads and quietly cannot find the thing it
just told the model to go and read. Splitting cyberwise into eight parts produced
exactly one of those; it was caught by hand, and the point of `Test-Family.ps1`
is that the next one is caught by the machine.

It checks thirteen things, including that every reference and tool a `SKILL.md`
names resolves inside that skill, that every shipped reference is actually
mentioned by its owner, that every topic skill is reachable from the front door,
that every reference carries its own **Verified** / **Re-check after a patch**
stamp, and that no absolute user path has leaked into a public repo.

One of those is about drift: a **Verified** stamp must name a comparable version
number, *or* the file must say in as many words that nothing in it depends on a
game patch. "Verified: recently" is not a stamp, and the distinction between "not
patch-dependent" and "nobody wrote down which patch" is the whole point.

`Test-Validator.ps1` exists because a validator that has only ever returned green
is indistinguishable from one that returns green unconditionally. It copies the
family to a temp directory, injects one real fault at a time - a moved reference,
a renamed skill, a `.ps1` that no longer parses - and asserts that *the check
which owns that fault* is the one that reports, then that the tree comes back
clean afterwards. It found two bugs in the validator it tests.

### Testing the tools

`Test-Tools.ps1` builds synthetic installs in a temp directory and runs the real
scripts against them - no game, no hardware assumptions, no network. It covers
the things that broke before: that `#` and `!` are **filename** characters in
`modlist.txt` rather than comment markers, that the LZ4 decoder handles a match
overlapping its own output, that the Discord-facing markdown carries no path or
username, and that an unknown preset hash is printed rather than dropped.

A synthetic staging tree covers the manifest: that a hyphenated name like
`Cyber-Engine-Tweaks-107-1-35-1-...` still resolves to id 107, that a version of
`2k` survives, that a non-conforming MO2 or hand-unzipped folder still lists, and
that a CET mod is not also tagged an ASI plugin - `bin\x64\plugins` is an
*ancestor* of the CET mods path, so a naive existence check catches every one.

That last one is a good illustration of why the mutation suite exists. The first
version of the test asserted on the section headings, which looked right and
passed - but a mod is filed under its *primary* footprint, and CET wins that
ordering with or without the bug. Only reintroducing the defect showed the test
was watching a surface where it could never appear. The spurious label shows up
in the meta line as `CET+ASI`, which is what the test checks now.

The backup helper is covered too, and one of those tests exists because the first
version of `Show-ModFileDiff` **lied**: it reported "3 lines removed, 0 added"
for a one-line insertion, because `(if (...) {...} else {...})` is not a valid
sub-expression in PowerShell and the new text came back empty. The write itself
was correct — only the preview was wrong, which is exactly the thing the user is
asked to approve. A preview that lies is worse than no preview at all.

It also builds a five-store keybind fixture - a mod shipping `IK_F3`, a
`user.ini` rebinding it to `IK_F7`, a `buttonGroup` indirection in the cache, and
a `bindings.json` with keys differing only in case - and asserts the user's
rebind wins. That is the family's flagship rule (*never quote a mod's shipped
defaults as the user's configuration*) and this is the only place it is
mechanically enforced. An unbound CET entry must stay unreported, too: a key the
tool fails to find reads as a key that is **free**.

`Test-ToolMutations.ps1` reintroduces each of those bugs verbatim into a copy and
asserts that the test which owns it fails. Reintroducing the `#` bug reproduces
its original signature exactly - three modlist entries counted instead of four,
two archives reported unlisted instead of one.

It runs each suite in a **fresh process**, which is not optional:
`Expand-Save.ps1` compiles its LZ4 decoder with `Add-Type`, and a compiled type
cannot be replaced once loaded, so an in-process re-run silently keeps the first
version's decoder and the mutation looks undetectable.

None of it needs anything installed. Pester would be a dependency, and the
family's whole position is that PowerShell is already on the machine.

**Adding a skill?** Run all four. The reachability and routing checks will tell
you what you forgot to wire into the front door.

## Scope and honesty

- Written against **patch 2.31**. Paths and behaviours drift between patches, and
  they drift at very different rates.
- **Every file carries its own verification stamp**, because references get read in
  isolation - a model loading `cyberwise-crashes/references/crashes.md` never sees this README. Each
  one also has a **Re-check after a patch** line naming what to re-test first, so a
  new patch means triaging a handful of files rather than re-auditing everything.
  The highest-drift areas are flagged as such: save format first, then TweakDB
  record IDs, then crash telemetry.
- Findings are empirical, and most of the measuring happened on one large
  Vortex-managed install. Game behaviour (archives, load order, saves, TweakDB,
  logs) does not care which manager put the files there. Manager-specific
  behaviour is another matter: the MO2 and manual-install notes come from those
  tools' documented behaviour rather than from years of running them, so treat
  them as less battle-tested than the Vortex ones. Where something was verified,
  it says so; where it is inference, it says that too.
- **The tools are PowerShell on Windows, deliberately, and there is no other
  runtime to install.** The diagnostics are Windows APIs rather than incidentally
  Windows code: the registry for locating the install and reading true VRAM past
  the 4 GB `AdapterRAM` ceiling, CIM for pagefile and disk media, Credential
  Manager for the API key. Rewriting them in another language would still be
  Windows-only, and would add a runtime that does not ship with the OS the game
  requires. PowerShell is already there.

  **The notes are the portable half, and they are portable today.** File formats,
  hash algorithms and diagnostic reasoning have no operating system. A
  Linux/Proton user gets every `references/` directory and none of the tools; the
  paths there sit under the Proton prefix and none of that has been tested here.
- Nothing here is a substitute for reading the logs. Several notes exist purely to
  say *which* log, because that is the part people skip.

## Contributing

Corrections are welcome, particularly ones that contradict something stated here.
A note that turns out to be wrong is worse than no note, so if you can disprove
one, please open an issue.

## Author

Ghost World Tourist (GWT) - ghostworldtourist@pm.me

## Licence

MIT.
