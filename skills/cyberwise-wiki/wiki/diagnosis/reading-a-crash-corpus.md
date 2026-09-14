---
type: Diagnosis
title: A pile of crash reports is a dataset, and it needs a denominator
description: How to read many crashes at once - deduplicating on crashVisitId, why district and quest counts are meaningless without a base rate, comparing crashed against clean sessions at matched uptime, and the bimodality that hides two faults inside one bug report.
tags: [diagnosis, crashes, telemetry, statistics, method]
status: stable
generated: { by: "claude", at: "2026-09-14T02:30:00-04:00" }
---

# A pile of crash reports is a dataset, and it needs a denominator

One crash is an anecdote and gets diagnosed by reading logs. Thirty crashes is a
**dataset**, and reading it the same way produces confident nonsense - every
pattern in it is real, and almost none of them mean anything, because nothing
has been compared against how often that thing happens anyway.

Everything below was derived on one install: 31 unique crashes across 166
recorded sessions, 2026-08-06 to 2026-09-14. The numbers are that install's. The
mistakes are everyone's.

## Deduplicate first, on `crashVisitId`

`CrashInfo.json` is **overwritten per crash and never deleted**, so any watcher
that copies it on exit re-saves the same record after every clean quit. Counting
files instead of crashes inflates the corpus and fabricates clusters.

```python
vid = pm["crashVisitId"]       # dedupe key. Everything else repeats.
```

On the reference corpus this was mild - 33 files, 31 unique - but the same
mechanism once turned 2 real crashes into 21 files. Deduplicate before you count
anything, including before you say how many crashes there have been.

**Watch for zero-byte captures.** The game writes its post-mortem and exits
immediately; a watcher reading the instant the process disappears can land
between create and flush. Two 0-byte files in this corpus were saved as crashes
and contained nothing. A capture path must refuse an empty read rather than file
it - see the retry loop in `Watch-Crashes.ps1`.

## District and quest counts are meaningless on their own

The most tempting table in any crash corpus:

```
  8  LittleChina        15  (none)
  7  Kabuki              8  q001_lockdown
  3  CorpoPlaza          4  q000_corpo
```

This says nothing. It is a map of **where the player spends time**, not where the
game breaks. Four crashes in `q000_corpo` at Z≈144 look like a cluster until you
notice the prologue keeps you inside Arasaka Tower for those objectives, so the
base rate of being at that height during that quest is essentially 100%.

**A location is evidence only against a base rate.** Without one, the honest
statements are narrow:

- a crash *outside* the district where the player spends most of their time
- the same coordinates across *different* quests or playthroughs
- a district that appears far more than its share of played hours

Nothing else. `/process/proximity-is-not-evidence-without-a-base-rate` is the
general form; this is what it looks like with a table in front of you.

## Compare crashed against clean sessions AT MATCHED UPTIME

The question people actually want answered is "do crashed sessions look
different?", and the naive comparison always says yes for a reason that has
nothing to do with the fault.

**A session that dies at 20 minutes is all growth phase. One that runs 90
minutes spends most of its samples on a plateau.** Comparing peaks or slopes
across the two therefore compares *durations*, not health. On this corpus the
uncontrolled slope difference was 10x - and it was an artifact.

The fix is to truncate every trace to a common window and only include sessions
that actually reached it, so both groups survived equally long:

```python
def at(session, minute, metric):
    v = [r[metric] for r in session.rows if r.up <= minute]
    return v[-1] if v else None

crashed = [s for s in all if s.crashed     and s.dur >= T]
clean   = [s for s in all if not s.crashed and s.dur >= T]
```

Done that way on the reference corpus, a real and stable difference appears at
every window from 5 to 30 minutes:

| at t=20 min | crashed (n=11) | clean (n=36) | diff |
|---|---|---|---|
| adapter GPU GB | 24.46 | 21.64 | **+2.82** |
| game GPU GB | 16.67 | 15.53 | +1.15 |
| private GB | 26.85 | 25.37 | +1.48 |
| handles | 3298 | 3305 | -7 |

Crashed sessions sit **~2.5 GB higher on adapter GPU at the same uptime**, every
window, consistently. Handles are flat, which rules out a handle leak outright.

**That is a correlate, not a cause**, and the difference between those is the
whole discipline. Higher GPU at matched uptime is equally consistent with
"memory pressure kills it" and with "this session loaded heavier content, and
whatever actually breaks is more likely in heavy content".

## A ceiling has a shape, and this is not it

If a hard VRAM limit mattered, the crash rate would climb as sessions approach
it. Bucket by peak and compare against the baseline rate:

```
  peaking >= 26 GB adapter:  24 sessions, 50% crashed
  peaking >= 28 GB adapter:   6 sessions, 17% crashed
  peaking >= 29 GB adapter:   3 sessions,  0% crashed
  baseline across all sessions:           17%
```

The rate is elevated in the middle band and **falls to baseline nearest the
card's 32 GB**. That is not a ceiling effect; a ceiling is monotone. (The top
buckets are n=6 and n=3, so they are weak on their own - but they are certainly
not evidence *for* a ceiling.)

## Look for bimodality before assuming one bug

Session length at crash, sorted, is the cheapest test for "am I chasing two
faults at once":

```
  under 2 min :  6 crashes   median peak game GPU   8.15 GB
  2 - 30 min  : 13 crashes   median peak game GPU  16.24 GB
  over 30 min :  9 crashes   median peak game GPU  19.15 GB
```

Three populations, and the short one is not a small version of the long one - it
dies at **half the memory footprint**, before the load ramp finishes. A startup
crash and an hour-in crash are different faults wearing the same bug report, and
averaging them produces a description of neither.

Split the corpus on this before any other analysis.

## Rate needs a denominator too

"It crashed six times this week" is unreadable without knowing how much was
played. Count crashes against **sessions** and against **hours**:

| period | sessions | crashes | rate | hours | MTBF |
|---|---|---|---|---|---|
| before a large mod update | 146 | 22 | 15% | 67.8 | 185 min |
| after | 20 | 6 | 30% | 6.7 | 67 min |

Then test it rather than believing it. An exact one-tailed binomial against the
prior rate gives **p = 0.069** - suggestive, not conclusive, and one quiet
evening would move it a long way. Say that, rather than "the update doubled the
crash rate", which the data does not support at n=20.

## Scope

Method, not game facts; nothing here depends on a patch. The worked numbers are
one install's and are included because a method with no worked example is
advice. Re-derive them per install - the shapes are what transfer.
