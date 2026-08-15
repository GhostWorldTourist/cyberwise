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
systemic.

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

**Startup genuinely ramps 0 to ~14 GB of GPU memory in about two minutes.** Sampling
once during that ramp and once after it, then reporting the difference as a leak,
is an easy and confident mistake. It was made here and reported as "≈1.5 GB/min
sustained growth", which was pure measurement error.

To claim a leak you need a **trend across a long session**, not two points. A
40-minute capture in the same investigation showed memory plateauing after the load
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

Sample every 15-30 s to CSV: working set, private bytes, per-process and adapter
GPU memory, free RAM, handle count, thread count. Write a marker when the process
disappears, and copy `CrashInfo.json` on death before it is overwritten.

**`Start-Job` does not work for this.** Background jobs are children of the calling
PowerShell session and die when the call returns. Launch detached:

```powershell
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList `
    '-NoProfile','-ExecutionPolicy','Bypass','-File',"<path>\watch.ps1","-Out","<csv>"
```

## Single-variable testing

Crash investigations accumulate variables fast - driver updates, settings changes,
mod changes. Change one at a time and record which. In one session a mod setting
test and a driver update were nearly run together, which would have made both
results uninterpretable.

Prefer tests that are instant and reversible. An in-game Mod Settings toggle beats
a redeploy; a graphics setting beats a driver rollback.

## Reading mod source is inference, not measurement

You can find a genuine defect by reading a mod's code - a leak, an asymmetric guard
clause, an unbounded array - and still not have found *your* crash. Label it
accordingly. In one case a real resource leak was identified in a mod's redscript,
and the crash continued after that mod was fully undeployed.
