# Gameplay and stat mechanics

How the shipped game behaves - stats, cyberware, items, quick slots and scripted
sequences - established by reading the game's own scripts and data rather than a
wiki or a forum post. Mods appear here only as examples, and several of these
articles **contradict a widely-repeated claim**.

Two things unite them. Each was settled at the artefact: a real stat name, a real
enum member, the actual mapping. And most were believed wrongly first, so the
wrong road is written down beside the right one.

## Stats

- [Cyberware capacity is the "Humanity" stat family internally, and `HumanityTotal` does not exist](/gameplay/cyberware-capacity-is-the-humanity-stat) - `HumanityTotalMaxValue` / `HumanityAllocated` / `HumanityAvailable`, and a stat name that reports unavailable forever without erroring
- [Bleed has no resistance axis at all - only binary immunity](/gameplay/bleed-has-no-resistance-only-immunity) - graded resistance exists for three damage types, so bleed lands at full value while elemental damage decays against tougher enemies *(draft: which enemy records set the immunity flags was not checked)*

## Cyberware, items and slots

- [A base cyberware record does not necessarily yield the lowest tier](/gameplay/a-base-record-is-not-a-base-tier-item) - the base monowire record spawns a Tier 3 item; a record ID carries no tier information
- [Cyberware equip and unequip is ripperdoc-gated, and both console routes fail silently](/gameplay/cyberware-is-ripperdoc-gated) - an identifier existing is not the operation being permitted, and an attachment slot is not an equipment area
- [The monowire quickhack slot is a Relic-tree milestone, and Phantom Liberty only](/gameplay/the-monowire-quickhack-slot-is-a-relic-milestone) - found by reading the refund path, because the code that removes a thing enumerates what granted it *(draft: read from scripts, not walked in game)*
- [The vanilla consumable quick slot takes only health items](/gameplay/the-consumable-quick-slot-takes-only-health-items) - one mapping, no bind path for anything else, so "a hotkey for any consumable" is a real gap *(draft: a negative only as wide as the layers searched)*
- [Clothing after 2.0 - it can never be junk, carries no meaningful stats, and quality tier IS the scaling](/gameplay/clothing-and-quality-after-2-0) - which gives one clean test for whether a clothing mod's tiers mean anything

## Scenes and quests

- [A scripted sequence is on rails - teleporting during one crashes the game](/gameplay/a-scripted-sequence-is-on-rails) - vanilla, mod-free, and it happens where prologue debugging happens; the same sequence raises the scene tier and correctly gates features that then look broken

## Method

- [Checking a gameplay claim against the game's own scripts, not a forum](/gameplay/checking-a-gameplay-claim-against-the-shipped-scripts) - a circulating cheat naming a function the game does not have, and a console that is case-sensitive and silent on success
