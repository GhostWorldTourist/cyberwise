# ReShade and virtual photography stacks

> **Verified:** Cyberpunk 2077 patch 2.31 - August 2026
> **Re-check after a patch:** Not bound to the game patch - this tracks ReShade and add-on releases instead. Re-check the add-on build signature test and the REST incompatibility against current versions.

Everything lives in `bin\x64` alongside the game executable.

## The add-on build is mandatory, and you identify it by signature

Any stack using `.addon64` binaries - IgcsConnector, CyberLit, Marty's LUTManager /
ParallaxDOF / ReGradePlus / ReLight - requires the **add-on** build of ReShade, not
the standard one.

The two builds are hard to tell apart from the filename. The reliable test:

> **The add-on build is UNSIGNED.** `Get-AuthenticodeSignature` on `dxgi.dll`
> returning `NotSigned` means you have the correct build. The *signed* one is the
> restricted version that refuses to load add-ons.

## Shader packs must stay in separate subfolders

iMMERSE and METEOR each ship their own copy of the same ~15 `mmx_*.fxh` headers,
and **all of them differ between packs**, including at matching file dates.

`EffectSearchPaths` is recursive, so flattening the packs into one folder makes
`#include "MartysMods/mmx_global.fxh"` resolve unpredictably - producing shader
compile errors that appear random and move around between launches.

ReShade resolves includes relative to the including file first, so the fix is to
keep each pack's headers adjacent to its own `.fx`:

```
reshade-shaders\Shaders\iMMERSE\  + iMMERSE\MartysMods\
reshade-shaders\Shaders\METEOR\   + METEOR\MartysMods\
reshade-shaders\Shaders\OtisFX\
reshade-shaders\Shaders\Stock\
```

## Sourcing gotchas

- **`IgcsDof.fx` ships in the IgcsConnector release zip** - not in OtisFX, and not
  in the IgcsConnector source repo.
- **The ReShade installer's package index lags GitHub.** It has shipped a stale
  list missing current shaders and still offering ones that had been dropped. Pull
  Marty's packs from GitHub directly.
- iMMERSE Ultimate is a strict superset of free iMMERSE. Install one or the other,
  never both.

## Known incompatibility worth remembering

**ReshadeEffectShaderToggler (REST) v1.3.23 against ReShade 6.8**: the game reaches
rendering normally, then dies roughly 50 seconds in, **with no error in any log**.
This is worth suspecting whenever a modded install crashes shortly after gameplay
starts and every game-side log is clean. Nothing else in a typical stack depends on
REST; it only provides HUD and menu masking.

## Ordering and behaviour

- **Launchpad must sort first** in any preset - it is the shared prepass that MXAO,
  RTGI and SOLARIS all read from.
- **IgcsDOF does not use the depth buffer.** It accumulates frames while the camera
  tool physically walks the camera through an aperture pattern. Depth-buffer
  settings cannot affect it. MXAO and CinematicDOF are the depth-dependent effects,
  so depth-buffer troubleshooting applies to those and not to IgcsDOF.
