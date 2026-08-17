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

## Do the round FOR them, and launch the game yourself

The person testing has exactly one job that cannot be automated: looking at the
screen and saying what happened. Everything either side of that is chores, and
handing those back is what makes a twenty-round bisect feel like a punishment.

**Arm the round yourself.** Moving a hundred files is a script; a hundred
checkboxes in a mod manager is twenty minutes and a transcription error. Use
`tools/Invoke-BisectRound.ps1`, which parks a named set, records exactly what it
parked, and hands back a one-line undo.

**Then launch the game yourself.** This is the single biggest quality-of-life
change to a long bisect, learned from a twenty-round one in another game: the
tester glances over, sees the game is up, and knows it is time to try the thing.
No instruction to read, no waiting to be told the round is ready, no "have you
started it yet" round-trip.

```powershell
tools\Invoke-BisectRound.ps1 -GameRoot '<path>' -Round C -Park cut3.txt -Launch
```

**Launch it the way they play it**, not by running the exe. A storefront launch
applies their configured launch options - one install here carries
`--launcher-skip -skipStartScreen` - and bypassing those tests a configuration
they never play. `launcher-configuration.json` in the game root names the
platform; the tool reads it rather than guessing from the path.

Two things not to automate past:

- **The verdict is theirs.** A watcher cannot tell a livelock from a loaded game
  sitting at a menu (below). Getting them to the screen faster is the win; the
  screen is still the instrument.
- **A round that parks 37 of 38 is not the round in the manifest.** Refuse a
  partial set outright. An unresolvable name silently parks nothing, which scores
  as "the fault went away" and sends the whole search down the wrong branch.

**Write every round down.** Which configuration was that, exactly? is the
question that ruins long bisects, and it always gets asked three rounds later.
The tool writes a manifest per round beside the game's own data, so a different
agent - or the user alone - can pick the bisect up cold.

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

Park files by hand when there is no manager, when you need finer granularity than
the manager offers - half of one mod's archives, say - or **when the round has to
be armed in seconds rather than minutes.** On a long bisect that last one wins
most of the time: parking is scriptable and recordable, and a manager's UI is
neither.

**Under a hardlink-deploying manager, parking is cheaper than it looks.** Every
file in the game tree is a second name for the staging inode, so moving the
game-side name hides the mod and loses nothing - the staging copy is the same
data, still there, still the manager's. Restoring is a rename back.

**Move, never copy.** A copy makes a new inode, and the file the game then loads
is no longer linked to staging: the manager's next deployment sees a file it did
not place, and any later update to that mod silently stops reaching the game.
`Move-Item`, always.

The cost of choosing parking is that the manager's picture is now stale, so:

- **Treat a deployment during a bisect as voiding the round.** If the manager
  redeploys mid-run it can restore a parked file underneath you, and the
  configuration you tested is not the one you recorded. Re-arm rather than
  reasoning about what it might have put back.
- **Restore from the manifest, not from memory**, and report loudly if a file is
  not where the manifest says it was parked - something else moved it, and every
  round since is suspect.

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
3. **Then search within the guilty layer - but read the next section before you
   assume halving is the search.**

## A failing round narrows nothing

This corrects advice this file used to give, and the correction matters more than
anything else on this page. It comes from `sulskill`, the same-shaped skill family
for another game, where the assumption below cost about a dozen launches before
anyone noticed it was an assumption.

**Disable half, launch, keep the half that still fails** is wrong, and wrong in
the way that looks like progress. It assumes **exactly one culprit**. Two mods
that each break the same thing on their own make every half fail, because the
other cause is still enabled - so each round "clears" innocent and guilty alike
and the search narrows into a region that never held the whole answer. Nothing
errors. The rounds keep halving. The report looks like a bisect.

The asymmetry is the whole method:

| round | what it proves |
|---|---|
| **clean** | every cause is inside the set you disabled |
| **failing** | only that at least one cause is still enabled |

So while you are still halving, a failing round is not evidence about any
individual mod in it.

**Once any round comes back clean, invert.** You now have a proven base: hold it
disabled and add mods *back* in groups. From then on both outcomes are
informative, because the complement is already known clean. Add-back is slower per
round and finishes sooner.

**A mod is named as a cause only by adding it back, alone, to a proven-clean base
and watching it fail.** Never by elimination. An answer reached by elimination is
the same claim as "everything else was innocent", which no failing round supports.

This is also why the validation rule below is not optional bookkeeping: restoring
everything and withholding only the suspect is the add-back test, run once more
against the full order.

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

## When halving stops paying: write a guard

Bisection answers *which mod*. It does not answer *what that mod is doing*, and
sometimes the interesting question is the second one - the suspect is confirmed,
but the state that makes it fail happens inside a function nothing logs.

A **guard** is a throwaway mod whose only job is to watch one place and write
down what it sees. Not a fix. One function, one log line, deleted afterwards.

This came from another game's twenty-round bisect, where a guard wrapped the one
call that was failing, skipped the operation when its precondition was empty, and
appended a line naming the value and its size. The log line
`wanted states[0] but has 0 state(s)` settled a root cause that four rounds of
halving had only circled - because the number nobody could see was the whole
answer.

**Design rules, in the order they matter:**

- **Log the value that separates your hypotheses**, not "reached here". If two
  explanations predict different numbers, print the number. A guard that only
  proves the code ran has told you what the crash already told you.
- **Say in the mod itself that it is containment, not a fix.** If it skips the
  failing operation to keep the game up, the README says so in as many words.
  Guards get forgotten and then get blamed for behaviour six months later.
- **Expect to ship it twice.** The first log line is usually not quite the right
  one; version it, refine what it prints, re-deploy. That is normal, not failure.
- **Register it** with `cyberwise/tools/ModPatchWatch.ps1` and delete it when the
  investigation ends. An unregistered guard is an invisible mod that survives
  every future update.

**Two Cyberpunk-specific constraints decide how you build one:**

- **Prefer CET over redscript for a guard.** redscript is an all-or-nothing gate:
  a guard that fails to compile silently disables *every* `.reds` mod on the
  install, which is a spectacular way to make a bisect worse. A broken CET mod
  fails alone, and CET writes a per-mod log at
  `bin\x64\plugins\cyber_engine_tweaks\mods\<name>\<name>.log` with no extra
  plumbing (`cyberwise-tweaks/references/cet-lua.md`).
- **You cannot wrap another mod's own classes.** `@wrapMethod` / `@replaceMethod`
  work on classes the *game* declares, not on ones another mod declares, so a
  guard usually has to sit on the game-side function the suspect calls into
  rather than on the suspect itself. Establish which is which before promising
  anybody a guard.

## Reporting

Say plainly which configuration was tested, what the outcome was, and what remains
untested. When an earlier answer is disproved, say it is disproved - a list of
superseded theories is genuinely useful, because the next person will otherwise
propose them again.
