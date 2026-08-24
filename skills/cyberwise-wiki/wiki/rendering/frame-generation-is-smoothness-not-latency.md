---
type: Engine Mechanic
title: Frame generation is display smoothness, never input latency - and latency rises with the multiplier
description: Responsiveness is tied to the base rendered frame rate, generation adds overhead on top, and in frozen time there is nothing to interpolate - so it contributes nothing to precise camera work while its artifacts show up in stills.
tags: [frame-generation, latency, performance, artifacts, photography]
status: stable
generated: { by: "claude", at: "2026-08-24T22:10:00-04:00" }
---

# Frame generation is display smoothness, never input latency - and latency rises with the multiplier

Frame generation is routinely recommended as a fix for a game that "feels
sluggish". It is the wrong tool, and it makes that specific complaint worse.

**Responsiveness is tied to the base rendered frame rate.** Generated frames
carry no new input sampling - they are interpolated from frames the engine
already produced. Generation also costs work on top of rendering, so:

> **Latency *rises* with higher generation multipliers.** More generated frames
> means a smoother-looking image and a slightly less responsive one, not the
> reverse.

What it genuinely buys is display smoothness. That is a real benefit and it is
the only one; judge it on motion, never on feel.

## In frozen time it contributes nothing

For photography and precise camera work the argument collapses entirely.

- **Frozen time means no motion to interpolate.** There is nothing between two
  identical frames to generate, so there is no smoothness benefit to have.
- **Its artifacts are worst on fine repeating geometry** - railings, grilles,
  mesh, distant window grids, chain-link. Exactly the content a still image
  invites someone to look at closely, and exactly where an interpolation error
  is visible when it would have been invisible in motion.

So the trade in a still is all cost: no benefit available, artifacts still
present. Turn it off before composing, and turn it back on for play if you like
what it does there.

## Related

- [Photo mode is a separate rendering context](/rendering/composing-in-the-gameplay-renderer) - the freeze-time workflow this applies to
- [Sharpening recovers detail, it never invents it](/rendering/sharpening-recovers-detail-it-never-invents-it) - the other effect whose strength depends on upstream reconstruction
