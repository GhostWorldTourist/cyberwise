---
name: cyberwise-crashes
description: Diagnose Cyberpunk 2077 crashes, hangs and failures to launch on a modded install - which log actually says what, how to bisect a large mod list without wasting launches, and why the obvious memory reading is usually wrong. Use when the game crashes, hangs, closes silently, or stops launching after a mod change.
---

# Cyberwise: crashes, hangs and bisecting

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> **Re-check after a patch:** Confirm log paths and the crash-report filename first; those move between versions.

**Check the patch version before hunting for a log** - the paths and the
crash-report filename move between versions, and a log you cannot find reads as
a log that was never written:

```powershell
(Get-Item "$GameRoot\bin\x64\Cyberpunk2077.exe").VersionInfo.ProductVersion
```

Load `cyberwise` alongside this for the method rules. Two matter enormously here:

- **Reproduce before bisecting.** One crash is not a deterministic fault. Bisect
  noise and you will "fix" it by coincidence, then be surprised later.
- **Confirm the mod is deployed.** A crash blamed on a mod that was never
  actually deployed is a whole evening.

## Start by asking what changed

Bisection is for when the suspect set is too big to inspect - it is not a ritual.
At every size the first question is *what changed*, not *which half*. Under about
twenty mods, a binary search is roughly five launches to find something the user
could have named in zero.

`references/bisecting.md` sizes the method to the list, and covers why parking
files on disk is unreliable on a managed install - a manager can restore a parked
file mid-test, and on MO2 the archives may not physically be there at all.

## A missing log is not a silent log

None of REDscript, RED4ext, CET, ArchiveXL or TweakXL ship with the game. An
archives-only load order legitimately has none of them, and `r6\logs\` may not
exist. Absence means "that framework is not installed", not "that framework
reported nothing".

`references/diagnosis.md` maps symptom to the log that actually carries it.

## Memory is usually a red herring

Only open a memory investigation when it is genuinely a suspect - `isOom: true`,
or a crash that only appears deep into long sessions. Startup legitimately ramps
GPU memory hard, so a reading taken during it proves nothing.

`references/crashes.md` covers the crash report the game writes itself, why
Windows Error Reporting never fires for it, and the measurement traps.

## Tools

| tool | what it does |
|---|---|
| `tools/Watch-Crashes.ps1` | samples the running game to CSV and captures its post-mortem on death |
| `tools/Register-CrashWatch.ps1` | registers the watcher as a logon task so it survives death and reboot |

```powershell
.\tools\Register-CrashWatch.ps1 -Dir "<somewhere writable>" -GameRoot "<game>"
.\tools\Register-CrashWatch.ps1 -Status      # registered? running?
.\tools\Register-CrashWatch.ps1 -Remove
```

Three things about this that are not obvious:

- **The capture is deduped on `crashVisitId`.** `CrashInfo.json` is overwritten
  per crash but never deleted, so a watcher that copies it on every exit
  re-saves the same record after each normal quit. See `references/crashes.md` -
  that mistake produced 21 files holding 2 real crashes and a fabricated cluster.
- **Register it rather than launching it.** A shell-launched watcher dies with
  the shell, on reboot, and silently on error. Worse, **an assistant may be
  unable to start one at all** - a sandboxed tool session can reap the process
  tree when the call returns, so `Start-Process` reports success and nothing
  runs. The task scheduler owns the process instead.
- **Verify it is actually running**, with `-Status`. Match the process on its
  `-File` argument; a bare script-name substring also matches the query asking
  the question, which cheerfully reports a watcher that is not there.

## Reference material

| file | covers |
|---|---|
| `references/diagnosis.md` | which log says what, locating a visual symptom, failure shapes |
| `references/bisecting.md` | sizing the search to the list, layer-first passes, why automated hang detection fails |
| `references/crashes.md` | CrashInfo.json, why WER never fires, memory measurement traps |

To capture the machine and install facts that change a crash diagnosis - VRAM
against texture volume, pagefile, framework versions - `cyberwise-reports` has
the system profiler. Start there when someone arrives with "it's broken" and no
detail.
