---
type: Diagnosis
title: A failing round narrows nothing, and a clean round proves everything
description: Disable half, launch, keep the half that still fails is wrong, and wrong in the way that looks like progress - it assumes exactly one culprit. Two mods that each break the same thing make every half fail, so each round clears innocent and guilty alike while the report still looks like a bisect.
tags: [bisect, method, evidence, load-order, diagnosis]
status: stable
generated: { by: "claude", at: "2026-08-24T21:10:00-04:00" }
---

# A failing round narrows nothing, and a clean round proves everything

This corrects the advice almost everybody starts with, and the correction matters
more than any other single thing about bisecting. It surfaced in a same-shaped
skill family for another game, where the assumption below cost about a dozen
launches before anyone noticed it *was* an assumption.

**"Disable half, launch, keep the half that still fails" is wrong.** It assumes
**exactly one culprit**.

Two mods that each break the same thing on their own make **every half fail**,
because whichever half you keep, one of the causes is still enabled. So each
round "clears" innocent and guilty alike, and the search narrows into a region
that never held the whole answer.

Nothing errors. The rounds keep halving. The report looks like a bisect.

## The asymmetry is the whole method

| round | what it proves |
|---|---|
| **clean** | every cause is inside the set you disabled |
| **failing** | only that at least one cause is still enabled |

A clean round is a statement about *all* causes. A failing round is a statement
about *no individual mod*. While you are still halving, a failing round is not
evidence about anything in it.

## Once any round comes back clean, invert

You now have a **proven-clean base**. Hold it disabled and add mods *back* in
groups. From then on both outcomes are informative, because the complement is
already known clean.

Add-back is slower per round and finishes sooner.

## The standard of proof for naming a cause

**A mod is named as a cause only by adding it back, alone, to a proven-clean base
and watching it fail.** Never by elimination.

An answer reached by elimination is the same claim as "everything else was
innocent", which no failing round supports. This is also why validating against
the full load order is not optional bookkeeping - restoring everything and
withholding only the suspect *is* the add-back test, run once more against the
real configuration.

The same standard applies to a suspect found by reading code rather than by
halving. A defect you can point at in a mod's source is a hypothesis with good
provenance, and it still has to survive the add-back test -
[memory is usually a red herring](/diagnosis/memory-is-usually-a-red-herring)
carries the case where a real leak was found in a mod's redscript and the crash
continued after that mod was fully undeployed.

## Related

- [Sizing a bisect to the list](/diagnosis/sizing-a-bisect-to-the-list) - when to bisect at all, and the parking mechanics that decide whether a round tested what you think
- [When halving stops paying, write a guard](/diagnosis/writing-a-guard-mod) - bisection answers *which mod*, never *what it is doing*
