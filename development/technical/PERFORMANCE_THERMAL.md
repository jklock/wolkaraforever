# Performance under thermal load

An evaluation of what this build actually does at 60 fps, what it costs per frame, and
what to change next for the most stable 60 fps when the iPad is hot. Written 2026-10-27
on Dadpad (iPad Pro 12.9-inch, 5th generation, M1, iPadOS 27.0.1), Developer service,
against the **released** client, World of Warcraft Forever 1.60.1.70634 (product `wowf`,
`_forever_`) — the baseline this page is written against.

> **Paths.** A bare `tools/<script>` means `wolkaraforever/tools/<script>` when the layer
> provides it, otherwise `platform/tools/<script>`. `translation/`, `runtime/` and
> `authorization/` live under `platform/`.

This page replaces no numbers from [PERFORMANCE_LANES.md](PERFORMANCE_LANES.md) — it adds
the release build, and it is the page to update as the thermal work proceeds.

## What was measured, and what was not

**Measured, on the device, today:**

- Frame pacing, GPU time and thermal state for five graphics configurations, 5-second
  windows, on the only scene this project can start without an account.
- A GPU-bound configuration driven to 23.6 fps, to see the shape of a frame that is
  actually over budget.
- The client's own dynamic resolution scaler, and the app's own render-profile control,
  side by side with hand-written CVars.

**Not measured, and why:**

- **The world.** The login screen is the only scene reachable without logging in, and no
  account could be used today. The in-world numbers quoted below are from
  [PERFORMANCE_LANES.md](PERFORMANCE_LANES.md) (2026-10-23, same device, beta build). The
  login screen is *not* a substitute: it is vsync-pinned with ~47% GPU headroom and no
  CPU pressure, so it cannot show a throttled frame.
- **A long Nominal → Serious → Critical ramp.** Attempted; the system suspended the
  unattended session after about ten minutes (the app's pid changed and the screen was
  back at the home screen). Finding F8 below is that result. A ramp must be run with the
  device kept awake.
- **Charging and brightness.** The HUD shows both (battery row, and `AC power`), but only
  in its expanded view, which needs a tap this project has no tool for. The screenshot at
  19:37 shows the battery at 100% on power, so **the device was charging throughout**,
  which is a heat source the software does not control.
- **Anything on a second device.** One iPad, one SoC.

## Method

The client's own instrument, `--measure-native`, writes one line every five seconds
(`platform/translation/Metal/Presentation.m`, layer patches 0019 and 0026):

```
frame timing seconds=5.01 fps=60.0 gap_avg_ms=16.67 max_gap_ms=25.0
  gap_bins_lt12=.. gpu_ms=8.1 gpu_load=0.53 wait_ms=0.01
  cpu_submit_avg_ms=0.04 cpu_submit_max_ms=0.28 ...
  thermal=2
```

- `fps`, `gap_avg_ms`, `max_gap_ms`, and the gap histogram come from the presentation
  timestamps the layer records.
- `gpu_ms` is `MTLCommandBuffer.gpuEndTime - gpuStartTime` for the buffer that presented
  the frame, which is Apple's documented way to ask Metal how long the GPU ran it
  ([`gpuStartTime`](https://developer.apple.com/documentation/metal/mtlcommandbuffer/gpustarttime)).
- `gpu_load` is the GPU's busy share of the last second.
- `wait_ms` is how long the client blocked asking `CAMetalLayer` for a drawable.
- `thermal` is `ProcessInfo.thermalState` (0 nominal, 1 fair, 2 serious, 3 critical),
  whose values Apple defines as "within normal limits", "slightly elevated", "the thermal
  state is high", and "significantly impacting the performance of the system and the
  device needs to cool down"
  ([_ProcessInfo.ThermalState_](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum)).

`wolkaraforever/tools/perf_sweep.py` writes one `Config.wtf` per variant, launches the client with
`--local-game-startup --measure-native`, waits for the login screen, samples, stops the
client, and prints the table below. Every row can be reproduced with one command; the raw
windows and the exact `Config.wtf` used are kept under `logs/perf/<timestamp>/`.

```
wolkaraforever/tools/perf_sweep.py --stop-first --variants native,preset,half
```

## Results: the login screen, release 1.60.1.70634

Five-second windows; `at 60` is the share of windows at ≥59.5 fps. "Caps" means
`gxForegroundFPS 60`, `gxBackgroundFPS 30`, `vsync 1`; the wiki-named variant uses
`useMaxFPS 1`, `maxFPS 60`, `useMaxFPSBk 1`, `maxFPSBk 30`, `vsync 1` instead.

| variant | what it sets | windows | fps mean | fps min | at 60 | GPU ms | GPU load | wait ms | gap p95 | gap max | thermal |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `native` | renderScale 1.0, no cap named | 6 | 60.00 | 60.00 | 100% | **9.3** | 0.53 | 0.01 | 25.0 | 25.0 | serious×6 |
| `preset` | renderScale 0.75 + caps | 12 | 60.02 | 60.00 | 100% | **7.8** | 0.46 | 0.01 | 25.0 | 25.0 | nominal×12 |
| `presetwiki` | renderScale 0.75 + wiki caps | 12 | 60.02 | 60.00 | 100% | **7.9** | 0.46 | 0.01 | 20.8 | 25.0 | nominal×12 |
| `half` | renderScale 0.5 + caps | 12 | 60.02 | 60.00 | 100% | **5.1** | 0.30 | 0.01 | 25.0 | 25.0 | nominal×12 |
| `drs` | renderScale 1.0, `DynamicRenderScale 1`, `DynamicRenderScaleMin 0.5`, `targetFPS 60` | 12 | 60.00 | 60.00 | 100% | **9.0** | 0.53 | 0.01 | 25.0 | **33.4** | nominal×12 |
| `stress` | renderScale 2.0 (4× the pixels) | — | **23.6** | — | 0% | **75-81** | — | — | — | 42.5 mean gap | — |

`stress` has no five-second summaries: at 4× the pixels every frame is an anomaly, and the
per-frame anomaly line (patch 0034) is what the log carries instead. Its frame is 42.5 ms
with 75-81 ms of GPU work per command buffer — a genuinely GPU-bound frame, and the
candidate "worst case" nobody should play at.

A second session, later, ran the default and the app's own render profile back to back on
a cooled device, both at nominal thermal throughout:

| variant | what it sets | windows | fps mean | fps min | GPU ms | GPU load | wait ms | gap p95 | thermal |
|---|---|---|---|---|---|---|---|---|---|
| `native` | renderScale 1.0, no cap named | 17 | 60.02 | 59.90 | **9.0** | 0.53 | 0.01 | 25.0 | nominal×17 |
| `backing075` | `TOLKARA_BACKING_SCALE=0.75` (the app's "Performance" profile) | 19 | 60.02 | 60.00 | **9.9** | 0.57 | 0.01 | 25.0 | nominal×19 |

**Caveat on absolute numbers:** the login screen animates, and its GPU cost varies by
about ±2 ms between scenes (7.5-11.0 ms of `gpu_ms` inside a single two-minute run). Every
comparison here is between runs minutes apart, not on a frozen frame; the large, monotone
steps (9.3 → 7.8 → 5.1 for render scale) are far outside that variance, the 9.0-vs-9.9
pair is inside it and is reported as "no reduction", not as a regression.

## Findings

**F1 — The release build holds 60 exactly at the login screen in every sane
configuration, and the GPU is not the reason.** 60.00-60.02 fps, `wait_ms` 0.01,
`gap_avg` 16.65-16.68 ms. With 9.3 ms of GPU work in a 16.7 ms frame the GPU has ~7 ms
spare; this scene cannot throttle-test anything. Any 60 fps claim from this scene is a
claim about vsync, not about the game.

**F2 — Render scale is the lever that moves GPU time, and it moves less than the pixel
count.** 9.3 ms at 1.0 → 7.8-7.9 ms at 0.75 (−43.75% pixels, −16% GPU) → 5.1 ms at 0.5
(−75% pixels, −45% GPU). The two steps do not scale alike, so a fixed, pixel-independent
cost of roughly 3.5-4 ms remains. **Consequence:** at 0.5 the GPU still costs ~5 ms, and
a plan that assumes "half the pixels, half the time" will be wrong by that fixed part.

**F3 — Cutting per-frame GPU work moves the thermal state, measurably.** The `native` run
was at state *serious* in all six windows. The `preset` and `half` runs, minutes later on
the same device, were at *nominal* in all twelve windows each. That is not a coincidence
of timing: the only thing that changed between runs was the per-frame GPU work (9.3 → 7.8
→ 5.1 ms) and the resulting power draw. This is the software lever Apple describes —
resource-intensive apps "can choose to reduce resource use enough to avoid a Critical
thermal state"
([_Test under adverse device conditions_](https://help.apple.com/xcode/mac/current/#/dev308429d42))
— and it acted within minutes, not hours.

**F4 — The client's own dynamic resolution scaler did nothing here, and paced worse.**
`DynamicRenderScale 1` with `targetFPS 60` left the scale at 1.0 (GPU 9.0 ms, load 0.53,
identical to `native`) because the frame was never GPU-bound, and it produced the run's
only 33.4 ms gap (worst p95/max of any variant). Blizzard documents the same two
problems: the feature "Lowers render scale if GPU bound to hit Target FPS", is "in BETA",
and "May cause hitching. May behave poorly with vsync on."
([_Console variables_](https://warcraft.wiki.gg/wiki/Console_variables)). Do not build the
thermal plan on it.

**F5 — A frame cap cannot be tested on this scene, and one CVar spelling of "no cap"
freezes the client.** The cap variants are indistinguishable from uncapped here because
vsync already pins 60. Separately, `gxForegroundFPS 0` (the app's preset vocabulary for
"no limit") produced **no presented frames at all** in the first sweep — the client stops
presenting. The wiki's spelling of "no limit" is `useMaxFPS 0` with `maxFPS` left at its
own value, not a limit of zero. The preset in the app must not use `0` for a cap.

**F6 — Supersampling is not free and not stable.** At `renderScale 2.0` the client ran at
23.6 fps with 75-81 ms of GPU work, and the session did not survive: the app was
backgrounded and relaunched (new pid) within about ten minutes. 5464×4096 drawables are a
memory and bandwidth problem before they are a speed problem. The "Quality — 2732 × 2048"
row in the app's render-profile sheet is a diagnostic, not a play mode.

**F7 — Nothing in the layer reacts to heat or to Low Power Mode.** The only reader of
`thermalState` and `isLowPowerModeEnabled` is the HUD, which displays them
(`wolkaraforever/Touch/AKPerformanceOverlay.m`). No code changes behaviour. Apple's
guidance is explicit that an app should: "If Low Power Mode is active, take appropriate
steps to reduce activity in your app"
([_isLowPowerModeEnabled_](https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled)),
and Low Power Mode itself is documented as "Reducing CPU and GPU performance".

**F8 — An unattended session does not keep running.** During the GPU-bound ramp the app
was suspended and relaunched (pid 26846 → 26870) and the device sat at the home screen
with the client in the background; the guest log stopped growing at 6731 anomaly frames
and stayed there for eleven minutes. Any sustained measurement — and any player who puts
the iPad down mid-fight — depends on the device staying awake.

**F9 — The app's own render profile is the wrong lever.** The launcher's "Performance —
1024 × 768" profile sets `WolkaraForeverBackingScale` 0.75, and its sheet says it
"submits 56% fewer pixels". Measured against the default on a cool device: **9.9 ms of GPU
with the profile against 9.0 ms without** — no reduction at all. The client's own
`renderScale 0.75`, by contrast, measured 7.8-7.9 ms in the earlier session. The drawable
is indeed smaller, but the guest's scene cost does not follow it, which is what a client
that renders to its own targets and blits to the drawable would look like. **The control
the product ships does not do what its label says; the client's CVar does.** That has to
be settled by measurement before the profile is renamed or relied on (S2).

**F10 — The 16-20 ms drawable wait identifies a presentation-path problem, not its
cause.** The in-world trace has 21-25 ms present gaps, 8.2-8.9 ms of GPU work,
`cpu_submit_avg_ms` 0.04-0.05, and **16.2-20.4 ms in
`-[CAMetalLayer nextDrawable]`**. That rules out command submission as the dominant cost,
but does not distinguish display scheduling, drawable-queue saturation, or guest pacing.
The 20.8/25.0 ms values are compatible with 48/40 Hz steps; they do not prove those rates.

Apple's model for that: "the system insulates the ProMotion display's actual refresh rate
from your app — you can't force a ProMotion display to show your content at any specific
rate", Core Animation "arbitrates ... and determines the refresh rate at any particular
time", and "the system provides games with special priority to 30Hz and 60Hz refresh rates
... your game needs to set a preferredFrameRateRange with a CAFrameRateRange structure
using one or both of those values"
([_Optimizing for ProMotion_](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays)).
**No code in either tree made that claim**: the only `CADisplayLink` was the performance
HUD's, at 4-30 Hz preferred 10.

The display link is not a CPU cost to retain in normal gameplay: it is a capture-only
measurement, not the guest's render driver. It is available only with
`--measure-display-rate`, alongside
`wolkaraforever/Bridge/DisplayRate.m` (compiled into the Metal adapter, installed from a
constructor like `BackgroundPacing.m`):

- it requests `CAFrameRateRangeMake(30, 60, 60)` only during that diagnostic capture;
- it logs, once per second, the interval Core Animation schedules for **that display link**
  and the callback interval: `display link rate: target 16.68ms (60.0 Hz), callback mean
  33.35ms ...`.

Measured on the login screen with it installed: the claim is logged (`asked for 30-60 Hz,
preferring 60 (screen maximum 120)`), the target is **16.68 ms = 60 Hz**, and the frame
figures are unchanged — 60.00 fps, GPU 8.4-9.1 ms, `wait_ms` 0.01, gap p95 25.0. This
proves the link request was accepted for the link; it does **not** prove the game presented
at 60 Hz. The Metal present distribution remains the proof for the renderer.

**What is still unproven:** in-world present cadence. It needs an in-world trace. If the
Metal gaps remain 21-25 ms while this link remains at 16.68 ms, the link request did not
solve presentation pacing and the drawable queue/guest pacing must be instrumented next.

**F11 — Nothing sets the drawable queue either; the competing HUD hint was removed.**
`CAMetalLayer.maximumDrawableCount` and `displaySyncEnabled` are left at their defaults
(3 and YES on iPadOS); the diagnostic now logs the observed layer configuration rather
than assuming it. The HUD's 4-30 Hz fallback `CADisplayLink` has been removed: it was only a fallback
number, while its preferred range was a second scheduling hint. The HUD now waits for the
Metal counters rather than issuing a competing request.

## The arithmetic for 60 fps when the SoC is hot

At 60 Hz the budget is 16.7 ms per frame (Apple's own ProMotion table lists 60 Hz as
16 ms,
[_Optimizing for ProMotion_](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays)).

The one throttled comparison on this device
([PERFORMANCE_LANES.md](PERFORMANCE_LANES.md), 2026-10-23, in world, beta build) is:

| | at rest | throttled | ratio |
|---|---|---|---|
| frame | 20.0 ms | 29.2 ms | 1.46× |
| GPU busy | 7.8 ms | 10.9 ms | 1.40× |
| thermal | Nominal | Serious | — |

Both the CPU side and the GPU slowed by about the same proportion, which is what a
SoC-wide clock reduction looks like, and Apple documents the outcome without the number:
in hot conditions "performance is reduced with lower frame rates or increased processing
times"
([_If your iPhone or iPad gets too hot or too cold_](https://support.apple.com/en-us/118431)).

So a frame that must survive Serious thermal has to fit **16.7 / 1.46 ≈ 11.4 ms** at
Nominal, and its GPU part **16.7 / 1.40 ≈ 11.9 ms**. The measured in-world nominal frame
was 21-25 ms with 8.2-8.9 ms of GPU — about **1.8-2.2× too slow on the frame** and inside
the GPU bound. The GPU part is the easier half: render scale 0.5 takes a ~8.5 ms GPU frame
to roughly 5 ms (F2's fixed cost + a quarter of the scaling part), which is within
11.9 ms. **The remaining 16-20 ms is on the CPU and presentation side and is the actual
work.**

That also means the honest promise is: *render scale will keep the GPU cool and buy
headroom, and it will not by itself make a CPU-bound world frame hit 60.* The next step
below is to find out what that CPU-side time is made of, because nothing measured so far
splits it.

## Next steps, in the order the measurements support

Each step says what to change, what it is expected to do *in milliseconds*, and how the
result will be judged. Nothing here is adopted until its own measurement says so.

### S1 — Measure actual in-world presents, then act

The display-link line proves only the diagnostic link's scheduling interval. The first
in-world run must instead correlate the link line with the Metal evidence from the same
window: `frame timing` gap bins, anomaly lines, `wait_ms`, GPU time, and the logged
drawable-pool configuration.

- **Link target 16.68 ms but Metal gaps still cluster at 20.8/25.0 ms** → the request did
  not fix render pacing. Keep display sync unchanged and instrument guest-side work before
  changing queue depth; a larger queue can trade latency for throughput and is not a free
  performance fix.
- **Metal gaps converge on 16.67 ms** → the request removed the observed cadence issue;
  repeat under thermal load before calling it stable.

Launch with `--local-game-startup --measure-native`, preserve the full log, and record the
thermal state. Do not infer in-world performance from the login scene or a passive link.

### S2 — Make the render profile write the client's `renderScale`, and settle what the
backing scale does

The launcher's "Render profile" sheet writes only our own `WolkaraForeverBackingScale`
(0.75 / 1.0 / 2.0), and F9 measured that 0.75 of it does not reduce GPU work (9.9 ms vs
9.0 ms). The layer's `+[TKForeverUI performancePreset]` — `renderScale 0.75`,
`gxForegroundFPS 60`, `gxBackgroundFPS 30`, `vsync 1` — exists and **has no caller**, and
the client's `renderScale` is the one that measured a real saving (F2).

So: one control writes the client's `renderScale` (and the wiki-named caps
`useMaxFPS 1`, `maxFPS 60`, `maxFPSBk 30`, never `0`, F5); the backing-scale path is kept
only for what it demonstrably does — the drawable's size — and its label stops claiming a
pixel reduction the scene does not get.

**Update, 2026-10-29 — the first half of S2 was decided against; that is not a fix.**
The [launcher reorganization](../uichanges/LAUNCHER_REORGANIZATION_PLAN.md) settles how the
two levers are separated, not that the saving was found. The page's **Render profile** row
writes only `WolkaraForeverBackingScale` and says so, and the rows that write the game's
`Config.wtf` are a different card with different names, so nothing on the page mixes "how this
app draws" with "what the game is told". `performancePreset` still has no caller. The shipped
control is therefore an honest smaller-drawable switch, and the measured 7.8-7.9 ms saving
from the client's own `renderScale` is still **unused**. S2 remains open and is now narrower:
if the game's CVars are ever written from the page, it has to be a separately named,
separately explained control — not this row quietly changing meaning. Until then every profile
record in `WoW/DeviceProfile.m` carries F9 in its own notes, so a reader of the table cannot
mistake Performance for a faster frame.

*Expected effect:* the measured 9.3 → 7.8 ms GPU (F2), and the measured return from
*serious* to *nominal* (F3).

*Judge it by:* `perf_sweep.py` on the same scene showing GPU ≤ 8.0 ms with the profile
selected through the product's own UI path (not by a hand-written `Config.wtf`), and the
settings surviving a client restart (the wiki notes `Config.wtf` is rewritten on exit, so
the writes must happen while the client is not running: "Config files can be manually
edited while the game is not running; they would otherwise be overwritten"
([_Console variables_](https://warcraft.wiki.gg/wiki/Console_variables))).

### S3 — Ship a thermal ladder with hysteresis, and prove it under Xcode's thermal condition

When `thermalState` reaches *serious*, step down one rung (0.75 → 0.5); at *critical*,
step to 0.5 **and** cap the frame rate at 30, because a stable 30 beats a swinging 45-55.
Recover one rung only after the state has been nominal for several minutes — never
oscillate.

*Why with hysteresis:* Apple documents the risk of exactly this loop: "Dynamically
adjusting render quality in response to refresh rates ... can throttle the GPU. To avoid
an oscillating feedback loop, use code paths for different frame rates and test them on
actual devices"
([_Optimizing for ProMotion_](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays)).
It also documents that the system itself may reduce what a display link may ask for: "Low
Power Mode, critical thermal state ... can affect the system's frame rate"
([_preferredFrameRateRange_](https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange)).

*Judge it by:* Xcode's Device Conditions, Serious profile, running the same fixed scene
for ten minutes: the ladder must engage, the frame must settle, and the state must not
reach critical. That is the same test Apple prescribes for games, and it removes the need
to heat a real device to reproduce it.

### S4 — Keep the device awake while a session runs

Set `UIApplication.shared.isIdleTimerDisabled` while a guest is live (and clear it on quit).

*Why:* F8 measured the session dying after about ten minutes unattended. A player who
touches the screen is unaffected, but every measurement in this document had to be
supervised, and a long fight on a controller-only setup would hit the same timeout.

*Judge it by:* a 30-minute `perf_sweep.py --hot` run whose window count keeps growing to
the end.

### S5 — Cut the fixed part of the GPU frame

Roughly 3.5-4 ms of the login screen's 9.3 ms does not scale with resolution (F2). That is
the part render scale cannot buy back — shadow-map size, screen-space passes, the UI
composite — and it is also the part that determines how much render scale *can* save.
Profile it with Metal's own GPU counters per pass, then lower the specific setting
(`graphicsShadowQuality`, `graphicsSSAO`, `graphicsResampleQuality`) one at a time, each
with a `perf_sweep.py` row.

*Judge it by:* GPU ms with the setting changed, everything else identical. A setting that
does not move `gpu_ms` stays as it is.

### S6 — Take the power the software does not own out of the loop, and say so in the UI

The device was charging throughout (100%, AC) and the backlight is a first-order power
draw at 5.6 MP. Apple lists both as heat sources: the device feels warmer when you
"Wirelessly charge your device" or "Use graphics-intensive ... apps", and when it is too
warm "Charging ... slows or stops" and "The display dims"
([_118431_](https://support.apple.com/en-us/118431)). The operating range is 0-35 °C.

There is nothing to fix in code here; the plan is a line in the settings page and in
`docs/`: playing while charging in a warm room is the case that produces *critical*, and
the ladder in S3 is what protects the frame rate when it happens.

### S7 — Do not adopt `DynamicRenderScale`, and keep the Quality profile off the play path

Measured no effect where it should have acted and the worst pacing of any variant (F4),
with Blizzard's own caveat attached. Keep it out of the preset. The app's "Quality —
2732 × 2048" profile is a diagnostic: 23.6 fps and a session that did not survive ten
minutes (F6).

### S8 — Attribute the 25 ms gap before chasing it

One frame in roughly every five seconds arrives a refresh late (p95 and max 25.0 ms in
most windows; 20.8 ms in some). It is small, it is regular, and it is unexplained
(candidates: the HUD's 10 Hz display link, a guest timer, UIKit work on the main thread).
A 60 fps target means this is either fixed or shown to be harmless; a TSan-style timeline
of one bad frame decides which.

## What would change this plan

- If S1 shows the in-world 21-25 ms is mostly *waiting* rather than work, the fix moves
  to the presentation path (drawable count, `gxMaxFrameLatency`, pacing), not to the
  scene's CPU cost.
- If S1 shows most of the frame is guest-side work inside the client's own code, render
  scale becomes the main lever and the target becomes "hold 60 at 0.5", with the ladder in
  S3 doing the work.
- If a second device with a different SoC behaves differently, Apple's own warning
  applies: "Different hardware has different thermal characteristics, and needs different
  profiling work to optimize it."

## Reproduce

```sh
# The table above, on the release build, without touching the settings sheet.
wolkaraforever/tools/perf_sweep.py --stop-first --variants native,preset,half

# The client's own dynamic scaler, for comparison.
wolkaraforever/tools/perf_sweep.py --stop-first \
    --variants "drs:renderScale=1.0;useTargetFPS=1;targetFPS=60;DynamicRenderScale=1;DynamicRenderScaleMin=0.5;vsync=1"

# The GPU-bound case (4x the pixels): no five-second summaries, read the anomaly lines.
wolkaraforever/tools/perf_sweep.py --stop-first --variants stress --hot --seconds 60 --hot-slots 12

# The app's own render profile, through the environment the layer reads.
wolkaraforever/tools/perf_sweep.py --stop-first --variants "backing075:env.TOLKARA_BACKING_SCALE=0.75"
```

Raw windows, the exact `Config.wtf` written for each variant, and the guest logs are kept
under `logs/perf/<timestamp>/`.
