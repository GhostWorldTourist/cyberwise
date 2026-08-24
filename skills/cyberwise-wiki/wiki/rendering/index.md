# Rendering, post-processing and capture

What happens to a frame between the scene render and the file you hand somebody,
and which stage a given problem actually belongs to. Nothing here is about a
particular install: it is how the engine, an injected shader chain and the
capture path behave. Tools and shader families are named only as examples that
make a mechanism concrete.

**Start with stage order.** Most arguments in this area - fix it in game or in
ReShade, why the bloom setting did nothing, why a calibration stopped being valid
- are settled by knowing where in the chain each thing sits.

## The pipeline

- [ReShade sees the frame after the game has finished with it](/rendering/stage-order-decides-where-a-fix-belongs) - the controllable stages in order, why a shader can never see pre-tonemap values, and why exposure gets fixed at the earliest controllable stage
- [Bloom has no toggle in the game's options](/rendering/bloom-has-no-toggle-in-the-options) - the `[Developer/FeatureToggles]` `user.ini`, and the five-step checklist for a toggle that appears to do nothing
- [The display is the last stage, and its "enhancements" fight the art direction](/rendering/the-display-is-the-last-stage) - black equalizers, range compression, dynamic tone mapping, and OSD labels that lie about their own direction

## HDR

- [An HDR retrofit layer changes what every later shader sees](/rendering/an-hdr-retrofit-layer-changes-what-shaders-see) - a 40:1 scene arriving at the shaders as 1.35:1, and bloom that lifts the whole frame with no traceable source
- [HDR and SDR are two different calibrations](/rendering/hdr-and-sdr-are-two-different-calibrations) - the log2 whitepoint that makes a bloom shader look insane, and the luminance number Windows shows once and never again

## Capture and delivery

- [The capture path can silently ruin a finished shot](/rendering/capture-formats-and-what-they-clip) - 16-bit PNGs that blew out highlights, JPEG XR from Game Bar and OBS, and the tooling gaps that reproduce the fault
- [HDR screenshot metadata is a negotiated compromise, and SDR is the honest delivery format](/rendering/hdr-delivery-is-a-negotiation) - one hot pixel can dim a whole image, and every consumer re-tone-maps anyway

## Composing a shot

- [Photo mode is a separate rendering context](/rendering/composing-in-the-gameplay-renderer) - ray reconstruction is broken inside it; freeze time and fly a detached camera instead
- [Frame generation is display smoothness, never input latency](/rendering/frame-generation-is-smoothness-not-latency) - latency rises with the multiplier, and in frozen time there is nothing to interpolate
- [Judging a visual change](/rendering/judging-a-visual-change) - toggle layers in place rather than comparing side by side, and the four scenes a grade has to survive

## Effects, and how they interact

- [Ordering the effect chain](/rendering/ordering-the-effect-chain) - infrastructure first, meters last, corrective sharpener before aesthetic, and what path tracing makes redundant
- [Sharpening recovers detail, it never invents it](/rendering/sharpening-recovers-detail-it-never-invents-it) - why a contrast-adaptive sharpener does not halo, and why SDR tolerates far more of it than HDR
- [One grain pass, and one grain model](/rendering/one-grain-pass-and-one-grain-model) - three layers can each add grain, and the halide-crystal and sensor-noise models mean different things by the same control
- [Telling bloom from what is not bloom](/rendering/telling-bloom-from-what-is-not-bloom) - reflections and lens flare get reported as bloom, and bloom itself is a per-shot decision

## What is marked draft, and why

Five articles here carry `status: draft` because their central finding is a
**single observation** rather than a repeated test - one machine, one session,
one version of a tool. Each says so in its own "What was not verified" section:
the HDR retrofit layer, the HDR/SDR calibration article, the capture formats,
photo mode's broken ray reconstruction, and the display-side features.

The mechanisms in those articles generalise. The measurements in them do not, and
should be re-derived rather than copied.
