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
