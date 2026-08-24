# Log

## 2026-08-24

**Three patterns added, all earned from a live diagnosis rather than from
reading.** A drop point that would buy nothing turned out to be a single
`ALLOW NOTHING` flag that bypasses a mod's entire filter chain - no error, no
log line, and the settings that looked like the fix were the exact ones the flag
ignores. Two other mods hooked the same sell path and looked guilty; both were
purely additive. That produced
[override-flag-silences-the-filter-chain](/patterns/override-flag-silences-the-filter-chain),
including the habit of naming what was ruled out.

Establishing whether the flag was a shipped default or a user choice exposed a
wider hole: `user.ini` is only half the settings picture, because CET Lua mods
persist to their own JSON. An absent value there reads exactly like a default.
Written up as
[live-state-is-not-defaults](/patterns/live-state-is-not-defaults) - the rule is
to ask which store a mod writes to before asking what the value is.

The third came from a documentation pass over ~80 mods:
[shared-core-announces-its-addons](/patterns/shared-core-announces-its-addons).
A core dependency that reports its active slots at runtime beats every
file-presence proxy, because it reports what actually ran rather than what was
copied.

All three name mods only as examples. The per-mod detail - which flags this
install has set, what each add-on does - stayed in the user bundle, which does
not ship.


## 2026-08-23

**Creation** - bundle started. OKF 0.2.

Scope set deliberately narrow: this bundle ships, so it carries only game,
engine and format knowledge, plus cross-mod interaction *patterns* that are
really facts about the game's data model. Anything about a specific mod's
settings or behaviour belongs to the per-user bundle and never ships.

First articles are migrations of findings that were sitting in skill reference
files, where they were reference material wearing instructions' clothing.
