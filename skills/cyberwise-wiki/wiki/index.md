---
okf_version: "0.2"
---

# Cyberwise base wiki

Game, engine and format knowledge for a modded Cyberpunk 2077 install, plus
cross-mod interaction patterns that are really facts about the game's data
model, and the process knowledge that keeps work about an install trustworthy.

**This bundle ships.** Knowledge about a specific mod - its settings, how it
works, what its author wrote - belongs to the per-user bundle beside the game's
own data, and never ships. See `cyberwise-wiki` for the boundary and
`Test-Wiki.ps1 -Base` for the check that enforces it.

**Grep this bundle before working anything out from first principles.** Nearly
every article here exists because somebody already lost an afternoon to it, and
most of them record the wrong road alongside the right answer. A few seconds of
searching beats an hour of rediscovery - and the article will also tell you what
it did *not* check.

## Patterns

Facts about the game's data model that surface as mod conflicts. Mods appear
only as examples.

- [A mod that enumerates records will hand the player abstract templates](/patterns/record-enumeration-leaks-templates) - `$base` templates are valid records carrying no display data
- [A settings file the game rewrites answers "what is set", never "what is default"](/patterns/live-state-is-not-defaults) - two disjoint settings stores, and reading the wrong one is confidently wrong
- [A mod's shipped defaults are not proof a human chose anything](/patterns/defaults-can-be-written-by-code) - a mod can seed and persist its own settings during init
- [An "allow nothing" flag short-circuits every other option, and shows no symptom](/patterns/override-flag-silences-the-filter-chain) - no error, no log line, and the settings that look like the fix are the ones it ignores
- [A shared core that announces its own add-ons turns "is this installed" into a lookup](/patterns/shared-core-announces-its-addons) - a runtime manifest beats every file-presence proxy
- [all patterns](/patterns/index)

## Engine

How the game and its script layers behave, independent of any mod.

- [A .reds file on disk is not code the game is running](/engine/compiled-script-bundle) - the bundle is compiled at launch, and three of the absences are false
- [An archived redscript log is named for the run that replaced it](/engine/redscript-log-names-the-wrong-run) - rotation renames the old log with the new run's timestamp
- [Reading live game objects from CET Lua without losing the row that mattered](/engine/cet-lua-runtime) - LuaJIT rather than Lua 5.4, and an out-param slot that moves between builds
- [There are two load-order systems, and a conflict scan only sees one of them](/engine/two-load-order-domains) - nothing ranks loose archives against the REDmod deploy
- [The game's own option registry outranks any mod's account of an engine setting](/engine/option-registry-is-the-authority) - `UserSettings.json` settles whether an option exists on this patch at all
- [all engine articles](/engine/index)

## Formats

How a file is laid out, and how it misleads you - enough to actually parse the
thing.

- [A sav.dat is an LZ4 block container with an uncompressed index bolted on the end](/formats/cyberpunk-save-container) - the offset arithmetic that makes a naive seek look like a decompression bug
- [Appearance lives in a save node CDPR misspelled, and its blocks can disagree](/formats/appearance-in-a-save) - `CharacetrCustomization_Appearances`, and why a part renders in the preview but not the world
- [An ACU preset's LocKey number is a hash of a group name, not a localization key](/formats/acu-preset) - why two presets legitimately have different line counts, and why indices must never be reconciled against notes
- [The ReShade add-on build is identified by being UNSIGNED, not by its filename](/formats/reshade-addon-build) - the Authenticode test that tells the two builds apart
- [Two shader packs by one author ship the same headers, and the copies differ](/formats/stacked-shader-packs) - flattening them produces compile errors that move around between launches
- [The character-document formats, and what each one is structurally good at](/formats/character-document-formats) - seven shapes a backstory can take, and how each one characteristically fails
- [all format articles](/formats/index)

## Authoring

How the scripting and data layers behave when you are the one writing into them.

- [Never guess a TweakDB record ID - the game writes the real list](/authoring/finding-the-real-record-id) - a plausible guess is usually wrong, and always silent
- [A TweakXL record is resolved last-wins, and that is the lever for everything else](/authoring/tweakxl-records-are-last-wins) - resolution is per record, so a late-sorting folder wins without touching anyone's files
- [One indentation error disables every record in a TweakXL file](/authoring/a-yaml-error-disables-the-whole-file) - the symptom is a mod that is installed, enabled and does nothing at all
- [Vendor stock and item pricing are both arrays of records, not values](/authoring/vendor-stock-and-pricing) - several price components exist and are read by nothing
- [The game ships its own API reference, and guessing a signature is slower than reading it](/authoring/reading-the-shipped-script-dump) - it also tells you whether a class can be hooked at all
- [Addressing one specific world object from redscript](/authoring/addressing-a-world-object-from-redscript) - `EntityID.GetHash` eventually matches the wrong object; go through the full 64-bit `PersistentID`
- [Deleting a world node with ArchiveXL - the type must come from the sector](/authoring/archivexl-node-deletions) - a `debugName` lies about `$type`, and one wrong entry reverts every deletion in the file
- [Detecting a player action by matching its interaction text is matching on something another mod owns](/authoring/detecting-a-player-action-from-an-interaction) - the LocKey moves, and quest-scripted sequences never fire it
- [Finding a piece of text the player saw in game](/authoring/finding-in-game-text) - one per-locale JSON, extracted from that language's archive, containing no spoken dialogue
- [What the CET console can and cannot do](/authoring/the-cet-console-is-a-sandbox) - widely-posted cheats that are not CET globals, and a quest fact that dies at the next load
- [all authoring articles](/authoring/index)

## Conflicts, load order and archive internals

Why one archive beats another, how to tell a mod that is losing from a mod that
was never in the fight, and what is actually inside an `.archive`.

- [Earlier in modlist.txt wins, and nothing in the game writes that file](/conflicts/earlier-wins-and-nothing-in-the-game-writes-the-list) - and only some installs have a `modlist.txt` at all
- [Every newly installed archive starts at the bottom of the priority stack](/conflicts/every-new-archive-starts-last) - so any hand-settled order quietly undoes itself
- [An archive can be installed, enabled, and contributing nothing](/conflicts/an-archive-that-contributes-nothing) - detectable from the indexes alone, and an inert archive never means an inert mod
- [A modlist entry with no archive is usually not a fault; an archive with no entry always is](/conflicts/an-entry-and-a-file-can-disagree) - the two halves of a mismatch have opposite meanings
- [modlist.txt has no comment syntax, and treating "#" as one fabricates faults](/conflicts/modlist-has-no-comment-syntax) - 60 invented faults on one install where the true count was zero
- [Making one mod win can kill a third mod nobody mentioned](/conflicts/a-precedence-change-creates-casualties) - precedence is zero-sum, so diff the inert list after any ordering change
- [Three conflicts look identical in a report and only one is fixable by order](/conflicts/what-reordering-can-and-cannot-fix) - a coverage gap and an unsatisfiable claim are not lost fights
- [Not every visual mismatch is a conflict, and the scanner agreeing with you is not evidence](/conflicts/visual-bugs-that-are-not-conflicts) - appearance overrides repoint a body part with no hash collision at all
- [An .archive index is plain structured data - only the file bodies are compressed](/conflicts/rdar-index-is-plain-data) - RDAR headers need no WolvenKit, and two numeric traps break a naive FNV1a-64
- [A hash you cannot name is still a conflict, and a miss is information](/conflicts/resolving-a-hash-to-a-path) - an unknown hash is usually a mod's own resource rather than a lookup failure
- [A serialized RED4 file survives a targeted regex, not a JSON round-trip](/conflicts/editing-serialized-red4-json) - values usually appear twice, so a single-occurrence edit is normally a bug
- [Scaling a placed prop is four separate edits, and the anchors do not follow the mesh](/conflicts/scaling-a-placed-prop) - `visualScale` moves the mesh and nothing else
- [all conflict articles](/conflicts/index)

## Installs and mod managers

What each way of assembling an install makes untrue about the files on disk.

- [What the game directory shows you depends entirely on how the mods got there](/install/how-the-install-is-assembled) - one mode shows an almost empty game folder, and one deletes every mod you add
- [Fixing a bug in someone else's mod](/install/overriding-another-authors-mod) - override or patch in place, and why the override's danger is silence rather than breakage
- [Two downloads from one mod page may not be alternatives](/install/two-builds-of-one-filename) - when two builds share a filename, byte size is the only thing identifying which is deployed
- [all install articles](/install/index)

## Input and bindings

What decides which key does what on a modded install, and why every simple
version of that question has a wrong answer that looks right.

- [Five separate stores hold key bindings, and no single one answers what a key is bound to](/input/five-binding-stores) - they disagree on format, and a binding you cannot find is not a key that is free
- [A binding store can lose its contents, and an empty store looks exactly like the wrong store](/input/a-binding-store-can-empty-itself) - the bound-to-total ratio is the cheap health signal
- [One key has four spellings, and comparing any two of them directly finds nothing](/input/one-key-four-spellings) - a raw string comparison reads as "unbound", so a key-availability gate reports taken keys as free
- [A binding can be stored as a packed integer instead of a key name](/input/packed-key-codes) - four virtual-key codes in 16-bit slots, and a chord holding VK 255 never matches a keypress again
- [An input context is not a category, and a shared key is usually not a fault](/input/input-contexts-are-not-categories) - bindings scope to a context, so one key legitimately carries several meanings
- [A mod can change what a vanilla key does without registering a key of its own](/input/a-mod-can-repurpose-a-vanilla-mapping) - hiding base-game rows to cut noise hides exactly the rows the user came for
- [A programmable mouse is a layer over the binding stores, not another store](/input/a-peripheral-profile-is-a-layer) - the device only emits a keystroke; the useful output is a three-way join
- [all input articles](/input/index)

## Diagnosis

Finding out what is actually wrong with an install, and what evidence each kind
of failure leaves behind.

- [Which log carries which symptom, and why a missing log is not a silent log](/diagnosis/which-log-carries-which-symptom) - seven logs, none of them shipped with the game
- [The game writes its own crash report, and Windows Error Reporting never sees it](/diagnosis/the-games-own-crash-report) - it catches its own fault and exits cleanly, so there is no event and no dump
- [A hang and a crash are different faults, and only one of them lets you interrogate the process](/diagnosis/a-hang-and-a-crash-are-different-faults) - killing the game destroys everything the hang was offering
- [Memory is usually a red herring, and measuring it badly manufactures the leak you went looking for](/diagnosis/memory-is-usually-a-red-herring) - the startup ramp turns two samples into a confident, invented growth figure
- [A failing round narrows nothing, and a clean round proves everything](/diagnosis/a-failing-round-narrows-nothing) - naive halving assumes one culprit and clears innocent and guilty alike
- [Sizing a bisect to the list, and the parking mechanics that decide whether a round tested what you think](/diagnosis/sizing-a-bisect-to-the-list) - under about twenty mods, just looking is faster than halving
- [When halving stops paying, write a guard](/diagnosis/writing-a-guard-mod) - bisection answers which mod, never what it is doing; the guard goes in CET, not redscript
- [all diagnosis articles](/diagnosis/index)

## Process

Not facts about the game - the ways work *about* the game goes wrong, and what
to do instead.

- [Documenting a large mod list without producing a report nobody can trust](/process/running-a-documentation-pass) - partition by filename ownership, and the four ways a confident article turns out to be wrong
- [A capacity read from the wrong API comes back plausible, and nothing about it looks wrong](/process/a-capacity-read-from-the-wrong-api) - saturation and enumeration, and a wrong number that propagates silently
- [all process articles](/process/index)

## What stayed in the skills

The skill files kept what is genuinely procedure: the compile-test invocation,
where this family stores its records, the PowerShell traps in its own tooling,
and the helper contract of one mod's script runner. None of that is waiting to
be migrated - it is either instruction rather than knowledge, or it is a fact
about this family rather than about Cyberpunk, and a shipping game wiki is the
wrong home for it. Anything specific to a mod on one install - its settings, its
paths, what its author wrote - lives in the user bundle by design.

## Log

- [log.md](/log) - what changed here and why
