# Cyberwise

A Claude Code skill for diagnosing modded **Cyberpunk 2077** installs.

It is not a modding tutorial. It is a set of field notes about the things that are
counterintuitive, undocumented, or actively contradicted by popular advice - the
ones that cost hours before they were understood. Every entry was learned by
getting it wrong first on a real install (846 mods, around 700 archives) - but the
notes are written for any install: 20 mods or 900, Vortex, MO2 or none at all,
Steam, GOG or Epic, on whatever drive. Where a finding is specific to one manager
or one scale, it says so.

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


## Included tools

`tools/New-ModManifest.ps1` builds a readable inventory of an installed load order:
every mod, what it deploys, its Nexus link and install date, and - with an API key -
a one-line description of what it actually does. `-HideNSFW` omits adult content.

It needs no credentials for the basics, because a manager that installed from Nexus
encodes `<Display Name>-<NexusID>-<version>-<timestamp>` into the staging folder
name. It reads a manager's staging root: the Vortex layout is found automatically,
MO2 needs `-StagingRoot` pointed at its `mods\` folder, and a fully manual install
has no staging tree for it to read.

Also included: `Get-Hotkeys.ps1` / `New-HotkeySheet.ps1` (every keybind on an
install, from all five stores that hold them, rendered as a cheatsheet),
`Measure-PageFit.ps1` (does a generated page fit a stated viewport) and
`NexusCredential.ps1` (stores a Nexus API key in Windows Credential Manager).

**Pass your own paths.** These scripts carry defaults - a game root, a staging
root, a viewport - and those defaults are the author's machine, not yours. Use
`-GameRoot`, `-StagingRoot`, `-Width`/`-Height`.

## Install

Works with manual installs, Vortex and MO2 - though see the environment notes, because
MO2 virtualises the filesystem and that changes how you diagnose anything.

Copy the folder into your Claude Code skills directory:

```
# user-level, available everywhere
~/.claude/skills/cyberwise/

# or project-level
<project>/.claude/skills/cyberwise/
```

Claude will load it when you ask about Cyberpunk 2077 mod problems. You can also
invoke it directly with `/cyberwise`.

## Scope and honesty

- Written against **patch 2.31**. Paths and behaviours drift between patches, and
  they drift at very different rates.
- **Every file carries its own verification stamp**, because references get read in
  isolation - a model loading `references/crashes.md` never sees this README. Each
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
- The tools are PowerShell on Windows. The notes themselves apply to a Linux/Proton
  install too, but the paths there sit under the Proton prefix and none of that has
  been tested here.
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
