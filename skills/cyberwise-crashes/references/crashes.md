# Crash forensics

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> **Re-check after a patch:** HIGH DRIFT. CrashInfo.json is CDPR telemetry and its fields can change or vanish between patches. Confirm the file still appears and still carries isOom, district and sessionLength before building an investigation on it.

## The game writes its own post-mortem

```
%LOCALAPPDATA%\CD Projekt Red\Cyberpunk 2077\CrashInfo.json
```

Written by the game **seconds before it exits**, and **overwritten on every
crash** - snapshot it immediately or you lose the previous one. It contains:

| field | use |
|---|---|
| `district` | where the player was |
| `location` X/Y/Z | exact world position |
| `sessionLength` | seconds, and far more reliable than log timestamps |
| `crashPatch` | game version |
| `isOom` | whether the game considered it out of memory |

**Crash locations across sessions are the single best lead.** If they cluster, it
is a streaming-sector or archive problem in that district. If they scatter, it is
systemic. That only holds if the records are genuinely distinct - see below.

### Dedupe the captures, or you will invent crashes

**The file is overwritten on each crash, but it is NOT deleted on a clean exit.**
It sits there holding the last crash indefinitely. So a watcher that copies it
whenever the process disappears re-saves the *same* record after every normal
quit, each time under a new timestamped filename.

This is not cosmetic. On the install this was written against, **21 captured
files were 2 real crashes** - one copied 9 times, one 12. A location analysis
over that folder "finds" a 9-hit cluster in one district that is a single event
counted nine times, and the conclusion (streaming-sector problem, go bisect
archives in Little China) is entirely manufactured.

**Dedupe on `crashVisitId`**, which the game issues per crash. Keep a list of the
ids already captured and skip anything already on it:

```powershell
$pm  = (Get-Content $CrashInfo -Raw | ConvertFrom-Json).Data.postMortem
$ids = if (Test-Path $seen) { @(Get-Content $seen) } else { @() }
if ($ids -contains $pm.crashVisitId) { 'clean exit - already on file' }
else { Copy-Item ... ; Add-Content $seen $pm.crashVisitId }
```

Two more things that follow from it:

- **Name the capture after `timeCrash`, not the copy time.** The watcher notices
  death whenever it next polls, which can be minutes late, and a filename built
  from that time makes the crash look like it happened then.
- **Record a verdict per session.** Otherwise "the process is gone" is all you
  have, and a normal quit is indistinguishable from a crash in your own logs.

**When you inherit an existing capture folder, count the DISTINCT records before
reading anything into it.** Hash the files or group by `crashVisitId` first. A
folder of near-identically-named JSON files looks like a rich dataset and may be
two events.

## Windows Error Reporting will never help you

The game **catches its own fault, writes telemetry, and exits cleanly**. Nothing
reaches WER. Consequences:

- No Application Error / Hang event, nothing in the System log.
- **No crash dump, even with WER LocalDumps correctly configured** (`DumpType=2`,
  a writable dump folder, correct exe name). It is not misconfiguration - WER only
  fires on *unhandled* exceptions and there isn't one.

Do not spend time chasing WER for this game. Go to `CrashInfo.json` instead.

## Log timestamps lie about the moment of death

A truncated log tail is **not** the crash time. In one measured case
`scripting.log` stopped at 05:07:28 while the process lived until 05:20:19 - a
13-minute error. Deriving "the crash happened at X" from a log tail will send you
looking at the wrong part of the session.

Both `gamelog.log` and CET's `scripting.log` ending mid-write does tell you
something useful though: it was a hard process death, not a clean exit.

## Measuring memory without fooling yourself

Only worth doing if memory is actually a suspect - `isOom: true`, or a crash that
only shows up deep into long sessions. Do not open a memory investigation by
default. If you do measure, the traps below are easy ones to fall into.

**Startup genuinely ramps GPU memory hard, for minutes.** On one heavily modded
install it climbed from 0 to ~14 GB in about two minutes; the figure and the
duration will differ with the card, the settings and the mod list, but the shape
does not. Sampling once during that ramp and once after it, then reporting the
difference as a leak, is an easy and confident mistake - in that investigation it
produced a reported "≈1.5 GB/min sustained growth" that was pure measurement error.

To claim a leak you need a **trend across a long session**, not two points. A
40-minute capture on the same install showed memory plateauing after the load
ramp and then oscillating with no trend for 27 minutes - healthy 15 seconds before
death, with `isOom: false` agreeing.

Other traps in the same area:

- **`Win32_VideoController.AdapterRAM` reports ~4 GB for any large GPU.** It is a
  32-bit WMI artifact. Ignore it and read per-process and adapter memory from
  performance counters instead.
- A GPU memory figure below the card's capacity does **not** refute exhaustion -
  allocation can fail below the ceiling. Equally, do not declare it refuted from a
  single early sample.

## Running a watcher

**This skill now ships one** - `tools/Watch-Crashes.ps1`, with
`tools/Register-CrashWatch.ps1` to run it as a logon task that restarts itself.
Prefer those over writing your own; the rest of this section explains what they
do and why, which still matters when you are reading someone else's watcher.

What such a tool needs to do: sample every 15-30 s to CSV
(working set, private bytes, per-process and adapter GPU memory, free RAM, handle
count, thread count), write a marker when the process disappears, and copy
`CrashInfo.json` on death before the next crash overwrites it - **deduped on
`crashVisitId`**, or the capture folder fills with copies of one crash. See
"Dedupe the captures" above; this is the single easiest way to build a watcher
that produces confident nonsense.

**If you build it in PowerShell, `Start-Job` does not work.** Background jobs are
children of the calling PowerShell session and die when the call returns. Launch
detached instead:

```powershell
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList `
    '-NoProfile','-ExecutionPolicy','Bypass','-File',"<your-watcher.ps1>","-Out","<csv>"
```

The same applies to any agent-launched helper: if it is a child of the session that
started it, it dies with that session.

**An agent may not be able to start it at all.** In a sandboxed or supervised
tool session the whole process tree can be reaped when the call returns, so
`Start-Process` reports success and leaves nothing running. Verify it survived -
check for the process by its `-File <watcher>` command line, not by a substring
that your own query also matches - and if it did not, **hand the command to the
user to run rather than retrying.** A watcher you believe is armed and is not is
worse than none, because the next crash looks like it produced no telemetry.

## Single-variable testing

Crash investigations accumulate variables fast - driver updates, settings changes,
mod changes. Change one at a time and record which. In one session a mod setting
test and a driver update were nearly run together, which would have made both
results uninterpretable.

Prefer tests that are instant and reversible. An in-game mod-settings toggle beats
a redeploy; a graphics setting beats a driver rollback.

## Reading mod source is inference, not measurement

You can find a genuine defect by reading a mod's code - a leak, an asymmetric guard
clause, an unbounded array - and still not have found *your* crash. Label it
accordingly. In one case a real resource leak was identified in a mod's redscript,
and the crash continued after that mod was fully undeployed.
