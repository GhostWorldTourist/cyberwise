# Log

## 2026-08-24

*(evening)*

**[a-capacity-read-from-the-wrong-api](/process/a-capacity-read-from-the-wrong-api),
written because the same machine produced two different wrong VRAM figures
within an hour and neither looked wrong.** `AdapterRAM` is a uint32 and
saturates at 4 GB, so every card above that answers "4 GB"; the registry QWORD
that fixes it is an enumeration, and index 0 was the integrated adapter, so the
careful second attempt answered "2 GB". One of those reached a crash diagnosis
before anyone cross-checked.

The article is in `/process` rather than `/engine` on purpose. The mechanism is
a Windows API detail and would date; the lesson is about how work goes wrong,
and it does not. A capacity read through an interface that cannot represent the
answer returns a **believable** number - right units, right order of magnitude,
no error and no null - and that is the whole problem: every other bad input
announces itself, and this one propagates into a report, then a diagnosis, then
advice about a machine nobody measured. The two tells are written down because
both are cheap: a value sitting on a power-of-two ceiling is saturation, and a
value matching a *different* device in the machine is a wrong index.

**The machine profile is now a generated artefact rather than a one-off.**
`New-SystemProfile.ps1 -Wiki` writes a `Machine Profile` article into the USER
bundle, so a fresh session reads what this hardware is instead of rediscovering
it - or worse, assuming it. It carries the VRAM warning above and a "what this
rules in and out" section derived from the actual numbers, because the useful
output is not "32 GB of VRAM", it is "VRAM exhaustion is not the first thing to
suspect here, and on weaker hardware that reverses". The tool refuses to write
it into this bundle: a machine profile is one person's hardware and never ships.

*(later the same day)*

**Process knowledge now lives here too, because a lesson that exists only in a
conversation is a lesson the next session has to learn again.** A documentation
pass over ~80 mods produced real method - how to partition writers, what to do
when two of them collide, how to tell a derived identifier from a fact - and
none of it was written anywhere a fresh start would look.
[running-a-documentation-pass](/process/running-a-documentation-pass) is that,
in a new `/process` area. The area exists because these are not facts about the
game; they are the ways work *about* the game goes wrong, and mixing them into
the engine notes would have hidden both.

The expensive one is the partition rule. Splitting agents by theme rather than
by explicit filename ownership put one mod into two briefs, and the writer that
finished second overwrote the first with no error and no record. Research was
lost and it was found by accident. That is why the rule is filename ownership
and why the repair is stated as additive - restoring the first version over the
second repeats the bug with the roles swapped.

**[defaults-can-be-written-by-code](/patterns/defaults-can-be-written-by-code)
is the one worth reading even if nothing else here is.** A mod seeds its own
settings during init, before the saved config loads, and persists them - so a
value in a live settings file can have been chosen by nobody. The first reading
of that case attributed the setting to the user, in a report, to a real person
who had never heard of the option, and it had to be retracted. The general rule
is stated plainly because getting it backwards misassigns responsibility in
whichever direction you got it wrong: *"who wrote this value" is a question
about code paths, not about file contents.* The article carries the mechanism -
the defaults table aliased to the live config, the apply pass that drops keys
absent from defaults, and the deduction that follows from those two (if user
settings survive a restart, something must be creating their keys before load).
It also carries the hazard on the other side: a mod with no settings-migration
code silently restores its seeded defaults on a version bump, so anything
recorded as "the user changed this" needs re-checking after that mod updates.

**And the reference migration.** `environment.md`, `script-cache.md` and
`cetmonkey.md` had grown into three of the largest files in the family, and
almost none of what made them large was instruction. A skill file is read to
decide what to do; a reference that explains how the compiled bundle is laid out
is being read to understand something. Those rot at different rates and belong
in different places, which is the whole argument for this bundle existing.

Eight articles came out of them, in two new areas. `/engine` holds what is true
of the game regardless of manager: the compiled script bundle and the three ways
to get a false absence from it, the log-rotation trap where every archived
redscript log is named for the run that *replaced* it, the CET Lua runtime
including the out-param return slot that moves between builds and the
`firstArray` idiom that survives the move, the two load-order domains that no
single list ranks, and the option registry that outranks any mod's label.
`/install` holds what is only true of a particular assembly - Vortex hardlinks,
MO2's virtual filesystem, Wabbajack deleting anything not tagged `[NoDelete]`,
and the override-versus-patch decision whose real danger is silence rather than
breakage.

The skill files keep pointers and the parts that genuinely are instructions -
the compile-test invocation, where this family stores its records, the
PowerShell traps in its own tooling. Nothing was deleted before its new home
existed.

Two judgements worth recording. The CET material is here as *engine* knowledge -
LuaJIT limits, how redscript out-params surface, what `uiData` and `resolves`
mean - while the specific helper contract of the script runner that hosts it
stayed in the skill, because that is one mod's interface and this bundle ships.
And the PowerShell traps stayed in the skill deliberately: they are true and
hard-won, but they are facts about this family's own tooling, not about
Cyberpunk, and a shipping game wiki is the wrong home for them.

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
