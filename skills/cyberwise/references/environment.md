# Environment, mod managers, and tooling traps

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> **Re-check after a patch:** Mod manager behaviour rather than game behaviour, so it drifts with Vortex/MO2 releases. The redscript compile-test invocation is the part most likely to change with a scc update.

Every path here is **relative to the game install root**. Steam, GOG and Epic put
that root in different places, users move it, and it is not always on C:. Get the
real root once - from the manager, from the launcher, or by asking - and never
assume a drive letter.

## Read the user's real settings, not a mod's defaults

If the Mod Settings framework is installed, `red4ext\plugins\mod_settings\user.ini`
holds the user's overrides as `[Module.Class]` sections with `key = value`. On a
heavily modded install it runs to thousands of entries; on a small one it may be
short or missing. **A missing key means "never overridden", not "not configurable"** -
the shipped default is then what applies.

**Check it first for any "what is X set to" or "which key does Y" question.**
Quoting a shipped default has caused real errors - one mod's XML declared a hotkey
of `IK_O` while the user's actual binding in `user.ini` was `IK_Pause`.

Not every mod uses Mod Settings. Others keep configuration in a CET mod's own
`.json`, in a `.reds` constant, or in a menu of their own. There is no single
settings store; work out which one the mod in question uses before quoting a value.

## Establish how the install is assembled FIRST

Almost every technique in this skill reads the game directory. Whether that
directory tells you the truth depends entirely on how mods got there, and there are
three very different answers. **Determine which one you are looking at before
trusting anything on disk.**

### Detecting the mode

| look for | means |
|---|---|
| `__folder_managed_by_vortex` marker files; a staging root full of `<Display Name>-<NexusID>-<version>-<timestamp>` folders; deployed files with **link count 2** | Vortex |
| `ModOrganizer.ini`; mods under MO2's own `mods\` tree; a game directory that looks suspiciously bare while the game is closed | MO2 |
| files simply present, no markers, no staging root, no deployment step | manual |

Vortex's staging root defaults to `%APPDATA%\Vortex\<game>\mods`, but it is
relocatable and frequently relocated - hardlink deployment requires it to sit on
the same volume as the game. MO2's `mods\` tree likewise lives wherever the
instance was created. **Ask for the path; do not assume one.**

These modes are also not exclusive. A managed install routinely carries
hand-dropped files alongside the managed ones, plus files mods write at runtime, so
"the manager doesn't list it" is not evidence a file isn't loaded.

When in doubt, ask. It is one question and it changes the entire approach.

### Manual install

The simplest case and the one everything here assumes by default: files are
physically in the game directory and what you see is what the game loads. It is
not a beginners-only setup - large hand-built load orders exist, and the techniques
here scale to them.

Caveats: there is no staging copy, so **any hand-edit you make is the only copy** -
back it up before editing. And there is no manifest, so nothing can tell you which
mod a given file came from: a mod's files are merged into the game's own directory
tree, so grouping-by-folder only works where the mod happened to ship a folder of
its own. Filename and that folder are all you have.

Because there is no manifest, an uninstall is a manual file-by-file removal, and
leftovers from a half-removed mod are a routine cause of "I already uninstalled
that". Keep the downloaded archives - their file lists are the only record of what
each mod put where.

### Vortex

- **Deployment is by hardlink** *on the default deployment method*. Editing a
  deployed file then also edits the staging copy. Useful for patching, but a mod
  reinstall reverts hand-patches. Vortex can also be set to symlink or move
  deployment; under those the next two bullets do not hold, so **check the game's
  deployment method before relying on either**.
- **Write through the link.** Tools that replace a file by delete-and-recreate break
  the hardlink and desynchronise staging. Prefer in-place writes.
- **Link count tells you the origin.** Under hardlink deployment, a deployed file
  with link count 2 is manager-managed. Link count 1 means it was created in-game or
  installed manually - which is why a purge does not remove it (it is not in the
  deployment manifest). This is the fastest way to explain a file the manager
  denies owning.
- **Staging folder names lie about versions.** Updates happen *in place*, keeping
  the original folder name while replacing files. Never infer a version from the
  folder name; check the RED4ext log for plugins, or compare against the download
  archive.
- **Never diff the mod directory mid-deploy.** Doing so reports transient states as
  additions and removals. Confirm no operation is running first.

### MO2 - the important one, because the filesystem lies

MO2 and Cyberpunk are **not natively compatible**; using MO2 without extra setup
produces CET and RED4ext errors. Working installs rely on the **Root Builder**
plugin, and that changes what you can see:

- **Root Builder copies its folders into the game directory at launch and removes
  them again when the game closes.** So inspecting the game directory while the game
  is shut down can show you almost nothing, and what it does show may be stale.
- **USVFS virtualisation means mod files may never be physically present** in the
  game directory at all - the merged view exists only for processes inside MO2's
  virtual filesystem. A script run from outside sees the bare game.
- CET **1.27+** is required for USVFS compatibility; 1.26 and earlier do not work.
  A confusing CET failure on an MO2 install is worth checking against this first.
- REDmod deploys automatically before launch, so REDmod state is also a
  launch-time artifact rather than something sitting on disk.

**Practical consequences.** On an MO2 install:

- "The file isn't there" is not evidence the mod isn't installed.
- Conflict and load-order scanning must be done against **MO2's own mod list and
  its virtual ordering**, not against `archive\pc\mod` on disk.
- Ask the user to check MO2's UI, or to run your inspection **through MO2** so it
  inherits the VFS, rather than from a plain shell.
- Hand-editing a deployed file is pointless if Root Builder will discard it on exit.
  Edit the file in MO2's mod folder instead.

If you are unsure whether a given install virtualises, the quick test is: with the
game closed, does `archive\pc\mod` contain the archives the user says are enabled?
If not, you are outside the VFS and must change approach.

## A manager only owns what it deployed

Files written **directly into the game directory** are invisible to the manager
that is supposed to be running the install. A purge, a redeploy, or an update of
the mod they belong to silently reverts or orphans them, and the deployed state
drifts from staging with nothing reporting it.

This bites hardest when it appears to work. On one install a working version of a
hand-built mod existed **only** as loose files in `r6\tweaks`, while staging still
held the superseded version - so the next deploy quietly restored the old one and
the "fixed" mod stopped being fixed, for reasons nothing explained.

**Package a mod as a zip and let the user install it through their manager**
rather than writing into the game folder. Then the manager owns it, an uninstall
is clean, and the version they have is the version it believes they have.

Two deliberate exceptions, both worth naming out loud when you take them:

- **Patching another mod's own file in place**, when the fix genuinely is an edit
  to their file. Where the manager deploys by **hardlink**, edit *both* the
  deployed file and the staging copy - editing can break the link and leave them
  independent, so the change silently vanishes at the next deploy.
- **Diagnostic tooling and backups the user has agreed to.** Keep them in clearly
  named folders that cannot be mistaken for mod content, and say they are there.

## The mod's own settings UI writes on exit

Where mods share a settings framework, the in-game panel is the source of truth
and it **writes its config file when the session ends**. An edit made externally
while the game is running is overwritten on exit with no error - the change simply
is not there next time, and the obvious conclusion ("the setting does not work")
is wrong.

So **report what differs and which setting controls it, then stop.** A diff of
intent against saved values is genuinely useful; a blind write to the config file
is a change the user did not see, may lose anyway, and cannot easily undo. Offer
to write it only if they ask for that.

## Files created in-game are not backed up by the manager

Presets, saved configurations and script libraries written by mods at runtime are
created after deployment, so no manager has a copy of them.

- **Vortex:** they exist only in the deployed game folder. They survive a purge
  (not being in the deployment manifest) but are lost on a mod reinstall or a
  manual clean.
- **MO2:** writes made from inside the VFS are normally redirected into the
  **Overwrite** folder rather than into the mod that prompted them, so they exist
  but belong to no mod. Look there before concluding a preset was lost.
- **Manual:** they sit alongside the mod's own files and are indistinguishable
  from them, so a "delete the mod folder" uninstall takes them with it.

Either way: back these up somewhere outside the game directory if they represent
real work.

## Resolving an internal name back to a findable mod

Never leave the user holding an identifier they cannot search for. Internal names
are chosen by authors for their own convenience and frequently share nothing with
the mod's public name.

### How to look it up

| manager | method |
|---|---|
| Vortex | the staging folder name encodes it: `<Display Name>-<NexusID>-<version>-<timestamp>` |
| MO2 | the `mods\` subfolder name is the name shown in the UI (set at install, so user-edited) |
| manual | **no mapping exists.** The folder name is all there is - say so rather than guessing |

The Vortex pattern holds for mods installed from Nexus. Anything added from a
local archive, or dragged in by hand, can carry any folder name at all - so treat
a name that does not match the pattern as "unknown provenance", not as a parse
failure.

For a file rather than a folder, find which staging folder (or MO2 mod folder)
contains that filename. That single step answers "which mod is this from" far more
reliably than reasoning about the name. With no manager there is no such index, and
the honest answer is that the file cannot be traced from disk alone.

### Why it is worth doing even when you think you know

**A file's name may have nothing to do with the mod shipping it.** An archive called
`_33removeunderwearforarchivexl.archive` turned out to be bundled inside a **dress
mod** - the author shipped it as a dependency so the dress would sit correctly.
Searching the manager for "underwear" found nothing, and the user could not locate
it until the containing mod was identified by tracing the file back to staging.

**The folder name carries more than the name.** A staging folder reading
`01 - BODY - PALE-15426-1-1-<timestamp>` tells you the display name is
"01 - BODY - PALE", the Nexus ID is 15426, and - from the `01` prefix - that this is
one numbered part of a **modular** mod. When a user's problem turned out to be a
missing leg texture, that `01` was the clue that other parts existed and one of them
might supply it.

**Version matters and the folder lies about it** - see the Vortex note above.
Report the version from the RED4ext log or the download archive, not the folder.

### File timestamps do not tell you when a mod was installed

Managers preserve the timestamps inside the mod archive, so a deployed file's mtime
is the **mod author's build date**, not the install date. "Find everything newer
than last Tuesday" will therefore miss most of a fresh deploy and is not a reliable
way to answer "what changed".

What is reliable: diff the archive list against a known-good `modlist.txt`, or read
the manager's own install dates (Vortex staging folder names carry an install
timestamp as their trailing number; MO2 shows an install date per mod). With no
manager, the list diff is the only option, which is a good reason to keep a copy
of the last known-good one.

The exception that misleads further: logs and caches under `red4ext\plugins\*` *do*
update on every run, so a timestamp sweep will surface those and make it look like
framework plugins were updated when only their logs moved. Check the DLL's own date
before concluding a framework changed.

### What to give the user

Display name, Nexus ID, and where it deployed. That is enough to find it in a
manager, find it on Nexus, and check its file list for parts they may not have.

## Redscript compilation is all-or-nothing

**If redscript fails to compile, every single `.reds` mod is silently off.** Not
degraded - off. There is no in-game indication. On one install this was true for
**eight months** before anyone noticed, and during that time a whole category of
mods appeared installed, enabled, and did nothing.

Check `r6\logs\redscript_*.log` for `Compilation complete` and a plausible source
reference count. This should be among the first things verified on any install where
"a script mod isn't working". The log is written by the game at runtime, so on a
virtualising install look for it wherever that manager redirects runtime writes
(MO2: Overwrite) rather than concluding it was never produced.

Causes seen, none of them obvious:

- **Duplicate class definitions** - the same mod installed twice under different
  names (two downloads from one Nexus page, byte-identical `.reds` files).
- **A missing module dependency** - one mod importing a module that ships in a
  separate "core" download, producing dozens of errors from one absent mod.
- **A stale hand-patch** - a hand-edit made to work around an old incompatibility,
  still in place after the author shipped a real fix that did more.

Also: **a plugin's script directory only compiles if the plugin's DLL loads.** A
plugin shipped accidentally as a *Debug* build imports `MSVCP140D.dll`,
`ucrtbased.dll` and `VCRUNTIME140D.dll`, which are not present on a normal machine.
RED4ext logs error 126 and the plugin never loads - so its scripts never compile and
the mod is completely inert with no other symptom. Check `red4ext.log` for load
failures before believing a plugin is active.

## Two downloads from one mod page may not be alternatives

Do not assume that files labelled like variants are mutually exclusive. Compare
their **contents and file counts** first.

A real case: one download was the full package (23 files - a script plus 20 tweak
files and an archive), while the "alternative" was 2 files (a manifest and a
*different build* of the same script). Disabling the first to use the second
silently dropped 20 tweaks and an archive that nothing else supplied. The correct
setup was to install **both** and decide explicitly which copy of the shared script
survived - a conflict rule in Vortex, mod priority in MO2, or, installing by hand,
keeping only the intended copy of the contested file.

**Record the file SIZE of the copy that should win.** When two builds of the same
filename contend, size is usually the only way to tell which one is deployed -
they have the same name, the same path, and often the same timestamp. Note the
byte count once, and a redeploy that silently flips the winner becomes a
one-command check instead of an invisible behaviour change:

```powershell
(Get-Item "$GameRoot\<contested file>").Length
```

This matters most for the files nothing warns you about: a script that changes
behaviour reports no error when the other build wins, it just behaves differently.

When two builds of the same filename exist, **file size is the identity tell**.
Record the byte counts; if the number flips after a redeploy, behaviour changed
silently.

## Do not infer duplication from shared records

Several mods writing to the same TweakDB records are not necessarily duplicates.
A set of vehicle-handling mods all wrote to the same vehicle records while touching
**disjoint property sets** - TweakXL merges that fine and all of them were needed.
Compare the *properties* each mod writes, not the records it targets, before
recommending anyone uninstall one.

## Triaging TweakXL errors

A large load order routinely logs dozens of TweakXL errors that are upstream author
bugs with no crash risk. Do not treat the count as a health metric or try to drive
it to zero. (On a small load order the reverse holds: a handful of mods producing a
page of errors is worth actually reading, because there is nothing else to blame.)

One genuinely confusing pattern: **which records fail can vary between launches**,
because another mod is reshaping the same records and the outcome is order-dependent.
A varying error list is not nondeterminism in the game; it is load-order interaction.

## Compile-testing redscript without launching the game

`scc.exe` ships with redscript and lives under the game root, so this only exists
on an install that has redscript at all:

```
<game>\engine\tools\scc.exe -compile <game>\r6\scripts -compilePathsFile <paths> \
    -customCacheDir <dir> -outputCacheFile <file>
```

`<paths>` must list **only the extra script directories** - every directory under
`red4ext\plugins` that contains `.reds` (Codeware, TweakXL, ArchiveXL, mod_settings
and similar). Enumerate them; do not hardcode a list, since which frameworks are
installed varies per install.

- **Do not also list `r6/scripts` in the paths file.** It double-compiles and
  produces thousands of bogus `SYM_REDEFINITION` errors.
- **Do not omit the plugin directories.** That produces bogus "Codeware missing"
  errors instead.

Caution: `scc.exe` writes into `r6\logs` and rotates at 5 files, destroying older
`redscript_*.log` history. Back that folder up first if it matters. It also pops a
GUI dialog on failure, so do not run it unattended.

**On a virtualising install this must be run through the manager.** Started from a
plain shell, it compiles a game directory the mods are not in, and reports a clean
build that means nothing.

## PowerShell traps

The tooling shipped with this skill is PowerShell, and both of these produced
convincing wrong answers before being caught:

- **`Test-Path` without `-LiteralPath`** treats `[` and `]` in mod filenames as
  wildcards. On a large load order this reports a handful of phantom missing files.
- **`Sort-Object $scriptblock` binds `$_`**, so a `param($n)` block inside it
  silently receives `$null` and the sort appears to do nothing.

Also worth knowing:

- `UInt64` arithmetic throws on overflow, which breaks any hash implementation.
  Use an inline C# helper via `Add-Type` where wrapping multiply is required.
- Reading a very large JSON with `ConvertFrom-Json` is slow and memory-hungry.
  Line-by-line reading with a small state machine is faster and more predictable.
- Preserve line endings when rewriting game config files. Many are CRLF; writing LF
  can matter.

## Adding to another author's mod without touching it

Put your files under **your own depot prefix**, referencing their meshes and
materials by path or hash, and register any new entries through the appropriate
extension point rather than editing their files.

Their mod then updates freely and yours only depends on it staying installed.
Overriding their paths directly also works, but goes stale on every update and is
invisible to the user until something looks wrong.
