# The compiled script bundle, and how to tell what is actually in it

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026, redscript via
> `engine\tools\scc.exe` + `cybercmd`
> **Re-check after a patch:** The bundle's internal layout is redscript's, not
> the game's, so a game patch does not move it - but a **redscript** update can.
> Re-check the log's `Output successfully saved to` line and the `.ts` layout
> after updating redscript, RED4ext or cybercmd.

`.reds` mods do not run from `r6\scripts`. They run from a **compiled bundle**
built at launch, and everything below is about the gap between those two
statements. "The file is there" and "the code is running" are different claims,
and on a real install they disagree regularly.

## Find the live bundle from the log, not from the config

One line is authoritative:

```
[INFO - ...] Output successfully saved to <path>
```

That is where the bundle went. `r6\config\cybercmd\scc.toml` states *intent*
(`custom_cache_dir`, `scriptsBlobPath`) and is worth reading, but a run can and
does write elsewhere - a compile test being the usual reason.

Two cache trees exist and both persist: `r6\cache\` and `r6\cache\modded\`. On
the install this was written against, `r6\cache\final.redscripts.modded` was
**eight months stale** while `r6\cache\modded\final.redscripts.modded` was live.
Advice of the form "delete `final.redscripts.modded` to fix your scripts" hits
whichever one the user finds first, which is a coin flip.

## An archived log's FILENAME is the time of the run that replaced it

This one costs an afternoon if you do not know it.

redscript rotates by renaming the current log with the timestamp of the run that
is **displacing** it. So `redscript_r2026-08-14_21-49-16.log` contains the run
from 2026-08-12 23:35, not from the 14th. Verified across five consecutive
rotations on one install - every file's first line matched the *previous* file's
name, never its own:

| filename says | first line says |
|---|---|
| `redscript_r2026-08-12_23-35-25.log` | 12 Aug 23:24 |
| `redscript_r2026-08-14_21-49-16.log` | 12 Aug 23:35 |
| `redscript_r2026-08-15_03-09-22.log` | 14 Aug 21:49 |
| `redscript_r2026-08-16_09-05-07.log` | 15 Aug 03:09 |
| `redscript_rCURRENT.log` | 16 Aug 09:05 |

**Read the first line. Never the filename.** The wrong log is not obviously
wrong - it is a full, plausible compile of the same install.

## A compile test destroys the record of the last launch

The compile-test recipe in `environment.md` runs the same compiler, so it
**overwrites `redscript_rCURRENT.log`** and pushes the real launch's log into a
rotation named after the test. Two consequences:

- The newest run on disk is frequently not the one that produced what the game
  is running.
- Tell them apart by the output path: a test writes under `%TEMP%`
  (`scc_test_<guid>\`, `scc_cache\`), a launch writes to the install's cache.

If you need the last real launch, walk the rotations for the newest run whose
output is **not** a temp path.

## `final.redscripts.ts` is nanoseconds since the Unix epoch

16 bytes: a little-endian `u64` of **nanoseconds since 1970-01-01**, then eight
reserved zero bytes. Verified against two independent bundles, each matching its
own file mtime to the second.

```powershell
$ns = [BitConverter]::ToUInt64([IO.File]::ReadAllBytes($ts), 0)
[DateTimeOffset]::FromUnixTimeMilliseconds([int64]($ns / 1000000)).LocalDateTime
```

Worth reading rather than trusting the mtime, because a manager's redeploy can
rewrite file times without anything being compiled. **A `.ts` newer than the
bundle beside it means something stamped a build that did not produce that
bundle** - almost always a compile test that wrote its output elsewhere.

## What is inside: `Module.Path.Symbol`, null-terminated

Symbols sit in a plain null-terminated ASCII pool. A source that declares
`module BetterNetrunning.Breach` contributes `BetterNetrunning.Breach.<symbol>`;
a source with no module contributes the bare name. So membership answers "is this
mod's code in the bundle", but only if you match both forms.

**Three ways to get a false absence.** Each was found by getting it wrong first,
and together they turned 11 flagged mods into 1 real one on an install of 233:

- **A bare module name is never in the pool.** Probing for
  `BetterNetrunning.RemoteBreach.Core` finds nothing while
  `BetterNetrunning.RemoteBreach.Core.<symbol>` is present. Match the symbol, not
  the module.
- **Declarations inside comments.** Mods document their own API in `/** */`
  headers - WannabeEdgerunner lists five `public func` signatures that way. Strip
  comments before parsing sources, or you will report a mod as broken because it
  documented itself.
- **`@if(ModuleExists("Other"))`.** redscript compiles conditionally. A
  compatibility class for a mod the user does not have is *correctly* absent.
  That is information ("the bridge to X is inactive"), never damage.

Symbols under three characters cannot be looked up in a 35 MB blob without
matching noise. Say "cannot tell", not "absent".

## What absence actually means

Once the false positives are gone, an absent symbol has two readings, and the
mod's file times separate them:

- **Deployed after the bundle was built** - the mod is installed, enabled,
  correct, and *not running yet*. It compiles in on the next launch. This is the
  common case and it is invisible in game: no error, no missing-feature message.
- **Older than the bundle and still absent** - it was there when the compiler
  ran and did not make it in. Look at the log for that run.

And the whole-install version of the same question: if the last real compile did
not print `Compilation complete`, **every** `.reds` mod is off, not just the one
being investigated. That is the all-or-nothing gate described in
`environment.md`; this file is how you check the half of it the log cannot tell
you.

`tools/Test-ScriptsLive.ps1` does all of the above.
