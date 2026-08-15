# Environment, mod managers, and tooling traps

## Read the user's real settings, not a mod's defaults

`red4ext\plugins\mod_settings\user.ini` holds every Mod Settings override as
`[Module.Class]` sections with `key = value`. On a large install this runs to
thousands of entries.

**Check it first for any "what is X set to" or "which key does Y" question.**
Quoting a shipped default has caused real errors - one mod's XML declared a hotkey
of `IK_O` while the user's actual binding in `user.ini` was `IK_Pause`.

## Mod manager behaviour (Vortex)

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

## Files created in-game are not backed up by the manager

Presets, saved configurations and script libraries written by mods at runtime exist
**only** in the deployed folder, with no staging copy. They survive a purge (not
being in the manifest) but are lost on a mod reinstall or a manual clean. Back
these up somewhere outside the game directory if they represent real work.

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
