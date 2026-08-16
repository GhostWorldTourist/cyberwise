# Archives, hashes, and finding out who owns a file

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> **Re-check after a patch:** The RDAR index layout and FNV1a-64 hashing are stable across patches; dictionary coverage is not. Re-measure how much KnownHashes.txt resolves before relying on a negative result.

## Reading an .archive index without any tooling

You do not need WolvenKit to answer "which mods collide" or "what does this archive
contain". The index is plain structured data; only the file *bodies* are compressed.

```
header:  'RDAR' u32 | version u32 | indexPosition u64 | indexSize u32
at indexPosition:
         fileTableOffset u32 | fileTableSize u32 | crc u64
         fileEntryCount u32 | fileSegmentCount u32 | resourceDependencyCount u32   (28 bytes)
then fileEntryCount entries of 56 bytes each; the first 8 bytes are the name hash
```

File data is **Oodle-compressed**, so running `strings` over an archive returns
garbage. Only the index is readable this way.

## Path hashing

Resource names are **FNV1a-64 over the raw ASCII depot path**, backslash-separated,
exactly as written:

```
h = 0xCBF29CE484222325
for each byte b:  h ^= b;  h *= 0x100000001B3
```

Implement it in a language with wrapping 64-bit multiply. PowerShell throws on
`UInt64` overflow - use an inline C# helper via `Add-Type`.

## Resolving hashes back to paths

Two dictionaries, both incomplete:

- **Codeware's `KnownHashes.txt`** - *if Codeware is present.* It ships at
  `red4ext\plugins\Codeware\Data\` under the game root, and Codeware is a mod
  dependency, not part of the game, so plenty of installs simply do not have it.
  Roughly 127k paths. **On one large mod list it resolved only about 20% of archive
  entries.** It is mesh, entity and rig heavy; it contains **almost no texture
  paths**, no scene, questphase or audio paths. A *negative* result is only
  meaningful for a path you have already confirmed is in the dictionary.
- **WolvenKit** ships its own, broader dictionary. If it is installed, extracting an
  archive and listing the output is the fastest way to see real paths.

Assume neither is available until you have checked. Neither is required for the
work below.

**Collision detection needs no dictionary at all** - the same hash appearing in two
archives is a conflict regardless of whether you can name the file. Prefer working
from collisions when identifying culprits, and only reach for path resolution when
you need to explain *what* is conflicting.

## Practical recipes

**"Which mod owns file X?"** Hash the depot path, scan every archive index for that
hash, then sort the owners by whatever governs order on that install - `modlist.txt`
position where the file exists, alphabetical where it does not, the manager's list
where the manager owns ordering. Earliest wins. See `load-order.md` before
assuming which.

**"Why do two body parts not match?"** Do not start with load order. Extract the
suspect archives and read their actual file lists. A skin patch that ships torso
and arm textures but no leg textures cannot ever match the legs, and no reordering
will change that.

**"What is this archive actually for?"** Extract it and look at the path prefixes.
Vanilla content lives under `base\characters\...`, `base\quest\...` etc. Prefixes
like `base\4k\`, `base\v_textures\`, or a body-mod's own namespace mean the archive
is a **patch layer over another mod**, and it is inert without that mod installed.

## WolvenKit CLI round-trip

Needed only to see real paths or to *edit* content. Everything above - collision
detection, ownership, "what is in this archive" by hash - works with no WolvenKit
at all, so do not make it a prerequisite for a user who has never installed it.

The CLI is a **separate download** from the GUI - a GUI install has no CLI.

```
WolvenKit.CLI extract <archive> -o <dir> [-w "*pattern*"] [--hash <hash>]
WolvenKit.CLI convert serialize <file> -o <dir>      # output dir must exist
   ... edit the .json ...
WolvenKit.CLI convert deserialize <file>.json        # writes the binary beside it
WolvenKit.CLI pack <rootdir> -o <dir>                # rootdir mirrors depot paths
WolvenKit.CLI hash "<depot\path>"
```

- `-w` matches the **full depot path**, not just the filename.
- Copy the source archive to a short, apostrophe-free path first; both long paths
  and apostrophes misbehave.
- Enable Windows long-path support - packing requires it.
- Delete the `.json` files before packing.
- Old files (pre-2.0-era mods) may fail `convert serialize` outright. That is a
  converter limitation, not a corrupt archive.

## Editing serialized JSON

- Edit by **targeted regex on the raw text**. `ConvertFrom-Json` piped back through
  `ConvertTo-Json` mangles typed RED4 structures. Reading via `ConvertFrom-Json` is
  fine; writing is not.
- Values usually appear **twice** - once in `components`, again in the compiled
  buffer. A global replace is normally correct; a single-occurrence edit is normally
  a bug.
- **Do not empty arrays holding handle references.** Emptying an `effectDescs`
  array left dangling handles and the file would no longer convert. Change a flag
  instead.
- `HandleId` values must be unique across the whole file. Cloning a block without
  renumbering produces a file that converts but behaves oddly.
