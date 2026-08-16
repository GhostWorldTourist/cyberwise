# Cyberwise tray

A system tray icon for people who do not open terminals.

```powershell
.\build.ps1          # -> bin\CyberwiseTray.exe   (~22 KB)
.\build.ps1 -Run     # build and launch
```

## Why

Cyberwise's diagnostics are PowerShell, and its audience is Cyberpunk 2077
modders — most of whom will never open a terminal, and many of whom are put off
by the idea. A tray icon is an interface point they already understand: visible,
right-clickable, always there. This is that point, and the crash watcher is its
first job.

A watcher launched from a shell dies with the shell, dies on reboot, and dies
silently if it throws. **An investigation that believes it is recording and is
not is worse than one that knows it has no data** — the next crash simply looks
like it produced no telemetry. So the icon reports watcher state continuously
rather than assuming it.

## The icon

A slit-pupil eye, drawn at runtime so state is a colour rather than three files.

| colour | meaning |
|---|---|
| **green** | watching |
| **amber** | not watching, game not running — nothing is being missed |
| **red** | **game running, watcher not** — evidence is being lost right now |

Red is the only state that demands action, so it is the only one that gets a
balloon notification. A new crash capture gets one too, naming the district and
session length.

### Designing for sixteen pixels

There is room for about four ideas at tray size, so they have to be the right
four: an **almond outline** (a disc reads as a status dot, a lens reads as an
eye), a **bright iris** carrying the state colour, a **vertical slit** — the one
feature doing all the "not human" work — and a **pale sclera**.

The sclera is not decoration. A dark icon on a dark taskbar disappears for
everyone using dark mode, and no amount of iris colour fixes it; the pale lens
gives the shape something to read against, while the dark outline drawn over the
top does the same job on a light taskbar. Both halves of that are load-bearing.

The specular highlight is drawn **only above 16 px**. At tray-default size it
lands within a pixel of the slit and merges with it, reading as a notch bitten
out of the pupil. A detail that turns to noise at the size the thing is actually
used is worse than no detail — which is also why there are no aperture blades,
circuitry or eyelid, all of which were considered and all of which turn to mud.

Everything is proportional to the requested size, because the tray asks for 16,
20, 24 or 32 px depending on DPI and a shape hard-coded for 16 looks stretched
at 32.

```powershell
.\bin\CyberwiseTray.exe --icon-preview out.png
```

Renders every state at every tray size, on both light and dark backgrounds, with
6× blow-ups — using the **same** drawing code the tray uses, so what you inspect
is what ships. A 16 px icon cannot be judged from source; this is the only
honest way to check it is legible, and it took three passes. The first version
was a plain disc, and the second put the highlight through the pupil.

## What it is called

The exe carries a version resource, so Windows shows it as **Cyberwise** — in
Settings ▸ Taskbar ▸ *Select which icons appear on the taskbar*, in Task Manager,
and in its own properties. Without one, Windows falls back to the filename
(`CyberwiseTray.exe`), which reads like something that installed itself without
asking. `AssemblyTitle` becomes `FileDescription`; `csc` builds the resource from
the assembly attributes, so there is no separate `.rc` file to keep in sync.

## The menu

- **Watcher / Game / Crashes recorded** — live status, refreshed every 5 s
- **Start / Stop watching**
- **Start Cyberwise when I log in** — a per-user `HKCU\...\Run` entry, no admin needed
- **Copy crash summary** — the last ten crashes as plain text, for pasting when
  asking someone for help. That is the action this audience actually needs next.
- **Open crash folder**, **Settings…**, **Reload settings**, **Exit**

Exit leaves the watcher running on purpose: quitting the UI should not silently
stop a recording someone is relying on.

### Why autostart is a Run key and not a scheduled task

The first version registered a `schtasks /SC ONLOGON` task and failed with
**"Could not create the logon task: ERROR: Access is denied"** — in the user's
own session, not a sandbox. Creating a task in the root folder generally wants
elevation, and a per-user tray app should never ask for admin.

`HKCU\Software\Microsoft\Windows\CurrentVersion\Run` needs no elevation ever, is
the ordinary mechanism for exactly this, and shows up in Task Manager ▸ Startup
where someone can turn it off without coming back here.

It also autostarts **the tray**, not the watcher — so there is one thing to
supervise instead of two. `AutoStartWatcher=true` in the settings then starts
the recording as the tray comes up, because an icon that returns after a reboot
and quietly records nothing is worse than no icon at all.

### The path trap, and how it is caught

A Run entry stores an **absolute path**. Move, rename or delete the folder this
exe lives in and Windows fails to launch it at logon **silently** — no error, no
log, no dialog. The icon simply stops appearing, and the recording stops with it.
Someone can lose weeks of crash data to a tidy-up.

Since this whole app exists to stop things failing quietly, it checks itself: at
startup it warns if the logon entry points at a file that is gone or at a
*different copy* of Cyberwise, and `--selftest` prints the target path with a
`WARNING` line when it is wrong. Toggling the setting off and on re-points it at
whichever copy is running.

Running from a cloned repo makes this likely rather than theoretical — and
`bin/` is gitignored, so a fresh clone has no exe until you run `build.ps1`.
Both are arguments for a real installer putting a copy somewhere stable.

## Self-test

```powershell
.\bin\CyberwiseTray.exe --selftest
```

Prints everything the app can see — detected game root and version, watcher
script, whether the watcher and game are running, whether autostart is on,
and the crashes on file. It reports what it **found**, and prints `NOT FOUND`
rather than a plausible default, because a wrong guess presented confidently is
worse than a blank.

It is a `winexe` with no console of its own, so it attaches to the parent
console to print. Run it from a terminal and the output appears there.

**It cannot be piped**, and that surprises people. A GUI-subsystem executable
does not block the shell — `& .\CyberwiseTray.exe --selftest | Out-String`
returns immediately with nothing, because the shell has already moved on and the
text goes to the console buffer rather than to a stream PowerShell is capturing.
To capture it:

```powershell
Start-Process .\bin\CyberwiseTray.exe --selftest -NoNewWindow -Wait `
    -RedirectStandardOutput out.txt
```

The same applies to `--icon-preview`: without `-Wait` you will check for the PNG
before it has been written.

## Settings

`%APPDATA%\cyberwise\tray.ini`, written on first run so the auto-detected values
are visible and editable rather than living only in memory:

```ini
GameRoot=C:\...\Cyberpunk 2077
WatchDir=C:\...\Cyberpunk 2077\_crashwatch
Watcher=C:\...\Watch-Crashes.ps1
AutoStartWatcher=true
```

The game root is found from Steam's registry entry (including alternate library
folders listed in `libraryfolders.vdf`) and GOG's, and every candidate is
confirmed by `bin\x64\Cyberpunk2077.exe` actually being there. Steam, GOG and
Epic all install elsewhere and the drive is the user's choice, so a default path
is never assumed.

## Build choices

**.NET Framework 4.8, and no SDK anywhere.**

- It builds with the `csc.exe` already present on every Windows machine, so
  nobody needs a toolchain to build it.
- It targets a runtime that ships with Windows 10 1903+ and Windows 11, so
  **nobody needs to install a runtime to run it.**

A .NET 8/9 build would be a nicer development experience and would hand every
user either a runtime prompt or a ~70 MB self-contained binary. For an audience
whose defining trait is being put off by setup, that trade is the wrong way
round. 22 KB and no prerequisites wins.

The icon is drawn at runtime rather than shipped as a `.ico`, which is what
makes state a colour.

## Two traps this code is careful about

**Every path is quoted when launching the watcher.** The default game folder is
`Cyberpunk 2077` — with a space — and an unquoted path splits, so PowerShell
receives a truncated `-File` and the process dies instantly. That failure looks
exactly like "the platform will not let me start a process", and cost real time
on this project before it was understood.

**The watcher is found by its `-File` argument, never by a bare script-name
substring.** A bare match also matches the process doing the asking, which
reports a watcher that is not there.

## The installer

```powershell
.\build-installer.ps1      # -> dist\Cyberwise-Setup-<version>.exe   (~2 MB)
```

Needs Inno Setup, which is one command and installs per-user:

```powershell
winget install --id JRSoftware.InnoSetup
```

**It never asks for admin.** `PrivilegesRequired=lowest`, everything per-user:
the app in `%LOCALAPPDATA%\Programs\Cyberwise`, the skills in the user's own
profile, autostart in `HKCU`. An unsigned installer that also throws a UAC shield
is exactly where this audience stops.

Three optional tasks, and the first two are checked by default: start at logon,
install the skills for Claude Code and Codex, create a desktop shortcut.

Skills are linked by **the repo's own `install.ps1`**, shipped inside the
install, rather than a second implementation in Pascal. One linking
implementation to keep correct instead of two to drift apart.

### It killed the author's skill links the first time it was tested

Worth recording, because it is the sharpest bug this project has produced.

The uninstaller ran `install.ps1 -Remove`, which deleted every `cyberwise*` link
**by name**. On a machine where the author also had the repo linked for
development, uninstalling a throwaway test install silently removed those links
too — a destructive side effect on files the uninstall had nothing to do with.

`install.ps1 -Remove` now removes only links that resolve to **its own** skills
directory, and reports the ones it skipped. Both halves are tested: another
copy's uninstall leaves these links alone, and a copy can still remove its own.

The general shape is worth carrying: **an uninstaller that matches by name
deletes other people's things.** Match by target.

## Not done yet

- **Not code-signed.** SmartScreen will warn, and a tray app that spawns
  PowerShell and inspects other processes is a textbook antivirus false
  positive. Signing needs a certificate and a verified identity.
- **Only tested on one machine**, by the person who wrote it.
