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

## Start by asking what changed - and now you can answer it

```powershell
.\tools\New-InstallSnapshot.ps1 -Label 'before the DF update'
.\tools\Compare-InstallSnapshot.ps1            # newest vs the one before
.\tools\Compare-InstallSnapshot.ps1 -Since 20260810
```

"It worked yesterday" is the most common and least usable sentence in mod
support, because nothing records yesterday. A snapshot costs about a second and a
megabyte and records every archive, the modlist **order**, every loose script,
tweak, Lua and plugin, and the framework versions. Two of them turn "somewhere in
700 mods" into a diff that is usually three lines long.

**`Watch-Crashes.ps1` takes one automatically at every session start**, so the
history builds itself. A snapshot taken by hand is a snapshot nobody takes.

**Read the diff before proposing a bisect.** Bisecting is for when nothing else
narrows it - it is not the opening move, and at this game's load times it costs an
evening to rediscover something a diff names immediately.

The one it catches that nothing else does: **`LOAD ORDER ... moved`**. A mod whose
position changed now wins or loses files it did not before, and *nothing about it
looks different on disk* - same file, same size, same timestamp. Verified on a
727-archive install: one entry moved from position 131 to 10 was reported exactly,
with no false positives anywhere else.

A diff that finds nothing is also an answer: the install did not change, so look
at settings, save state or drivers - or accept it may not be deterministic.

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
| `tools/Watch-Crashes.ps1` | samples the running game to CSV, captures its post-mortem on death, snapshots the install at session start |
| `tools/Register-CrashWatch.ps1` | registers the watcher as a logon task so it survives death and reboot |
| `tools/New-InstallSnapshot.ps1` | records archives, load order, loose files and framework versions |
| `tools/Compare-InstallSnapshot.ps1` | diffs two snapshots - what changed, including order changes invisible on disk |

```powershell
.\tools\Register-CrashWatch.ps1 -Dir "<somewhere writable>" -GameRoot "<game>"
.\tools\Register-CrashWatch.ps1 -Status      # registered? running?
.\tools\Register-CrashWatch.ps1 -Remove
```

### The tray app is optional, and you build it for them

There is a tray icon in `app/` that runs the watcher and shows its state. **Build
it for the user - do not hand them build instructions.** It compiles with the C#
compiler already present in Windows, so nothing needs installing:

```powershell
cd app; .\build.ps1 -Run
```

**Say it is optional, because it is.** Everything works from the scripts alone.
The tray exists so somebody who never opens a terminal can see whether recording
is happening, and start or stop it.

Expect questions, and answer them plainly rather than technically:

- *"Is it safe?"* - it watches memory use and copies the crash report the game
  writes. It changes nothing in the game or in mods.
- *"Will Windows warn me?"* - yes, it is not code-signed, so SmartScreen shows
  "unknown publisher". That is a statement about a certificate nobody bought, not
  about the file. They can read the source and you just built it in front of them.
- *"Does it phone home?"* - no. Nothing here contacts the internet except the mod
  inventory, and only if they supply a Nexus key.
- *"Can I remove it?"* - close it from the menu, delete the folder. It puts one
  entry in the startup list, removable from the same menu or Task Manager.

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
- **Starting it twice is safe.** The watcher holds a mutex keyed on its output
  folder and a second launch exits immediately, so the tray, a logon entry and
  someone at a prompt cannot end up interleaving session CSVs. A second *game
  install*, with its own folder, still gets its own watcher.

**"It stopped starting at logon" is almost always a moved folder.** Both
autostart routes - the tray's toggle and this script's fallback - write an
**absolute path** into `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.
Move, rename or delete the folder and Windows fails to launch it at logon and
says nothing whatsoever. There is no error, no log, no dialog: the icon just
stops appearing, and if the watcher started from there the recording stops with
it. Weeks of "crashes" can pass with nothing recorded.

Check the entry against the filesystem before believing anything else:

```powershell
$v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run').'Cyberwise'
$v; Test-Path ($v -replace '"','')      # False = this is your problem
```

The tray detects this itself now - it warns at startup and `--selftest` reports
the target path and flags a missing one - but a user who has not opened it will
not have seen that. Turning the setting off and on again re-points it at the
copy that is actually running.

Anything installed by cloning a repo has this property. It is the strongest
argument for a real installer: a copy in a stable location does not move when
somebody tidies their projects folder.

**Task registration may simply be refused.** On the machine this was written
against, `schtasks /Create` returns "Access is denied" both from an agent session
and from an ordinary PowerShell window - so treat the scheduled task as the nice
case, not the expected one. `Register-CrashWatch.ps1` falls back to a per-user
`HKCU\...\Run` entry, which needs no elevation, and says plainly what that costs:
the watcher starts at logon but nothing restarts it if it dies.

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
