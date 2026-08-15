# ReShade and virtual photography stacks

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> **Re-check after a patch:** Not bound to the game patch - this tracks ReShade and add-on releases instead. Re-check the add-on build signature test and the REST incompatibility against current versions.

Whatever the install layout, ReShade's DLL and its `reshade-shaders\` tree live in
`bin\x64` alongside the game executable.

This file is about **stacks** - ReShade plus add-ons plus several shader packs, the
kind of setup virtual photographers build. A plain ReShade install with one shader
pack hits almost none of it, so establish what the user is actually running before
applying any of it.

## If the stack uses add-ons, the add-on build is mandatory - identify it by signature

Anything shipping a `.addon64` binary requires the **add-on** build of ReShade, not
the standard one. Camera/connector add-ons and several of Marty's tools are the
common cases, but the rule is the file extension, not the name: if there is a
`.addon64` in the ReShade folder, the standard build will ignore it and the feature
will simply never appear.

The two builds are hard to tell apart from the filename. The reliable test:

> **The add-on build is UNSIGNED.** Run `Get-AuthenticodeSignature` against the
> ReShade DLL - typically `dxgi.dll`, but it may have been installed under another
> API name such as `d3d11.dll`. `NotSigned` means you have the correct build. The
> *signed* one is the restricted version that refuses to load add-ons.

## Shader packs from the same author collide, so keep them in separate subfolders

Two packs by one author frequently ship their own copies of the same shared headers
- and **the copies differ**, including when the file dates match. One observed case:
iMMERSE and METEOR each carry ~15 `mmx_*.fxh` files under a `MartysMods\` folder,
all of them different between the two packs.

`EffectSearchPaths` is recursive, so flattening the packs into one folder makes an
include like `#include "MartysMods/mmx_global.fxh"` resolve unpredictably -
producing shader compile errors that appear random and move around between launches.

ReShade resolves includes relative to the including file first, so the fix is to
give each pack its own subfolder with its headers adjacent to its own `.fx`. Any
layout with that property works - one that does, for the packs above:

```
reshade-shaders\Shaders\iMMERSE\  + iMMERSE\MartysMods\
reshade-shaders\Shaders\METEOR\   + METEOR\MartysMods\
reshade-shaders\Shaders\<every other pack, one folder each>\
```

## Sourcing gotchas

- **A shader can ship with its add-on rather than with a shader pack.** `IgcsDof.fx`
  is the example that catches people: it is in the IgcsConnector *release zip*, not
  in OtisFX and not in the IgcsConnector source repo. If a `.fx` is missing, check
  the release archive of whatever add-on needs it before concluding the pack is
  broken.
- **The ReShade installer's package index lags GitHub.** It has shipped a stale
  list missing current shaders while still offering ones that had been dropped. Pull
  packs from the author's GitHub directly rather than trusting the installer list.
- **A paid or "ultimate" edition of a pack is usually a superset of its free
  edition**, not a companion to it - iMMERSE is the common case. Install one or the
  other, never both, or you get the header collision above with extra steps.

## Known incompatibility worth remembering

**ReshadeEffectShaderToggler (REST) v1.3.23 against ReShade 6.8**: the game reaches
rendering normally, then dies roughly 50 seconds in, **with no error in any log**.
That is one observed version pair, not a permanent verdict on REST - but the *shape*
is worth remembering, because a REST/ReShade version mismatch is worth suspecting
whenever a modded install dies shortly after gameplay starts and every game-side log
is clean. REST only provides HUD and menu masking, so if it is present, pulling it
is a cheap test that rarely breaks anything else.

## Ordering and behaviour

- **A pack's shared prepass must sort first in the preset.** In iMMERSE-based
  presets that is Launchpad, which MXAO, RTGI and SOLARIS all read from - so it has
  to run before them. Check whether whatever pack is installed has an equivalent
  before assuming effect order is free.
- **Not every DOF effect uses the depth buffer, so depth-buffer troubleshooting does
  not apply to all of them.** IgcsDOF is the counterexample: it accumulates frames
  while a free-camera tool physically walks the camera through an aperture pattern,
  so no depth-buffer setting can affect it. Depth-dependent effects (MXAO,
  CinematicDOF and the like) are the ones worth pointing depth troubleshooting at.
