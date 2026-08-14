# Saves and appearance data

## Read the metadata first

`metadata.9.json` sits beside `sav.dat` in each save folder and needs **no
decoding**. It carries level, street cred, attributes, skills, lifepath, playtime,
difficulty, build/patch version, active quests and some quest facts. Most questions
about a playthrough are answered here without touching the save proper.

Note `LocKey#<small number>` values in metadata are localization **primaryKeys**,
not hashes.

## Decompressing sav.dat

The save is a container of LZ4 **blocks** (not frames). .NET has no LZ4, but the
block decoder is about 40 lines and is safer than adding a dependency.

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

Its strings are `<resource>` / `<optionName>` pairs, for example
`08_blonde_dishwater` / `hair_color29`, plus `piercings_11`, `makeupEyes_03`,
`skin_type_04`, `01_ca_pale`.

Useful structure inside it: separate appearance blocks for `TPP_Body`, `FPP_Body`
and `character_creation`. **These can disagree.** A body part referenced by
`character_creation` but not by `TPP_Body` will render in the creator preview and
not in the world - a real source of "it looks right in the mirror but not in game".

Face morphs appear as global IDs (`eyes h011`, `nose h052`, `mouth h153`). These
are **not** the character-creator slider numbers and there is no simple offset
between them.

## AppearanceChangeUnlocker preset format

Each line is `LocKey#<n>:<index>`.

**`<n>` is not a localization key.** Resolving it against the game's localization
finds nothing. It is the **FNV1a-64 hash of the customization group name** -
`hairstyle`, `makeupEyes`, `piercings`, `eyes_color`. `<index>` is the
character-creator slider value.

**Colour keys embed the style index.** Hairstyle 29's colour is stored under
`hair_color29`, eyebrow colour under `eyebrows_color8`. So two presets using
different hairstyles legitimately have **different key sets and different line
counts**. That is not corruption and not evidence of differing mod loadouts.

Padding is inconsistent in CDPR's naming (`piercings_11`, `makeupEyes_03`,
`hair_color29`), so a brute-force sweep must try all spellings.

**A preset only stores groups that existed when it was saved.** If a CCXL mod adds
new customization options later, older presets carry no keys for them - the look is
not "missing" those features, the preset simply predates them. Date a preset
against the mod set of its day before concluding anything is wrong.

**Do not convert preset indices into numbers from a hand-written character sheet.**
There is no single rule - some fields read one lower (0-based), others match
exactly, and some disagree outright. The preset is authoritative.
