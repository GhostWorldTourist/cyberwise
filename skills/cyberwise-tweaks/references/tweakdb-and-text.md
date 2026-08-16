# TweakDB edits and finding game text

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> **Re-check after a patch:** HIGH DRIFT. Record IDs, vendor stock structure and price component names all move between patches. Re-verify every ID against the current string table; never carry one forward on faith.

## Never guess a record ID

TweakXL writes a string table under `r6\cache\modded\` - a `.str` file whose exact
name carries an expansion suffix on a Phantom Liberty install (`tweakdb_ep1.str`).
It is a plain string table containing every TweakDB record and flat name - hundreds
of thousands of entries. Extract printable ASCII runs and you have a searchable ID
list. It only exists once TweakXL has run, so if it is not there, check that TweakXL
is installed and the game has been launched at least once since.

This matters because **CDPR's naming is genuinely inconsistent**:
`Items.ContagionLvl2Program` but `Items.OverheatProgramLvl2`. A guessed ID produces
a mod that loads clean, logs no error, and silently does nothing. Verify every ID
against the dump before shipping a yaml.

## Vendor stock

- Stock lives in `Vendors.<vendor_id>.itemStock`, an array mixing per-vendor inline
  records (`Vendors.<id>_inlineN`) and shared named records. **Counting inline names
  undercounts badly** - one vendor had 61 inline names against 166 actual entries.
- Each entry carries `generationPrereqs`, typically a player-level tier gate. At
  low tiers only tier-1 slots roll, which is why early-game netrunner vendors stock
  almost nothing.
- **`quantity` is `array:TweakDBID`**, not a scalar. Writing `quantity: 1` makes
  TweakXL reject the whole record. Omit it and inherit from `$base`.
- Use `$base: Vendors.<a real inline stock slot>` when authoring, so you inherit
  the correct record type instead of hardcoding an RTTI type name you cannot verify.

**Do not fabricate stock entries.** Inventing a new stock record produced a vendor
listing with no display name, and three plausible explanations for that were each
disproved before the real cause was found: the entry itself was the problem.

The reliable pattern for "let me buy X earlier" is to **clear
`generationPrereqs: []` on the vendor's own existing slots**. Those keep CDPR's
authored name, price, quality and quantity, so nothing can be malformed.

**Inventories are rolled once and persisted in the save.** A TweakDB change will
not appear until the vendor restocks - skip roughly 24 in-game hours.

## Pricing

Cyberware price is not a scalar on the item. `.buyPrice` is an **array of `Price.*`
component records** combined at runtime, and `Price.ItemQualityMultiplier` is a
curve lookup, not a value.

- Quickhacks price from `Price.BaseHackPrice` x `ItemQualityMultiplier` x a
  per-type multiplier.
- **`Price.CommonQuickhack` and its siblings exist as records but nothing reads
  them.** Editing them changes nothing - a long-standing source of "my price mod
  does nothing".
- **Attached parts are billed with the item.** A cyberdeck shipping pre-installed
  quickhacks in its `slotPartList` costs several times the price of an identical
  bare deck. When diagnosing a price difference, diff the two records' **field
  lists** first; a field present on one and absent on the other is usually the whole
  answer.

## Verifying a tweak applied

1. `red4ext\plugins\TweakXL\TweakXL-<date>.log` - look for your file being read
   with no errors beneath it.
2. Read the flat back at runtime from the CET console (see `cet-lua.md`).

## Finding game text

Extract `base\localization\<locale>\onscreens\onscreens_final.json` from that
locale's text archive and serialize it - `en-us` inside `lang_en_text.archive` for
English, and one such pair per installed language. It contains **UI strings, shards,
emails, journal entries and computer text** - tens of thousands of entries. If the
user quoted text from the game in another language, search that language's archive,
not the English one.

Two traps:

- **It does not contain spoken dialogue or news broadcasts.** Those live in subtitle
  resources. Saying "that text is not in the game" after searching only `onscreens`
  is wrong, and easy to do.
- **Some entries have an empty `secondaryKey`.** Computer inbox mail in particular
  is keyed by `primaryKey` only, so any search that filters on key *names* will miss
  it entirely. Search the `femaleVariant` values, not just the keys.

Entry structure is `femaleVariant`, `maleVariant`, `primaryKey`, `secondaryKey`.
The file is large enough that a streaming line-by-line read beats loading the whole
thing into a JSON parser (in PowerShell, beats `ConvertFrom-Json` by a wide margin).
