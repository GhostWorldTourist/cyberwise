# Cyberwise

A family of skills for for **Claude Code and Codex** to work with modded **Cyberpunk 2077** installs.

It isn't a modding tutorial or mod list. Instead, it makes your agent smarter about things that are counterintuitive, undocumented, or actively contradicted by knowledgeable advice. This suite was built to assist with a real, highly complex 800+ mod install and informed by knowledgeable advice, hours of research, and painstaking empirical proof instead of the lazy guessing AIs like to do when something "looks right enough". Whether you have 20 mods or 900, use Vortex, MO2, or drag and drop mods into your folder, these tools will make your life easier.

## How to get started

**Cyberwise is not a mod, a mod manager, or a program you run.** It is a set of notes and scripts that make an **AI coding assistant** competent at Cyberpunk 2077 modding instead of confidently wrong about it (which is exactly what it is by default).

So it needs an AI assistant with a **paid plan**. Due to the way Cyberwise teaches your agent, free plans are not supported. At this time, **Claude Code** (Anthropic) or **ChatGPT / Codex** (OpenAI) are supported. Cyberwise requires Windows. Mac and Linux are not supported.

Once installed, you talk to it normally: *"my Borg-4a shotgun fires invisible bullets"*, *"which mod is making everyone grey"*, *"what is bound to F3"*. The skills load themselves when the subject comes up.

**If you don't want to use AI, the notes are still worth reading.** Every `references/` file is plain markdown written for humans as much as machines - why `zzz_` prefixes are backwards, why a mod can be installed, enabled and doing nothing, why Windows Error Reporting never fires for this game. You lose the tools, not the knowledge.

```powershell
git clone https://github.com/GhostWorldTourist/cyberwise ~/repos/cyberwise
cd ~/repos/cyberwise
.\install.ps1            # links the skills into Claude Code and Codex
```

Then restart your agent. Full detail, including the tray app, is further down.

If you're having troubles getting started, you can simply ask your agent "Help me get https://github.com/GhostWorldTourist/cyberwise working" and it will figure it out.

## What it looks like

A walkthrough on a real 850-mod install. The bracketed notes comment on what the skill adds over just trying to use an AI agent by itself to help you with your modded game (lol don't).

---

**“can you just tell me if any mods are broken or conflicting? I don't know how to check that”**

> Nothing is broken, and nothing is conflicting in a way that's costing you.
>
> **Your 233 script mods all loaded.** That matters because it's all-or-nothing: if one script mod fails to compile, *every* script mod switches off, with no message in the game. Yours reports "Compilation complete", so they're all live.
>
> **Load order is clean.** I scanned all 727 archives against each other — 67,490 individual files — looking for mods that are enabled but contributing nothing because something else wins every file they touch. That's the silent failure that looks like "I installed it and nothing happened."
>
> **Seven came up as contributing nothing, and all seven are fine.** Two are one mod packaged twice; four are conflicts you already settled. One is a prop pack whose real content isn't in the archive at all — it registers props into World Builder through a separate file. Uninstalling it on "the archive does nothing" evidence would have broken your prop browser.

> *[Three things the skill supplied. That the redscript gate is all-or-nothing and silent, so it must be checked first. That "inert archive" is even a concept. And the rule that an inert **archive** is not an inert **mod**. Things like this are the difference between good advice and breaking somebody's modded game.]*

---

**“what mods are changing the way vehicles handle?”**

> Six, and they're not fighting each other — each adjusts different properties: slope traction, steering response, downforce, differential overshoot, friction multipliers, added gravity.
>
> They all write to the same vehicle *records*, which is why a conflict checker flags them as overlapping — but they set **different properties inside** those records, so nothing is overwritten. All six are in effect.
>
> Night City Traffic Overhaul also touches vehicles heavily, but it changes traffic *behaviour*, not how your car feels.

> *[The trap here is real: "touching the same record" and "fighting over the same value" look identical in a conflict report, and only the second is a problem. Assuming otherwise is how people uninstall four working mods to fix nothing.]*

---

**“my cars feel weird taking corners… they don't slide much so it feels really slow”**

> Found it, and it's a single number. **Lonny Driving Tweaks** raises lateral friction — literally how much the car resists sliding sideways:
>
> ```
> Asphalt:  frictionLatMultiplier: 1.3   #1.2
> Sand:     frictionLatMultiplier: 1.2   #0.65
> ```
>
> On sand that's nearly double the sideways grip — sand is meant to be the surface you slide on. That's your "doesn't slide, feels slow" exactly.
>
> I checked Cyber Grip too, since the name suggests it. **Not your problem** — it sets `perfectSteeringFactor: 0`, which *removes* the game's steering assist and makes cars looser, not tighter.
>
> Also: **you've never adjusted any of these in game.** I checked your saved settings. What you're feeling is the authors' choices, not something you set and forgot.

> *[Two skill rules doing the work. "Never quote a mod's shipped defaults as the user's configuration". The real settings file gets read first. And the name-based guess (Cyber **Grip** causes grip) is exactly the wrong answer, ruled out by reading the values instead of the name. AI agents without help like this will make up what mods do constantly. Cyberwise knows how to actually look.]*

The fix offered was a small companion mod setting those friction values, loading after Lonny so it wins, leaving Lonny's own file untouched, surviving its updates, and removable in one click. Cyberwise remembers these tweak mods it makes, so if Lonny changes that file later you get told rather than silently keeping a stale copy.

**[See what it produces →](SCREENSHOTS.md)** — the system profile, a 780-mod inventory, a hotkey cheatsheet for your second monitor, and the tray icon. Real output from a real install, with what each page is showing and why.

## The family

`cyberwise` is the front door: the method rules that apply to every task, where each kind of mod lives on disk, and a routing table. The topic skills are separate so that reading about keybinds costs nothing when the question is about textures.

| skill | use it when |
|---|---|
| `cyberwise` | always - the method rules the rest depend on |
| `cyberwise-conflicts` | for when a mod does nothing; textures look wrong; load order; `.archive` internals |
| `cyberwise-crashes` | crashes, hangs, failures to launch; log triage; bisecting |
| `cyberwise-saves` | reading a save, appearance data, character presets |
| `cyberwise-hotkeys` | what a key is bound to; generating a cheatsheet |
| `cyberwise-reports` | mod inventory, system profile, any HTML/markdown deliverable |
| `cyberwise-tweaks` | TweakXL/TweakDB edits, CET Lua, finding game text |
| `cyberwise-reshade` | ReShade add-on builds, shader pack collisions |
| `cyberwise-backstory` | building a character: V's history, voice, roleplay decisions, a dossier |
| `cyberwise-feedback` | Cyberwise itself got something wrong, or you want to reach the author |

**They work together automatically:** a hotkey sheet is also an HTML deliverable, so Cyberwise will use both `cyberwise-hotkeys` and `cyberwise-reports`.

`cyberwise-backstory` is the odd one out, and deliberately so: it is about **playing** the game rather than fixing it. It interviews you about your V rather than writing one, knows the lifepath prologues well enough to ask questions only this game could ask, and states where something sits relative to canon exactly once without arguing about it. It lives here because this is where the Cyberpunk knowledge already is.

Each skill owns its own `references/` and `tools/` outright - there is no shared directory, because ten copies of a reference is ten things to drift. `environment.md` is the one genuinely cross-cutting file and it lives in the front door.

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


## The tray app runs the crash watcher

```powershell
cd app; .\build.ps1 -Run
```

`app/` builds **CyberwiseTray.exe** (~30 KB, no runtime to install) — a system tray icon that runs the crash watcher and reports its state continuously.

Green means watching. Amber means the watcher is down, but also the game is closed, so nothing is being missed. **Red means the game is running and the watcher is not**, which is the one state that is actively losing evidence and the only one that raises a notification. It can register the watcher as a logon task, and **Copy crash summary** puts the last ten crashes on the clipboard as plain text, which is what someone actually needs when they go and ask for help. This watcher only looks at Cyberpunk 2077, is open source, and simply helps diagnose crashes. It is completely optional, but it's highly recommended. Cyberwise can read the crash reports and help with what went wrong. Those knowledgeable with modding support will also appreciate the information if they're helping you with something.

`CyberwiseTray.exe --selftest` prints everything it can see, and prints `NOT FOUND` rather than a plausible default. See `app/README.md`.

## Nothing here modifies your install without you knowing it

That distinction is the most important one in this repo. Every tool below only writes its own reports or modifies data specific to Cyberwise. Your agent, using the tools, can make changes to your install, but will be very clear about what its doing, and you can always tell it not to change anything, to help you make the changes yourself, or undo changes it made. The agent is careful to backup files and remember actions it takes so it can undo things.

Two tools ship as part of the safety methods: `ModFileBackup.ps1` for the edit itself, and `ModPatchWatch.ps1` to notice later when the file you patched has changed underneath you:

```powershell
. tools\ModFileBackup.ps1
Show-ModFileDiff   -Path $f -NewText $updated              # preview, writes nothing
Set-ModFileContent -Path $f -NewText $updated -Note 'why'  # snapshot, then write
Restore-ModFile    -Path $f                                # undo
```

Snapshots live under `%LOCALAPPDATA%\cyberwise\backups`, deliberately outside the game directory, which a mod manager may purge or redeploy over. A restore snapshots what it replaced, so restores can also be undone.

And mods that Cyberwise helps you tweak are watched for when you update them so the patch can be adjusted:

```powershell
. tools\ModPatchWatch.ps1
Register-ModPatch -Name 'x' -UpstreamPath '<their file>' -OverridePath '<yours>' -Note 'why'
Test-ModPatches                 # after any mod update
Show-ModPatchDrift -Name 'x'    # what THEY changed, when it says CHANGED
```

**Re-deriving a tweak on an updated mod is judgement work; it's never automated.** Replaying an old edit against a refactored file either fails, or worse, succeeds in the wrong place. The tool shows you what changed; it does not guess.

## Included tools

Tools live with the skill that uses them: `cyberwise/tools/` (the backup helper above, which is cross-cutting), `cyberwise-hotkeys/tools/`, `cyberwise-conflicts/tools/`, `cyberwise-crashes/tools/`, `cyberwise-reports/tools/`, `cyberwise-saves/tools/` and `cyberwise-feedback/tools/`.

`New-ModManifest.ps1` builds a readable inventory of an installed load order: every mod, what it deploys, its Nexus link and install date, and - with an API key - a one-line description of what it actually does. `-HideNSFW` omits adult content.

It needs no credentials for the basics, because a manager that installed from Nexus encodes `<Display Name>-<NexusID>-<version>-<timestamp>` into the staging folder name. It reads a manager's staging root: the Vortex layout is found automatically, MO2 needs `-StagingRoot` pointed at its `mods\` folder, and a fully manual install has no staging tree for it to read. Folders that do not match the convention are still listed, from the folder name alone - a mod dropped from an inventory is a mod nobody knows they have.

`-NoNexus` guarantees it stays offline. A key stored in Credential Manager is used automatically, so omitting `-NexusApiKey` is not the same as making no network call.

Also included: `Get-Hotkeys.ps1` / `New-HotkeySheet.ps1` (every keybind on an install, from all five stores that hold them, rendered as a cheatsheet), `New-SystemProfile.ps1` (a machine and install profile that says what is likely wrong, redacted by default because the markdown is meant for pasting in public), `Measure-PageFit.ps1` (does a generated page fit a stated viewport), `NexusCredential.ps1` (stores a Nexus API key in Windows Credential Manager) and `New-ProblemReport.ps1` (gathers version, install shape and environment into a report you can send me).

**Anything meant to be pasted is built to fit.** Discord refuses a message over 2000 characters rather than shortening it, so an over-long paste doesn't arrive clipped — it doesn't arrive. The profile warns with the character count, the manifest names the file and the HTML as the alternatives, the problem report writes a separate Discord-sized version, and the tray trims a crash summary before it reaches the clipboard — dropping oldest first, and saying how many it dropped.

`cyberwise-crashes/tools/` carries `Watch-Crashes.ps1`, which samples the running game to CSV and captures its own post-mortem telemetry on death, and `Register-CrashWatch.ps1`, which registers that as a logon task so it restarts itself and survives a reboot. The game catches its own fault and exits, so nothing reaches Windows Error Reporting — `CrashInfo.json` is the only first-party evidence, and it is overwritten on the next crash. **The capture is deduped on `crashVisitId`**: an unconditional copy re-saves the same record after every clean quit, which on one install turned 2 real crashes into 21 files and a cluster that never happened.

`cyberwise-saves/tools/` carries `Expand-Save.ps1`, which decompresses a `sav.dat` into one flat searchable blob, and `Decode-Preset.ps1`, which turns ACU `.preset` files into readable appearance fields. Expand-Save hand-rolls an LZ4 **block** decoder because .NET has none and the chunks are blocks rather than frames, so a general LZ4 library will refuse them.

**Decoded saves are personal data.** Write them to a temp path; never into a repo.

**Pass your own paths.** These scripts carry defaults - a game root, a staging root, a viewport - and those defaults are the author's machine, not yours. Use `-GameRoot`, `-StagingRoot`, `-Width`/`-Height`.

## Install

```powershell
git clone https://github.com/GhostWorldTourist/cyberwise ~/repos/cyberwise
cd ~/repos/cyberwise
.\install.ps1          # -Remove to unlink, -ClaudeOnly to skip Codex
```

**Works with Claude Code and Codex**, from one install. Each skill under `skills/` is symlinked into `~/.claude/skills/` *and* `~/.codex/skills/` (or `$CODEX_HOME/skills`), so edits take effect immediately with no reinstall step and the two agents cannot drift apart. It falls back to a directory junction where a symlink would need elevation.

Then restart your agent so it refreshes its global skill catalog.

To install by hand instead, copy each directory under `skills/` into `~/.claude/skills/` (or a project's `.claude/skills/`) and `~/.codex/skills/`. Either agent loads them when you ask about Cyberpunk 2077 mod problems; you can also invoke one directly, e.g. `/cyberwise-conflicts`.

## Tests

```powershell
.\tests\Test-Family.ps1         # structural validation of the family
.\tests\Test-Validator.ps1      # proves the validator above can actually fail
.\tests\Test-Tools.ps1          # runs the tools against synthetic installs
.\tests\Test-ToolMutations.ps1  # reintroduces shipped bugs, expects to be caught
```

The two halves check different things, and the second is the one that matters more. **Structure is not behaviour, and parsing is not working.** Every defect these tools have actually shipped parsed perfectly and was filed correctly.

A skill family breaks *silently*. A `references/foo.md` that no longer exists, a frontmatter `name` that stopped matching its directory, a route to a renamed skill - none of it errors. The skill loads and quietly cannot find the thing it just told the model to go and read. Splitting cyberwise into parts produced exactly one of those; it was caught by hand, and the point of `Test-Family.ps1` is that the next one is caught by the machine.

It checks many things, including that every reference and tool a `SKILL.md` names resolves inside that skill, that every shipped reference is actually mentioned by its owner, that every topic skill is reachable from the front door, that every reference carries its own **Verified** / **Re-check after a patch** stamp, and that no absolute user path has leaked into a public repo.

The GitHub issue forms are checked the same way, and for the same reason: a malformed one doesn't error, it just quietly stops appearing in the chooser, and nobody opens issues against their own repo to find out.

One of those is about drift: a **Verified** stamp must name a comparable version number, *or* the file must say in as many words that nothing in it depends on a game patch. "Verified: recently" is not a stamp, and the distinction between "not patch-dependent" and "nobody wrote down which patch" is the whole point.

`Test-Validator.ps1` exists because a validator that has only ever returned green is indistinguishable from one that returns green unconditionally. It copies the family to a temp directory, injects one real fault at a time - a moved reference, a renamed skill, a `.ps1` that no longer parses - and asserts that *the check which owns that fault* is the one that reports, then that the tree comes back clean afterwards. It found two bugs in the validator it tests.

### Testing the tools

`Test-Tools.ps1` builds synthetic installs in a temp directory and runs the real scripts against them. It does not use or require a real game install. It covers many things that agents naturally misunderstand.

A synthetic staging tree covers the manifest: a hyphenated name like `Cyber-Engine-Tweaks-107-1-35-1-...` still resolves to id 107, that a version of `2k` survives, a non-conforming MO2 or hand-unzipped folder still lists, and that a CET mod is not also tagged an ASI plugin - `bin\x64\plugins` is an *ancestor* of the CET mods path, so a naive existence check catches every one.

That last one is a good illustration of why the mutation suite exists. The first version of the test asserted on the section headings, which looked right and passed - but a mod is filed under its *primary* footprint, and CET wins that ordering with or without the bug. Only reintroducing the defect showed the test was watching a surface where it could never appear. The spurious label shows up in the meta line as `CET+ASI`, which is what the test checks now.

The backup helper is covered too, and one of those tests exists because the first version of `Show-ModFileDiff` **lied**: it reported "3 lines removed, 0 added" for a one-line insertion, because `(if (...) {...} else {...})` is not a valid sub-expression in PowerShell and the new text came back empty. The write itself was correct — only the preview was wrong, which is exactly the thing the user is asked to approve. A preview that lies is worse than no preview at all.

It also builds a five-store keybind fixture - a mod shipping `IK_F3`, a `user.ini` rebinding it to `IK_F7`, a `buttonGroup` indirection in the cache, and a `bindings.json` with keys differing only in case - and asserts the user's rebind wins. That is the family's flagship rule (*never quote a mod's shipped defaults as the user's configuration*) and this is the only place it is mechanically enforced. An unbound CET entry must stay unreported, too: a key the tool fails to find reads as a key that is **free**.

`Test-ToolMutations.ps1` reintroduces each of those bugs verbatim into a copy and asserts that the test which owns it fails. Reintroducing the `#` bug reproduces its original signature exactly - three modlist entries counted instead of four, two archives reported unlisted instead of one.

It runs each suite in a **fresh process**, which is not optional: `Expand-Save.ps1` compiles its LZ4 decoder with `Add-Type`, and a compiled type cannot be replaced once loaded, so an in-process re-run silently keeps the first version's decoder and the mutation looks undetectable.

None of it needs anything installed. Pester would be a dependency, and the family's whole position is that PowerShell is already on the machine.

**Adding a skill?** Run all four tests against it. The reachability and routing checks will tell you what you forgot to wire into the front door.

## Scope and honesty

- This was created with **game patch 2.31**. Paths and behaviours drift between patches, and they drift at very different rates. I'll make an effort to update this if CPDR updates the game, but until I do, you should assume Cyberwise is broken.
- **THIS WAS NOT "VIBE CODED".** Obviously, an AI agent helped me build it. But I know Powershell and enough Python to understand what was created, I made specific directed edits to code itself, and I human-directed the creation of these skills. I use it personally, have tested it extensively, and did not just trust an AI to get things right.
- The above said, I'm sure there's things in here that are wrong, because I'm a human and AIs put the "artificial" in artificial intelligence. I will try to fix things that are wrong, and if you can point out what was wrong, that would help a lot. You can ask your agent "help me report this problem" and it will help gather what I need to fix it.
- **Every file carries its own verification stamp**, because references get read in isolation. An AI reading `cyberwise-crashes/references/crashes.md` needs to know what else is important to know about before answering based on those instructions. Each one also has a **Re-check after a patch** line naming what to re-test first, so a new patch means triaging a handful of files rather than re-auditing everything. The highest-drift areas are flagged as such: save format first, then TweakDB record IDs, then crash telemetry.
- Findings are empirical, and most of the measuring happened on one large Vortex-managed install. Game behaviour (archives, load order, saves, TweakDB, logs) does not care which manager put the files there. Manager-specific behaviour is another matter. I am extensively familiar with Vortex, MO2, and manual mod installation, but I don't use MO2 with this game, so you may occassionally encounter rough edges. 
- **The tools are PowerShell on Windows, deliberately, and there is no other runtime to install.** The diagnostics are Windows APIs rather than incidentally Windows code: the registry for locating the install and reading true VRAM past the 4 GB `AdapterRAM` ceiling, CIM for pagefile and disk media, Credential Manager for the API key.
- **The notes are the portable half, and they are portable today.** File formats, hash algorithms and diagnostic reasoning have no operating system. A Linux/Proton user gets every `references/` directory and none of the tools; the paths there sit under the Proton prefix and none of that has been tested here.
- Nothing here is a substitute for reading the logs. Several notes exist purely to say *which* log, because that is the part people skip.
- **The tray app is not code-signed.** Depending on your settings and software, you might see a warning on first run, and a tray app that spawns PowerShell and inspects other processes is a textbook antivirus false positive. You can read every line of `app/CyberwiseTray.cs` and build it yourself with `app\build.ps1`. It compiles with the C# compiler already in Windows, so you need nothing installed to check what you are running. If you don't trust it and don't want to audit it, you can also just not use it.
- **Nothing here phones home.** The only network call any tool makes is to the Nexus API, only when you supply an API key, and `-NoNexus` disables it outright. The crash watcher and snapshots write to your own disk and nowhere else.

## Contributing

Corrections are welcome, particularly ones that correct anything an agent using Cyberwise gets wrong. Bad information is worse than "I don't know". If you see issues, tell your agent to help you file an issue.

Saying *"help me report this problem"* loads `cyberwise-feedback`, which gathers the version, environment and exact error text itself, strips your username and paths out of it, and hands you a finished message — plus a shorter one that fits in a single Discord post. There are [issue forms](.github/ISSUE_TEMPLATE) for both a bug and a wrong note; the wrong-note one asks the least and is worth the most.

## Getting Help

I hang out in the [Ultra Place Discord](https://discord.gg/UltraPlace), so you can `@GhostWorldTourist` in the #cyberpunk channel. Note that this is *not* some "official Cyberwise support channel". I am the only one who supports this suite right now, so please be patient and wait for me to answer. Do not harass other people about it, please. They are good people and it's a really good place to talk about Cyberpunk 2077 and other games. While you're there, check out Ultra+ for CP2077, because it's genuinely cool.

## Licence

[MIT](LICENSE) — the code and the notes both. Take it, fork it, paste a script into your own tool, quote a finding in your guide. Keep the copyright line and you're square with me.

Two things the licence doesn't cover, so I'll just say them:

- **Credit the finding, not just the file.** If something here saves you an afternoon and you write it up somewhere, a link back means the next person can check the working rather than taking your word for it. That matters more here than usual, because half of this repo is claims about a game that keeps changing.
- **The name and the eye are mine.** No licence grants trademark rights, MIT included. Fork the code freely; if you ship it as your own thing, give it your own name so nobody files your bugs with me.
