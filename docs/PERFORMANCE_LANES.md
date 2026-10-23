# Performance lanes

An evaluation of every place this project could plausibly be costing performance,
each one either measured or explicitly marked as not measured. Written 2026-10-23
after a device session on Dadpad (iPad Pro 12.9-inch, 5th generation, M1, iPadOS 27),
Developer service, World of Warcraft Forever 1.60.1.

The rule this page follows: a lane is worth work only when something measured says
so. Where a hypothesis was tested and disproved, the disproof is kept here, because
the next person will have the same hypothesis.

> **Paths.** A bare `tools/<script>` means `wolkaraforever/tools/<script>` when the
> layer provides it, otherwise `platform/tools/<script>`. `translation/`, `runtime/`
> and `authorization/` live under `platform/`.

## The short version

| Lane | Verdict | What says so |
| --- | --- | --- |
| GPU time vs CPU time | **Measured in play: neither is saturated — the client misses the display budget.** In world the GPU needs 8.5 ms of a 21-25 ms frame and the client blocks 16-20 ms waiting for a drawable; at 60 fps on the login screen it never waits (0.01 ms). | `frame timing ... gpu_ms= wait_ms=` in the guest log |
| Thermal throttling | **Measured, and it is the biggest loss**: after ~20 minutes the same session read 32.6 fps with `Thermal State: Serious`, GPU 10.9 ms and both clocks down ~40%. Software cannot opt out; it can only draw less power sooner. | on-device HUD, 2026-10-23 |
| Frame pacing | **Clean**: 60.0 fps for 275 s at the login screen, no gap over 50 ms, one ~25 ms gap in most 5 s windows. **Not measured in play** - with the client CPU-bound at ~50 fps there is a frame to miss every 20 ms. | same log, `max_gap_ms`, `gaps_over_50ms` |
| Sustained play / thermal | **Not measured.** An earlier session on this iPad (2026-10-22) fell from 59.7 to 47.9 fps over ten minutes; that is a symptom with no controlled run behind it. | that session's guest log only; needs a fixed-scene run |
| Launch latency | **Measured defect, partly fixed**: 67.3 s of developer-service memory preparation per cold launch, now 62.5 s. The rest is the tunnel's own one-segment-in-flight TCP, not the protocol above it. | provider progress file sampled once a second on the device; `[local-launch] arena result ... elapsed=` |
| 60 vs 120 Hz | **Not a layer limit.** Nothing in the tree sets a frame cap; the client's own `Config.wtf` asks for vsync. | `preferredFramesPerSecond`/`displaySyncEnabled` absent from all code |
| CoreVideo display link | **Hypothesis disproved.** `CVDisplayLink*` is bound as a zero-returning stub, but the client never calls it. | `[stub]` lines appear only on first *call*; no `[stub] CVDisplayLink...` line in a full session |
| Shader / pipeline warm-up | **Measured in play, and large**: 114 Metal libraries loaded during one 265 s session, 96 of them inside one 20 s window at world entry. Each is a rewrap plus an iPad compile. | `On-device Metal library <sha>: loaded` lines, timed against the audio engine's fixed-rate counters |
| Run-loop mode error | **Open defect**: CoreFoundation logs `invalid mode 'kCFRunLoopCommonModes' provided to CFRunLoopRunSpecific` the moment the HUD is enabled. CF prints this once per process, so the frequency is unknown and could be every frame. | `native-guest.log`, 2026-10-23 07:56:19 |
| Texture upload (BC decode) | **Not engaged** on this hardware: the GPU samples BC natively, so the CPU decoder never runs. | `Metal BC: Apple M1 GPU samples BC textures natively, nothing installed` |
| Managed storage | **Not engaged** by default; the translation is opt-in and no run has shown the client asking for Managed. | `translation/Metal/ManagedStorage.m`, `--metal-managed-storage` |
| Input latency | **Not measured.** It is a latency lane, not a frame-rate lane. | see `docs/TOUCH_INPUT.md` |

## What the layer can and cannot cost

The client runs as native arm64 code in this process: `runtime/` places the image
and calls its original `main`. There is no interpreter and no per-instruction
translation in the path, so the layer cannot cost CPU per guest instruction. What it
costs is in the calls that cross from the guest into an adapter, and in the frame
hooks the adapters install.

The per-frame hooks that exist:

| Hook | When it does anything | Cost when it does nothing |
| --- | --- | --- |
| `-[CAMetalLayer nextDrawable]` | only with `--sample-native`, `--measure-native`, or the HUD on | one atomic load, then the drawable is returned untouched |
| `presentDrawable:` and its two variants | same | one atomic load |
| `commit` | same | one atomic load (the associated-object lookup is short-circuited) |

That gating is patch 0018 and it is deliberate: the presented handler allocates a
block and takes a lock per frame, and the first version of that patch did it for
every run whether or not anyone had asked for statistics.

Metal itself is not wrapped. The guest's device, queues, textures and encoders are
the iPad's own objects; the adapter swaps a handful of device predicates and
intercepts library loading (`translation/Metal/Devices.m`). Draw calls therefore
cost what they cost natively.

## Lane 1: is a frame waiting on the GPU or the CPU?

This is the question every other frame-rate lane depends on, and until patch 0019
the project could not answer it: a frame rate and a frame interval are the same
whether the GPU took 16 ms of the frame or 6 ms with 10 ms of drawing code in front
of it.

Patch 0019 records `MTLCommandBuffer.gpuStartTime`/`gpuEndTime` for the buffer that
presented each frame — the documented way to ask Metal how long the GPU ran a
command buffer — and publishes the last frame's GPU time and the GPU's share of wall
time over a trailing second. The log line `--measure-native` already printed now
carries `gpu_ms=` and `gpu_load=`, and the HUD's expanded view reads the same two
values by name into a `GPU:` row. (The row's text is set in the same 0.5 s pass as
every other row, and the app ran with the overlay switched on without a crash;
reading it on screen needs the HUD expanded by a tap, which this project has no tool
for — so what is proved here is the number, not the pixel.)

Measured at the login screen, 31 consecutive 5 s windows. Two things happen in
them. At rest the GPU is idle about half of every frame:

```
fps=60.1 max_gap_ms=25.0 gpu_ms=8.0 gpu_load=0.53
fps=60.0 max_gap_ms=25.0 gpu_ms=9.1 gpu_load=0.56
fps=60.0 max_gap_ms=25.0 gpu_ms=10.3 gpu_load=0.60
```

and then, as the client finished loading the screen, GPU time rose to fill the frame
and went past it once:

```
fps=60.0 max_gap_ms=20.8 gpu_ms=14.0 gpu_load=0.80
fps=60.0 max_gap_ms=20.8 gpu_ms=16.8 gpu_load=0.94
fps=59.2 max_gap_ms=25.0 gpu_ms=25.9 gpu_load=1.70
```

Read it as: at rest there is no lane here, because the GPU has roughly half the
frame spare and the display, not the layer, sets the pace. During a transition the
GPU is the limit — 16.8 ms of a 16.7 ms budget, then a 25.9 ms frame — which is the
shape a real GPU-bound scene would have, and the reason a busy scene may behave
very differently from the login screen. `gpu_load` above 1.0 is legitimate: two
command buffers from different queues can overlap inside one second.

**What is still unmeasured is gameplay.** The login screen renders a quiet scene.
The numbers that matter are the ones from a busy area with the user's settings, and
they need a person to log in — the project does not automate the client. The
instrument for that run now exists; see "How to measure it" below.

### In play (2026-10-23, same build, HUD on)

With the client in a questing zone at the user's settings, the HUD read:

```
Frame Rate: 49.8 FPS (20.0 ms)
GPU: 7.8 ms of 20.0 ms (39% busy)
Thermal State: Nominal (Cool) · Low Power Mode: Off
RAM Footprint: 3826 MB · Headroom: 12558 MB
```

That is the answer to the lane, and it is not the GPU: the GPU still does its 7.8 ms
— the same 8-10 ms it did at 60 fps on the login screen — while the frame grew to
20.0 ms. Where the other 12 ms went was still open at that point, so the next build
recorded how long the client blocks asking for a drawable (`wait_ms`). Re-measured
in play with that instrument, in 5 s windows across the login→world transition:

| phase | fps | frame | GPU | wait for a drawable | thermal |
| --- | --- | --- | --- | --- | --- |
| login screen | 60.0 | 16.7 ms | 7.3-15.0 ms | **0.01-0.02 ms** | nominal |
| login → world (loading) | 17.7-47.1 | gaps of 430-690 ms | 1.8-2.3 ms | 0.03-0.55 ms | nominal |
| in world, settled | 39.5-47.1 | 21-25 ms | 8.2-8.9 ms | **16.2-20.4 ms** | nominal |

Read together, those three rows settle the lane:

- At the login screen the client never waits for a drawable and holds 60 exactly.
- While the world loads it stalls for hundreds of milliseconds at a time — that is
  the asset and shader work in Lane 5, not the loop.
- In world it **blocks 16-20 ms for a drawable** while the GPU needs only ~8.5 ms.
  The frame is 21-25 ms against a 16.7 ms display budget, so it misses refreshes
  and settles near 45 fps. It is not CPU-starved and not GPU-starved: it is a few
  milliseconds over budget, and the overrun shows up as waiting for the present
  pipeline to give it another drawable.

That reframes the fix. Cutting CPU work alone would not restore 60 unless the overrun
goes below zero, and the most direct way to buy back 4-6 ms is to make the GPU's
~8.5 ms smaller — which is the render scale the client is not using.

One measurement caveat: these are windows with the HUD switched on, so the HUD's own
per-frame work (a block, an associated object and a short lock per presented frame)
is included in them. It is a diagnostic setting, off by default.

### The same session, throttled

Twenty minutes later the same session read:

```
Frame Rate: 32.6 FPS (29.2 ms)
GPU: 10.9 ms of 29.2 ms (36% busy)
Thermal State: Serious (Throttling active)
RAM Footprint: 4542 MB · Headroom: 11842 MB
```

That is the collapse the user feels, and the three numbers together name it:

| | at rest | throttled | ratio |
| --- | --- | --- | --- |
| Frame | 20.0 ms | 29.2 ms | 1.46x slower |
| GPU busy | 7.8 ms | 10.9 ms | 1.40x slower |
| GPU share | 39% | 36% | - |

Both the CPU side and the GPU lost about the same proportion, which is what a
*SoC-wide* clock reduction looks like, not a workload that suddenly got heavier. And
the GPU is still only a third of the frame, so the client remained CPU-bound
throughout: **the throttle is the cause of the collapse, and lowering the GPU's work
alone would not restore 60 fps unless it first lowers the power draw enough for the
clocks to come back.**

`ProcessInfo.ThermalStateSerious` is Apple's "the thermal state is high"; `critical`
is documented as "significantly impacting the performance of the system and the
device needs to cool down". Neither is something an app can opt out of, and no iPad
has a fan. The only lever software has is to draw less power, sooner, so the device
never reaches the state — and to recover, to wait for it to cool.

What makes the sustained draw here bigger than it needs to be, in the order the
measurements support:

1. **The client renders at native 2732x2048** (5.6 MP): `[ak] window content size ->
   1366x1024 @2x`, and no `renderScale` assignment exists in `Config.wtf`, so the
   internal scale is the default 1.0. The GPU's 8-11 ms is a continuous power draw.
2. **No frame cap.** `Config.wtf` carries `useMaxFPS "1"` but no frame-rate
   assignment, so nothing stops the client rendering as fast as it can outside the
   scene limit — menus, loading and the login screen included.
3. **The iPad was charging during the throttled sample** (`Battery: 100%
   (Charging)`). Charging is a second heat source inside the same chassis; a session
   that throttles while plugged in may not throttle on battery.
4. **Brightness** was not measured. The backlight is the largest single power draw on
   an iPad display and therefore a first-order thermal input at 5.6 MP.

Items 1 and 2 are the client's own settings and can be applied by this app; 3 and 4
are the user's to control while playing. See "Lane 10" below for what was changed and
what it measured.

Two candidates for that time, both ours to check and one already measured:

- **Shader warm-up (measured).** 114 Metal libraries loaded during the session, 96
  of them in one 20 s window at world entry (see Lane 5). That is a stutter a player
  feels at the start of a zone, not a steady 50 fps.
- **A run loop entered with an invalid mode (unresolved).** CoreFoundation logs
  `invalid mode 'kCFRunLoopCommonModes' provided to CFRunLoopRunSpecific` the moment
  the HUD is switched on. `CFRunLoopRunSpecific` refuses a common mode, so the call
  returns at once — if the caller loops on it, the main thread spins and burns a
  frame's worth of CPU doing nothing. CF prints the message once per process, so how
  often it really happens is unknown from the log alone, and it is the next thing to
  count.

## Lane 2: frame pacing

Same kind of session, 55 windows of 5.01 s each (275 s) on the build before the GPU
instrument, plus 31 windows on the build after it (59.2-60.1 fps there):

| Measure | Result |
| --- | --- |
| Frame rate | 59.9-60.2 fps in every window of the 55-window run; 59.2-60.1 in the later one, its single 59.2 being the frame Lane 1 attributes to the GPU |
| Longest gap in a window | 20.8 ms (5 windows) or 25.0 ms (50 windows) |
| Gaps over 50 ms | 0 in every window |

So: no stutter, and one missed frame roughly every five seconds. That 25 ms gap is
one frame's worth of lateness (a 16.7 ms frame arriving one display refresh late)
and it is **not yet attributed** — the timestamps say when a frame was presented,
not what delayed it. Candidates that a future run can separate: the HUD's own 10 Hz
display link, a guest-side timer, or UIKit work sharing the main thread.

Nothing in either tree caps the frame rate:

```
grep -rn 'preferredFramesPerSecond|displaySyncEnabled|preferredFrameRateRange' \
    platform wolkaraforever
```

returns only the HUD's own display link (10 Hz, so it does not fight the game) and
the adapters *reporting* the display's refresh rate to the guest
(`translation/AppKit/Screens.m`, `translation/CoreGraphics/Displays.m`).

### The display-link hypothesis, and why it is wrong

An obvious suspect was that the client's `CVDisplayLink` calls — the usual way a
macOS game takes its frame timing from the display — are stubs:

```
[native] stub _CVDisplayLinkCreateWithActiveCGDisplays as function ordinal=30
[native] stub _CVDisplayLinkSetOutputCallback as function ordinal=30
[native] stub _CVDisplayLinkStart as function ordinal=30
```

Those lines are emitted when an import is *bound*, not when it is called. The
runtime logs a `[stub] <name>() called` line the first time any stub is actually
called, and a full session contains exactly four, none of them CoreVideo:

```
[stub] GetSymbolicHotKeyMode() called
[stub] EnableSecureEventInput() called
[stub] CGSSetDebugOptions() called
[stub] AXIsProcessTrustedWithOptions() called
```

The client never calls `CVDisplayLink`, so implementing it would change nothing.
Recorded here so nobody implements it twice.

## Lane 3: sustained play and heat

The one observation that suggests a real deficit is an earlier session on the same
iPad: 59.7 fps over the first 600 frames, 47.9 fps over frames 600-1800. A 20% fall
after ten minutes on an M1 iPad is what throttling looks like, but nothing about
that session is controlled: no fixed scene, no thermal record, no GPU time.

This is the lane most likely to matter to the person playing, and the least measured.
A run that holds one scene for ten minutes now records, per 5 s: fps, longest gap,
GPU ms, GPU load — plus the HUD's thermal state and battery. That is enough to say
whether the GPU is saturated (gpu_ms approaching the frame interval), the CPU is
late (gpu_ms far below it), or the SoC is throttled (thermal state rising while
gpu_ms stays low and the frame is late anyway) — three different answers with three
different owners.

## Lane 4: launch latency — the one measured defect

Every cold launch with Developer service prepares the arena first: 99,532,800 bytes
of fresh memory that the service reads back as zero, then touches one byte per
16 KiB page, then reads each back. The app times it and says so:

```
[local-launch] arena result=1 bytes=99532800 elapsed=67.308s
```

67.3 s before anything of the game runs. That is the largest measured cost in the
project, and unlike the frame-rate lanes it is definitely ours.

### Where the time goes, measured

The provider keeps its own progress in
`Documents/local-authorization-progress.txt` in the extension's container
(`local.wolkaraforever.johnklock.authorization`), rewritten once a second. Sampling
it from the Mac during a launch gives the phase and the byte offset:

```
+ 4s phase=preflight, region=0, offset=2093056
+ 6s phase=preflight, region=0, offset=5232640
+10s phase=preflight, region=0, offset=11511808
+20s phase=preflight, region=0, offset=27732992
```

That is a steady 1.5-1.6 MB/s through the whole image. At that rate the 99.5 MB
read-back alone takes 62-66 s of the 67 s; what is left, the 6,075 page writes and
their read-backs, is the remainder of the total (this split is arithmetic from the
measured rate, not a second measurement). So the time is the read-back, and the
read-back runs at 1.5-1.6 MB/s.

### Why deeper batching does not fix it

The preflight used to send four read replies' worth of requests per round trip; patch
0020 raises that to thirty-two — eight times the window. Measured afterwards:
**62.5 s**, a 7% improvement rather than the 8x the window suggests.

That result rules out the protocol above the transport and points at the transport.
`authorization/Transport/TunnelTCP.swift` sends exactly one segment and waits:

```swift
private func flush(now: TimeInterval) -> [Event] {
    guard pending == nil, state == .established || state == .closeWait else { return [] }
    ...
```

with the intent stated at `tick`:

```
// Drive with a monotonic clock. Conservative one-segment flight limits
// control traffic; TLS underneath supplies congestion control for the link.
```

One MSS in flight, roughly 68,000 segments for this image, and 1.48 MB/s is 1460
bytes every 0.99 ms by that arithmetic — which is the 62-66 s observed. The batch
depth cannot help because the transport never has more than one segment outstanding.

**This is a design decision, not an oversight**, and it is in the code that carries
pairing and the memory-preparation protocol. The evaluation is therefore: a send
window in that transport (several segments in flight, cumulative ACK, retransmit)
would plausibly take the 62-66 s to a few seconds, and it is a change that needs its
own design and adversarial tests, not a tuning knob. Patch 0020 is the precondition
for it (the RSP layer's own window would cap a pipelined transport long before the
link did), and is worth keeping for that and for the peer test it makes eight times
faster — but it is not the fix, and the patch header says so.

## Lane 5: shader and pipeline warm-up

Shader libraries are rewrapped on the device and compiled by the iPad's own Metal,
and every library in a full session loaded:

```
[ak] On-device Metal library 5ccb2cc1...: loaded
```

Repeated loads of the same bytes are cached in an `NSCache` keyed by SHA-256 with a
64 MB cost limit (`translation/Metal/Devices.m`), so a level re-entering does not
recompile. What was missing was *when* and *how many*, which decides whether this is
a steady cost or a hitch.

**Measured in play (2026-10-23, 265 s session).** The `[ak]` lines carry no
timestamps, but the audio engine prints a fixed-rate counter every window (1024
frames at 48 kHz, 234.4 calls per window), so the log's own order against that clock
dates each load:

| When | Libraries loaded |
| --- | --- |
| 30-50 s after play began | **96** (29 in the first ten seconds, 67 in the next) |
| the other 215 s | 18 |
| whole session | 114 |

So this is a burst at world entry plus a trickle. 96 libraries in 20 seconds is a
hitch a player feels when a zone appears, not the reason a frame is 20 ms for the
whole session. The cost per load is still unknown — timing
`newLibraryWithData:error:` and the client's `newRenderPipelineState` calls is the
next instrument here, and it is small.

## Lane 6: texture upload

`TOLKARA_BC_FALLBACK` engages a CPU decoder for BC textures only when the GPU says
it cannot sample them. On this iPad it does not:

```
[ak] Metal BC: Apple M1 GPU samples BC textures natively, nothing installed
```

So no upload is decoded in software, and this lane is empty **on this hardware**. It
would matter on a device without BC sampling; the decision is a capability query,
not a device name, so such a device needs no code change and would show the fallback
line in its log.

## Lane 7: storage mode

macOS applications may ask for `MTLStorageModeManaged`, which iPadOS does not have.
`translation/Metal/ManagedStorage.m` can rewrite those requests to Shared, but only
under `--metal-managed-storage`, and no device run has shown the client asking for
Managed at all. If a future client did, the failure mode would be visible as buffer
creation errors rather than as slowness. Not a lane today; the check is to log the
first few resource creations with their storage mode.

## Lane 8: input latency

Not a frame-rate lane, and not measured here. The pieces that matter are the 1 ms
UIKit turn in `-[NSApplication nextEventMatchingMask:...]` for non-blocking polls
and the guest's event queue; both are in `translation/AppKit/AppKit.m`. Open PR #6
changes the touch-to-pointer path. Judge it with a tap-to-response measurement, not
with a frame counter.

## What Tolkara itself says

Checked 2026-10-23 against `tolkara/tolkara`:

| Item | State | Relevance to performance |
| --- | --- | --- |
| PR #1 | merged | guest executable analysis and the unsigned JIT mode; load time, not frame time |
| PR #2 | merged | iPhone support |
| PR #5 | open | controller support; input, not frames |
| PR #6 | open | touch tap and on-screen keyboard; input latency |
| Issue #3 | open | M5 compatibility report — says FPS was **not** measured |
| Issue #4 | open | the client asserts on a non-default display zoom; correctness |

So there is no upstream performance work to build on, and no upstream claim to
contradict. The only performance statement in the tracker is issue #3 listing frame
rate as untested, which is still true.

## How to measure it

```sh
# A run with the attribution lines in it.
xcrun devicectl device process launch --device "$DEVICE" "$TOLKARA_BUNDLE_ID" \
    --local-game-startup --measure-native
wolkaraforever/tools/device_log.sh 40 'frame timing'

# Launch latency, and where it went.
TOLKARA_BUNDLE_ID=$TOLKARA_BUNDLE_ID wolkaraforever/tools/device_log.sh 3 'arena result'
xcrun devicectl device copy from --device "$DEVICE" \
    --domain-type appDataContainer --domain-identifier "$TOLKARA_BUNDLE_ID.authorization" \
    --source Documents/local-authorization-progress.txt --destination /tmp/progress.txt
```

`gpu_ms` is the GPU's time for the last presented frame; `gpu_load` is the GPU's busy
share of wall time over the last second. A GPU-bound frame has `gpu_ms` close to the
frame interval in `fps`; a CPU-bound frame has `gpu_ms` well below it.

## What is not claimed

- No in-world frame rate, GPU time or thermal result. The login screen is the only
  scene measured here, and it has headroom.
- No result for any device other than Dadpad.
- No claim that 120 Hz is available to the client: the display reports its own
  refresh rate through the adapters, and what the client does with it was not
  measured.
- No claim that the 25 ms gap in Lane 2 is harmless. It is small and regular; it is
  not yet explained.
