# Saves and appearance data

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> **Re-check after a patch:** HIGHEST DRIFT IN THIS SKILL. The save format carries its own version number (269 when this was written) and CDPR revises it. Re-verify the chunk table layout and the node-offset arithmetic against a fresh save before trusting any parse.

## Read the metadata first

Each save is a folder under `Saved Games\CD Projekt Red\Cyberpunk 2077\` in the
user's profile. Inside it, `metadata.9.json` sits beside `sav.dat` and needs **no
decoding**. It carries level, street cred, attributes, skills, lifepath, playtime,
difficulty, build/patch version, active quests and some quest facts. Most questions
about a playthrough are answered here without touching the save proper.

A save is personal data. Read what the question needs, quote back the minimum, and
do not write a decoded save or an appearance dump anywhere it could be shared.

Note `LocKey#<small number>` values in metadata are localization **primaryKeys**,
not hashes.

## Decompressing sav.dat

The save is a container of LZ4 **blocks** (not frames) - which is the first thing
to get right, because a frame decoder will simply refuse them. If your language has
no LZ4 in its standard library (.NET and PowerShell do not), the block decoder is
about 40 lines and is safer than adding a dependency.

```
'CSAV' magic (stored 'VASC') | saveVersion u32 | gameVersion u32 | 13 misc bytes
'CLZF' marker (stored 'FZLC') | chunkCount u32
then chunkCount triplets: fileOffset u32, compressedSize u32, decompressedSize u32
each chunk payload begins with an 8-byte header ('XLZ4' + decompressed size),
the remainder is a raw LZ4 block
```

**The node table is NOT compressed.** It sits in the raw file after the last chunk
and ends with `ENOD`. Entries are:

```
[lenByte][name][id u32][0xFFFFFFFF][offset u32][size u32]
```

where `lenByte` is `0x80 | length`.

### The offset trap

Node offsets are into the **logical** file, which includes the uncompressed header.
Index into your decompressed blob as:

```
blobIndex = nodeOffset - firstChunkFileOffset
```

Skip this and the last node overruns the end of your buffer by ~1700 bytes, which
looks exactly like a decompression bug and is not.

## Appearance data in the save

The node is **`CharacetrCustomization_Appearances`** - CDPR's own typo. Search for
`Characetr`, not `Character`.

Its strings are `<resource>` / `<optionName>` pairs: a CDPR asset name on one side
and the customization option it fills on the other. Option names read like
`hair_color29`, `piercings_11`, `makeupEyes_03` - note that the numeric padding is
inconsistent between groups, which matters if you go looking for a key by name.

Useful structure inside it: separate appearance blocks for `TPP_Body`, `FPP_Body`
and `character_creation`. **These can disagree.** A body part referenced by
`character_creation` but not by `TPP_Body` will render in the creator preview and
not in the world - a real source of "it looks right in the mirror but not in game".

Face morphs appear as global IDs, shaped like `eyes h011` / `nose h052` - a group
name plus an `h`-prefixed three-digit number. These are **not** the
character-creator slider numbers and there is no simple offset between them.

## AppearanceChangeUnlocker preset format

Only relevant if the install has AppearanceChangeUnlocker (ACU) - it is a popular
appearance mod but far from universal, so confirm it is there before explaining a
file in its terms.

Each line of an ACU preset is `LocKey#<n>:<index>`.

**`<n>` is not a localization key.** Resolving it against the game's localization
finds nothing. It is the **FNV1a-64 hash of the customization group name** -
`hairstyle`, `makeupEyes`, `piercings`, `eyes_color`. `<index>` is the
character-creator slider value.

**Colour keys embed the style index.** Hairstyle `<n>`'s colour is stored under
`hair_color<n>`, eyebrow colour under `eyebrows_color<n>`, and so on. So two presets
using different hairstyles legitimately have **different key sets and different line
counts**. That is not corruption and not evidence of differing mod loadouts.

Padding is inconsistent in CDPR's naming (`piercings_11`, `makeupEyes_03`,
`hair_color29`), so a brute-force sweep must try all spellings.

**A preset only stores groups that existed when it was saved.** If a CCXL mod adds
new customization options later, older presets carry no keys for them - the look is
not "missing" those features, the preset simply predates them. Date a preset
against the mod set of its day before concluding anything is wrong.

**Do not reconcile preset indices against numbers recorded anywhere else** - notes,
a screenshot of the creator, a build write-up. There is no single rule: some fields
read one lower (0-based), others match exactly, and some disagree outright. The
preset is authoritative; a mismatch is not evidence that anything is wrong.
