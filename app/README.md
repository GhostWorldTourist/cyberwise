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

## The colours

| colour | meaning |
|---|---|
| **green** | watching |
| **amber** | not watching, game not running — nothing is being missed |
| **red** | **game running, watcher not** — evidence is being lost right now |

Red is the only state that demands action, so it is the only one that gets a
balloon notification. A new crash capture gets one too, naming the district and
session length.

## The menu

- **Watcher / Game / Crashes recorded** — live status, refreshed every 5 s
- **Start / Stop watching**
- **Start automatically at logon** — registers a scheduled task via `schtasks`
- **Copy crash summary** — the last ten crashes as plain text, for pasting when
  asking someone for help. That is the action this audience actually needs next.
- **Open crash folder**, **Settings…**, **Reload settings**, **Exit**

Exit leaves the watcher running on purpose: quitting the UI should not silently
stop a recording someone is relying on.

## Self-test

```powershell
.\bin\CyberwiseTray.exe --selftest
```

Prints everything the app can see — detected game root and version, watcher
script, whether the watcher and game are running, whether the logon task exists,
and the crashes on file. It reports what it **found**, and prints `NOT FOUND`
rather than a plausible default, because a wrong guess presented confidently is
worse than a blank.

It is a `winexe` with no console of its own, so it attaches to the parent
console to print. Run it from a terminal and the output appears there.

## Settings

`%APPDATA%\cyberwise\tray.ini`, written on first run so the auto-detected values
are visible and editable rather than living only in memory:

```ini
GameRoot=C:\...\Cyberpunk 2077
WatchDir=C:\...\Cyberpunk 2077\_crashwatch
Watcher=C:\...\Watch-Crashes.ps1
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

## Not done yet

- **Not code-signed.** SmartScreen will warn, and a tray app that spawns
  PowerShell and inspects other processes is a textbook antivirus false
  positive. Signing needs a certificate and a verified identity.
- **No installer.** This builds an exe; it does not place it, create a Start
  Menu entry, or install the skills.
- **Only tested on one machine**, by the person who wrote it.
