# Environment, mod managers, and tooling traps

## Read the user's real settings, not a mod's defaults

`red4ext\plugins\mod_settings\user.ini` holds every Mod Settings override as
`[Module.Class]` sections with `key = value`. On a large install this runs to
thousands of entries.

**Check it first for any "what is X set to" or "which key does Y" question.**
Quoting a shipped default has caused real errors - one mod's XML declared a hotkey
of `IK_O` while the user's actual binding in `user.ini` was `IK_Pause`.

## Establish how the install is assembled FIRST

Almost every technique in this skill reads the game directory. Whether that
directory tells you the truth depends entirely on how mods got there, and there are
three very different answers. **Determine which one you are looking at before
trusting anything on disk.**

### Detecting the mode

| look for | means |
|---|---|
| `__folder_managed_by_vortex` marker files; a staging root at `%APPDATA%\Vortex\<game>\mods`; deployed files with **link count 2** | Vortex |
| `ModOrganizer.ini`; mods under MO2's own `mods\` tree; a game directory that looks suspiciously bare while the game is closed | MO2 |
| files simply present, no markers, no staging root, no deployment step | manual |

When in doubt, ask. It is one question and it changes the entire approach.

### Manual install

The simplest case and the one everything here assumes by default: files are
physically in the game directory and what you see is what the game loads.

Caveats: there is no staging copy, so **any hand-edit you make is the only copy** -
back it up before editing. And there is no manifest, so nothing can tell you which
mod a given file came from. Filename and the mod's own folder are all you have.

### Vortex

- **Deployment is by hardlink.** Editing a deployed file also edits the staging
  copy. Useful for patching, but a mod reinstall reverts hand-patches.
- **Write through the link.** Tools that replace a file by delete-and-recreate break
  the hardlink and desynchronise staging. Prefer in-place writes.
- **Link count tells you the origin.** A deployed file with link count 2 is
  manager-managed. Link count 1 means it was created in-game or installed manually -
  which is why a purge does not remove it (it is not in the deployment manifest).
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

## Files created in-game are not backed up by the manager

Presets, saved configurations and script libraries written by mods at runtime exist
**only** in the deployed folder, with no staging copy. They survive a purge (not
being in the manifest) but are lost on a mod reinstall or a manual clean. Back
these up somewhere outside the game directory if they represent real work.

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

For a file rather than a folder, find which staging folder contains that filename.
That single step answers "which mod is this from" far more reliably than reasoning
about the name.

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
the manager's own install dates. Vortex staging folder names carry an install
timestamp as their trailing number.

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
"a script mod isn't working".

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
setup was to install **both** and let a manager conflict rule decide which copy of
the shared script survived.

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
it to zero.

One genuinely confusing pattern: **which records fail can vary between launches**,
because another mod is reshaping the same records and the outcome is order-dependent.
A varying error list is not nondeterminism in the game; it is load-order interaction.

## Compile-testing redscript without launching the game

```
engine\tools\scc.exe -compile <game>\r6\scripts -compilePathsFile <paths> \
    -customCacheDir <dir> -outputCacheFile <file>
```

`<paths>` must list **only the extra script directories** - every directory under
`red4ext\plugins` that contains `.reds` (Codeware, TweakXL, ArchiveXL, mod_settings
and similar).

- **Do not also list `r6/scripts` in the paths file.** It double-compiles and
  produces thousands of bogus `SYM_REDEFINITION` errors.
- **Do not omit the plugin directories.** That produces bogus "Codeware missing"
  errors instead.

Caution: `scc.exe` writes into `r6\logs` and rotates at 5 files, destroying older
`redscript_*.log` history. Back that folder up first if it matters. It also pops a
GUI dialog on failure, so do not run it unattended.

## PowerShell traps

Both of these produced convincing wrong answers before being caught:

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
