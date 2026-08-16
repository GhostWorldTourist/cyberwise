# Bisecting a broken load order

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> **Re-check after a patch:** Method rather than data - largely patch-independent. The one thing to re-check is where files are staged on the install in front of you, if anything stages them, since the parking advice assumes same-volume moves.

Cyberpunk load times make bisection expensive. Getting the method wrong turns a
two-hour job into a two-day one. Everything here was learned during a bisect that
produced **six confidently wrong answers** before the real cause.

## Before you start

**Reproduce first.** A single crash or hang is not a deterministic fault. One
confirmation launch is cheap; a bisect over N items is log2(N) launches, and if the
fault is intermittent then *every clean round is noise that looks like information*
and quietly points at whatever happens to be tested last.

A real example of the cost: a crash at the intro triggered four bisect rounds over
six items. Every round came back clean, and restoring the exact original config
loaded fine too - six clean launches against one crash. Nothing was ever found
because there was nothing deterministic there.

"We don't know what that was, watch for it" is a legitimate outcome. Naming a
culprit by elimination when the underlying evidence is one unreproduced event is
not.

## Match the method to the size of the list

Bisection is what you reach for when the suspect set is too large to inspect. It is
not a ritual, and below a certain size it is *slower* than just looking. The costs
quoted throughout this file come from large installs; scale them down freely.

**At every size, the first question is "what changed", not "which half".** A fault
that appeared right after one install has a suspect list of one, and no amount of
halving beats reading the log and reverting that.

- **Under ~20 mods** - do not bisect at all. Read the logs (`diagnosis.md`), then
  disable the two or three most recent additions. A binary search here is ~5
  launches to find something you could have named in zero.
- **Dozens to low hundreds** - skip straight to the layer pass below. Four launches
  classify the fault by *kind* of mod, which on a list this size often names the
  culprit outright without any halving.
- **Many hundreds** - bisect properly and budget for it. Around 900 items is ~10
  launches for a clean binary search, and Cyberpunk's load time makes every wasted
  round expensive.

The rules - reproduce first, one variable per test, validate against the full load
order - hold at every size. Only the search strategy scales.

## Disabling versus parking

**If there is a mod manager, prefer its own enable/disable.** It is reversible, it
records what you did, and it will not desynchronise the manager's picture of the
install. Two manager-specific reasons this matters:

- **Vortex deploys by hardlink.** Moving a deployed file out of the game directory
  leaves the staging copy in place and the deployment out of date, so a later
  deployment can quietly restore it in the middle of a test.
- **MO2 virtualises.** With the game closed the archives may not physically be in
  `archive\pc\mod` at all, so there may be nothing to move - and moving whatever
  *is* there tests nothing. Disable in MO2's own UI. See `environment.md`.

Park files by hand when there is no manager, or when you need finer granularity
than the manager offers - half of one mod's archives, say.

## Where to park files

**Park inside the game folder** - e.g. `<game>\_bisect_parked\`.

- Same volume, so moves are instant rather than gigabyte copies.
- Nothing cleans it.

**Do not park in `%TEMP%`.** Temp sweepers run on their own schedule and will
delete your parked mods mid-procedure. In one session this cost 208 staged archives
and a full redeploy.

## Order of operations

1. **Get to a clean game first.** Turn everything off and launch. This confirms the
   fault is mod-related at all before you spend any launches narrowing it, and
   occasionally ends the investigation because it still happens. (Vortex calls this
   a purge; MO2 can disable at profile level; a manual install moves the folders
   aside.)
2. **Disable whole layers**, not individual files: `r6\scripts`, CET `mods`, all
   `*.xl`, all `*.archive`. Four launches tells you which *kind* of mod is at fault
   and halves the search space cheaply. Skip any layer the install does not have -
   an archives-only list has three of these to test, not four.
3. **Then binary search within the guilty layer.**

`.xl` files deserve early suspicion for anything that only manifests on a **new
game**. Quest-graph rewrites (`intercept: true` entries) only execute when the
quests run from scratch, so an existing save loads fine and the new game livelocks.
The culprit in one such case declared 33 quest parents and 30 intercepts - by far
the heaviest in the load order.

## Rules that are easy to break

**Never modify mod files while the game is running.** The results are
uninterpretable and you will not know which state you actually tested. Gate every
move on the process being closed. If a user says a test result was odd "given you
change files while it's running", that trust is already gone and every prior round
is suspect.

**Do not theorise during a bisect.** When someone is launching the game repeatedly
on your instructions, they need the next instruction, not a hypothesis. Narrate
findings afterwards.

**Validate the answer against the FULL load order.** Restore everything, withhold
only the suspect, and confirm the fault disappears. Answers validated against a
stripped-down configuration are worthless - several of the six wrong answers in
that session were "confirmed" that way and each fell over later.

## Automated hang detection does not work

A watcher that calls "stalled" on pinned CPU, flat memory and no log writes **cannot
distinguish a livelock from a loaded game sitting idle at a menu**. This produced
confident nonsense for three consecutive rounds before it was caught.

**The person looking at the screen is the only reliable oracle.** Do not try to
engineer them out of the loop, and do not treat watcher output as ground truth for
"did it hang".

Watchers are still useful for *measurement* - memory, handles, thread counts, and
recording the moment the process disappears. Just not for the verdict.

## Beware dependency chains

Disabling two mods together can produce a *new* failure because one depended on the
other. If a fault changes shape when you disable a group, split the group rather
than concluding you have found the cause.

Equally: a mod may be inert for reasons unrelated to your bisect (see
`environment.md` on redscript compilation). Confirm the mod you are testing is
actually running before drawing conclusions from disabling it.

## Reporting

Say plainly which configuration was tested, what the outcome was, and what remains
untested. When an earlier answer is disproved, say it is disproved - a list of
superseded theories is genuinely useful, because the next person will otherwise
propose them again.
