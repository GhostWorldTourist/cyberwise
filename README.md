# Cyberwise

A Claude Code skill for diagnosing modded **Cyberpunk 2077** installs.

It is not a modding tutorial. It is a set of field notes about the things that are
counterintuitive, undocumented, or actively contradicted by popular advice - the
ones that cost hours before they were understood. Every entry was learned by
getting it wrong first on a real ~700-archive load order.

## What it covers

| topic | examples of what's in there |
|---|---|
| **Load order** | why earlier-in-list wins and `zzz_` advice is backwards; why every newly installed mod starts inert; how to test override direction without fooling yourself |
| **Archives** | reading the RDAR index with no tooling; FNV1a-64 path hashing; which hash dictionaries exist and how incomplete they are |
| **Diagnosis** | which log answers which question; why a failed ArchiveXL patch looks like total mod failure; why you must locate a visual symptom before theorising |
| **Bisecting** | where to park files and why not `%TEMP%`; searching by layer before by file; why automated hang detection cannot work |
| **Crashes** | the post-mortem the game writes itself; why Windows Error Reporting never fires; how to measure memory without inventing a leak |
| **Saves & appearance** | decompressing `sav.dat`; the logical-offset trap; CDPR's `CharacetrCustomization` typo; the ACU preset format |
| **CET & Lua** | the LuaJIT 5.1 sandbox limits; console commands that work, and popular ones that silently don't |
| **TweakDB** | never guessing record IDs; vendor stock gating; why some price records exist but are never read |
| **ReShade** | identifying the add-on build by signature; shader pack header collisions; a known silent-crash incompatibility |
| **Environment** | telling manual / Vortex / MO2 apart and why it changes everything; resolving an internal name back to a findable mod; reading real settings vs shipped defaults; redscript as an all-or-nothing gate; tooling traps |

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

- Written against **patch 2.31**. Paths and behaviours drift between patches.
- Findings are empirical, from one large Vortex-managed install. Where something was
  verified, it says so; where it is inference, it says that too.
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
