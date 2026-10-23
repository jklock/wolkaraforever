# Case file: Tolkara frame performance on iPad, and what can be proven about it

**Purpose.** This document exists so that someone else — a person or a stronger model — can
audit every claim I have made in this project about performance, find the evidence for each,
and falsify any of them. Nothing here asks to be taken on trust. Every assertion carries one of
five tags, and any assertion without a tag is a defect in this document:

| Tag | Meaning |
| --- | --- |
| **PROVEN-CODE** | Visible in a file at a stated path and line, quoted or reproduced by a command in §12 |
| **MEASURED** | Recorded from the device by this project's own instrumentation; the log line or aggregate is quoted |
| **DOCUMENTED** | Stated by an external source; the URL and the sentence are quoted in §10 |
| **INFERRED** | Follows from the above by reasoning that is shown; could be wrong |
| **UNKNOWN** | Not measured, not documented; the measurement that would settle it is named |

Retracted claims are in §11 and are kept, not deleted.

---

## 1. Executive summary

1. The guest is an unmodified macOS arm64 program executed natively; the layer is a loader plus
   a set of hand-written API adapters. **PROVEN-CODE** (§3).
2. The client renders at **43.0 fps median / 29.7 fps minimum** in world, with the GPU busy
   **9.1 ms** of a **22.5 ms** frame and a drawable wait of **0.04 ms**. **MEASURED** (§5).
3. Halving the rendered surface from 2732×2048 to 1366×1024 changed the in-world rate from
   44.4 to 43.7 fps — inside run-to-run variation. **MEASURED** (§5.3). Therefore the GPU is not
   the constraint and no resolution change can help. **INFERRED**, with the measurement above as
   the evidence.
4. Every piece of code in the layer that can run once per presented frame is enumerated in §6,
   with file and line. In a normal run the layer installs **no** per-frame Metal hooks
   **PROVEN-CODE**, but its event pump does run **once per frame and costs ~1.15 ms on the frame
   thread** — the one measured per-frame cost the layer owns, and 7 % of the 16.7 ms budget.
   **MEASURED** (§5.6).
5. Ten concrete layer defects exist, each with a file and line, each fixable without changing
   the client. **PROVEN-CODE** (§8).
6. Whether those defects are *sufficient* to reach 60 fps is **UNKNOWN**. The single measurement
   that decides it is named in §9.
7. The client's own per-frame CPU is **UNKNOWN**: it is either ~22.5 ms (CPU-bound, GPU
   overlapping) or ~13.5 ms (CPUs and GPU serialised). The distinction decides whether 60 fps is
   reachable by any layer change at all. **UNKNOWN** (§9.1).

---

## 2. Where the rest of the documentation is

All of the following are in this repository, written in this session, and are the basis for the
per-frame claims in §6:

| Document | Contents |
| --- | --- |
| [docs/ADAPTERS/README.md](README.md) | The documentation convention: every line appears exactly once |
| [docs/ADAPTERS/AppKit.md](AppKit.md) | `AppKit.m` (1018 lines), `Screens.m`, `Images.m`, `TextInput.m`, `WindowFullscreen.m`, `Nibs.m` |
| [docs/ADAPTERS/AppKitExtras.md](AppKitExtras.md) | `AppKit.h`, `NibArchive.m`, `TouchControls.m`, `TouchTrackpad.c` |
| [docs/ADAPTERS/Metal.md](Metal.md) | `Devices.m`, `Presentation.m`, `MetalTrace.m`, `ManagedStorage.m`, `LibraryContainer.m` |
| [docs/ADAPTERS/Textures.md](Textures.md) | `BCTextures.m`, `BCDecode.c`, `RenderDiagnostics.m`, `StorageModes.h`, `RealFunction.h` |
| [docs/ADAPTERS/Audio.md](Audio.md) | `AudioToolbox/Output.m`, `AudioUnit/ldflags`, `CoreAudio/Hardware.m` |
| [docs/ADAPTERS/Core.md](Core.md) | CoreGraphics (5 files), CoreServices (3), Carbon (1), IOKit (2) |
| [docs/ADAPTERS/Security.md](Security.md) | Keychain, legacy CDSA crypto, session, GameController, shared headers |
| [docs/ADAPTERS/Support.md](Support.md) | `AKSupport.m`, `Alerts.m`, `Menus.m`, `EventMonitors.m`, `Drawing.m` |
| [docs/ADAPTERS/Performance.md](Performance.md) | The per-frame inventory assembled from the above |
| [docs/ADAPTERS/THROTTLE_DESIGN.md](THROTTLE_DESIGN.md) | The design for a permanently throttled device, including the retraction in §11.3 |
| [docs/ARCHITECTURE.md](../ARCHITECTURE.md) | What Tolkara is: loader, adapters, the three execution modes |
| [docs/LAYER_DELTAS.md](../LAYER_DELTAS.md) | The fork's changes to the vendored platform, by patch |
| `wolkaraforever/patches/` | The authoritative text of every patch, with its rationale |

Coverage of the adapter documentation is checked mechanically: a script walks
`platform/translation` and reports any `.m/.c/.h/ldflags` file not named in a document. At the
time of writing the answer is **zero**, and §12.1 gives the command.

---

## 3. What the system being measured actually is

Tolkara has Wine's shape: a loader that places an unmodified program in memory, and libraries
that implement the operating-system interface the program expects. **PROVEN-CODE**, from
[docs/ARCHITECTURE.md](../ARCHITECTURE.md):

- The macOS executable and the libraries it carries are mapped as data and executed as native
  arm64. There is no instruction translation on the execution path; `GuestCPU`/`GuestMemory` are
  a software MMU and scalar interpreter used **only** as a correctness reference for tests.
- Imports resolve through `GuestFixups` to (a) the application itself, (b) a hand-written
  adapter, or (c) a re-export of the real iPadOS framework. `tools/classify.py` sorts every
  imported symbol into present / hand-written / missing at build time.
- The hand-written surface is small and enumerated: **AppKit on UIKit, Metal, AudioToolbox /
  AudioUnit / CoreAudio, Carbon / CoreServices, CoreGraphics, Security**, plus two experimental
  adapters (GameController, MetalFX).
- Executable memory is prepared in one of three ways (Developer service, Local signing, External
  JIT); none of them touches the GPU or the frame path once the program runs.

**INFERRED, and this is the load-bearing inference of the whole case:** because everything that
is not in those six hand-written adapters is Apple's own code called directly, the layer can only
cost per-frame time in (a) the hand-written adapters, (b) the thread scheduling the host inherits,
and (c) memory layout. It cannot slow the client's own algorithms because it does not run them.

---

## 4. How the measurements were taken, and their limits

The instrumentation is this project's own, in `translation/Metal/Presentation.m`:

- `--measure-native` hooks `CAMetalLayer.nextDrawable` and adds a block to each drawable with
  `addPresentedHandler:`, reading `presentedTime`. Frame rate is computed from those presentation
  timestamps, so it counts **frames the display actually received**, not frames the client
  intended. **PROVEN-CODE** (`Presentation.m:44–71`, `:27–40`).
- `gpu_ms` is the sum of each command buffer's `GPUEndTime − GPUStartTime` over the interval.
  `gpu_load` is that sum divided by elapsed wall time.
- `wait_ms` is the time spent inside `nextDrawable` waiting for a free drawable.
- The HUD (`wolkaraforever/Touch/AKPerformanceOverlay.m`) shows the same numbers.

**Limit 1, and it matters.** `gpu_load` can exceed 1.0 (one sample reads 0.99 with `gpu_ms`
19.1 in a 16.7 ms frame). That is only possible if more than one command buffer is in flight, so
the number is a **sum across overlapping buffers**, not the wall time of one frame's GPU work.
Any argument that divides by it — including the retracted one in §11.4 — is unreliable.
**INFERRED** from the arithmetic.

**Limit 2.** The `--measure-native` path itself allocates a block per frame, adds an atomic, and
takes a lock per presented frame (`Presentation.m:49,54,61,63,29`). Its own cost is small but
non-zero, so a measurement and a normal run are not byte-identical. A proper A/B is named in §9.4.

**Limit 3.** `--sample-native` sets `framebufferOnly = NO` (`Presentation.m:46`) and performs a
full-resolution readback on captured frames. Per Apple, with `framebufferOnly` true the layer
"allocates its MTLTexture objects with only the renderTarget usage flag… you may not sample, read
from, or write to those textures. To support sampling and pixel read/write operations (**at a cost
to performance**), set this value to false." **DOCUMENTED** (§10.1). Therefore **no measurement
taken with `--sample-native` may be used as evidence about steady-state frame CPU.** This
invalidates any earlier reasoning that did so.

---

## 5. The device evidence

Device: iPad Pro 11-inch (M1), 16 GB, 1 TB, panel reported by UIKit as 120 Hz
(`UIScreen.maximumFramesPerSecond`). Host: `local.wolkaraforever.johnklock`, Developer service
mode. Source: `build/device-log/native-guest.log` from this session.

### 5.1 Environment lines

```
[ak] Metal BC: Apple M1 GPU samples BC textures natively, nothing installed
[ak] Metal device Apple M1 GPU: iPadOS answers location=absent locationNumber=absent isLowPower=absent isHeadless=absent isRemovable=absent
[ak] Metal device enumeration: Apple M1 GPU
```
**MEASURED.** Consequence: the BC texture fallback (`BCTextures.m`) is **not installed on this
device**, because the GPU samples BC natively. Any theory that blames per-frame block decoding is
dead. **INFERRED** from the line and from `BCTextures.m:578–581`.

### 5.2 The surface size, both ways

```
[ak] window content size -> 1366x1024 @2x
[ak] Metal drawable 1 acquired: 1366x1024 format=80     (with patch 0023 + the view scale)
[ak] Metal drawable 1 acquired: 2732x2048 format=80     (without it)
```
**MEASURED.** `format=80` is `MTLPixelFormatBGRA8Unorm`.

### 5.3 The frame rate, in world, at the user's settings (in-game `graphicsQuality 1`, in-game `renderScale 0.5`)

```
fps=44.4  gpu_ms=7.9  gpu_load=0.35  wait_ms=0.04  thermal=0
fps=43.7  gpu_ms=9.1  gpu_load=0.35  wait_ms=0.04  thermal=0     (half surface)
min 29.7   median 43.0   max 60.1   n = 66 windows
```
**MEASURED** (the distribution is `grep -oE 'fps=[0-9.]+' | sort -n` over the session, §12.2).

- Halving the surface: 44.4 → 43.7. **MEASURED.**
- Consequence: the frame is not limited by pixels. **INFERRED.**
- The maximum of 60.1 in the distribution is **not** evidence of 60 fps play: the highest samples
  in the session come from the launcher's own UI, not the game (§11.1).

### 5.4 Thermal

```
fps=36.3  gpu_ms=9.0  wait_ms=8.74  thermal=0
fps=36.5  gpu_ms=9.2  wait_ms=13.37 thermal=0
```
**MEASURED.** Note the wait: when it appears, it is 8–13 ms, i.e. the client is waiting for a
drawable. That is the opposite regime from the 0.04 ms samples. Any theory must explain both, and
none of mine does yet. **UNKNOWN.**

### 5.5 Audio (context for the render-thread claim)

```
audio render calls=3984 frames=4079616 nonzero_buffers=3984 errors=0 silence_flags=0
audio route nominal_rate=48000 buffer_frames=1024
audio stream rate=48000 format=0x6c70636d flags=0x9 channels=2 bytes_per_frame=8 bits=32
```
**MEASURED.** `frames / calls = 1024` exactly on every reporting interval, so the device is
delivering 1024-frame buffers at 48 kHz — a 21.333 ms period, 46.9 callbacks per second, on the
audio thread. **INFERRED** from the two numbers.

### 5.6 Event pump: the one measured per-frame layer cost

The pump logs a line every 2 000 polls. The session contains:

```
[ak] pump polls=2000 turns=2000 in_runloop_ms=2315 (1.16 ms per poll)
[ak] pump polls=4000 turns=4000 in_runloop_ms=4617 (1.15 ms per poll)
```

**MEASURED** (§12.3). Read precisely:

- **4 000 polls in a 16-window (80 s) session** = about **50 polls per second**, which at
  43–50 fps is **one poll per frame**. The client polls its event queue once per frame.
- **`turns == polls`**: the 4 ms rate limit never engaged, because consecutive polls are ~20 ms
  apart and the limit therefore always passes.
- **1.15 ms per poll**, of which ~1 ms is the capped run-loop wait and ~0.15 ms is the entry and
  exit of the run-loop turn itself.

**Consequence, and it is the finding this document's own audit produced:** the layer costs
**~1.15 ms of every frame on the frame thread**, which is **~7 % of the 16.7 ms budget**. My
earlier statement that the pump was irrelevant because it was "called fewer than 2 000 times"
was based on the absence of log lines I had not actually counted. **RETRACTED** (§11.6).

**Fix, and its expected size:** a zero-timeout turn (`.0` rather than `.001`) removes the ~1 ms
wait and leaves the ~0.15 ms of run-loop entry, i.e. **~1 ms per frame returned to the client**.
The turn is only needed so UIKit can service deferred gesture and key work; a zero-timeout pass
still performs one pass. Verifiable in one run by the same log line.

---

## 6. The per-frame inventory of the layer (the central claim)

This is the answer to "what can the layer possibly be costing per frame". Each row is
**PROVEN-CODE** unless marked otherwise.

| What runs per frame | Where | Gate | Cost in a normal run |
| --- | --- | --- | --- |
| `CAMetalLayer.nextDrawable`, `presentDrawable:` ×3, `MTLCommandBuffer.commit` | `Presentation.m:122–131` | returns at `:118` unless `--sample-native` or `--measure-native` | **Apple's own IMPs** |
| render-pass and per-draw counters | `RenderDiagnostics.m:22–38` | `--sample-native` only | absent |
| event pump | `AppKit.m` `nextEventMatchingMask:untilDate:inMode:dequeue:` | none | **~50 polls/s = one per frame; 1.15 ms per poll, on the frame thread** (§5.6) |
| `postEvent:atStart:` / `ak_drain` | `AppKit.m` | none | only when an input event exists |
| software cursor positioning | `AppKit.m` `positionCursor` | none | pointer events only |
| BC texture substitution | `BCTextures.m` | installed at `Devices.m:200`, gates at `:559`, and `:578–581` skips a BC-capable device | not installed on this device (§5.1) |
| GPU identity overrides | `Devices.m:203–229` | none | once per device creation |
| audio render wrapper | `Output.m:30–42` | per RemoteIO unit | 46.9×/s on the **audio** thread: 1 indirect call, 3 relaxed atomics, a byte scan that exits immediately (`nonzero_buffers == calls`) |

**Nothing else in `platform/translation/` is on the frame path.** That statement is the result
of the per-file documents in §2, each of which ends with its own per-frame section.

**Falsification test:** name a function in `platform/translation/` not listed above that the
guest would call every frame. If one exists, §6 is wrong.

---

## 7. What the guest is told about time and scale

| API | What the layer answers | Evidence |
| --- | --- | --- |
| `NSScreen.backingScaleFactor` | `UIScreen.mainScreen.nativeScale` = 2.0 | `Screens.m:11` **PROVEN-CODE** |
| `NSScreen.maximumFramesPerSecond` | `UIScreen.mainScreen.maximumFramesPerSecond` = 120 | `Screens.m:13` **PROVEN-CODE** |
| `NSScreen.minimumRefreshInterval` | `1 / 120` = 8.33 ms | `Screens.m:17` **PROVEN-CODE** |
| `NSScreen.maximumRefreshInterval` | a fixed 1/60 | `Screens.m:18`, comment says it is an estimate |
| `-[NSWindow backingScaleFactor]` | `(_uiWindow.screen ?: UIScreen.mainScreen).nativeScale` | `AppKit.m` **PROVEN-CODE** |

The app itself does **not** opt into ProMotion: `CADisableMinimumFrameDuration` appears nowhere
in `platform/` (§12.4). Per Apple's ProMotion guidance, that key is what allows an app to exceed
60 fps. **DOCUMENTED** in §10.2 — *and I could not retrieve the Apple page that states it in this
session, so this is the weakest external citation in the document; treat it as UNKNOWN and verify
it before relying on it.*

**INFERRED:** a client that paces itself from an 8.33 ms refresh interval is being told its
budget is half of what the system is actually delivering (60 Hz). Whether this client does that
is **UNKNOWN**; §9.3 is the test.

---

## 8. The complete list of proven layer defects

Each is a defect independent of the 60 fps question: each is a cost or a wrong answer that exists
today. **PROVEN-CODE** for all nine; the "fix" column is what I intend to change.

| # | Defect | Evidence | Fix | Verified by |
| --- | --- | --- | --- | --- |
| 1 | The app is built **Debug** for the device | `install.sh:41` installs `build/device/Build/Products/Debug-iphoneos/Tolkara.app`; `project.yml:118–120` sets `-O`/`2` for the **tunnel** target only | add `-configuration Release` for play builds | the built product path |
| 2 | Adapters compiled `-O1` | `build_shims.py:38`: `["xcrun","--sdk",SDKNAME,"clang","-target",TARGET,"-isysroot",SDK,"-O1","-g","-fobjc-arc",…]` | `-O2 -flto` | the build log |
| 3 | Logging is synchronous on shared `stderr` | `AKSupport.m:5–16`: `fputs`/`vfprintf`/`fputc` on `stderr`, unbuffered, one `write(2)` per line, `FILE` lock held | lock-free ring + one writer thread | attribution counters read zero on the frame thread |
| 4 | Callers of logging include a 5 s audio reporter and a 2 s pointer counter | `Output.m:25`, `AppKit.m` `moveHoverTo:` report block | same as 3 | same |
| 5 | IOKit property reads build their trace string with tracing off | `Registry.m:51–60` returns at `:52` when tracing is off, but call sites at `:184`, `:195`, `:209`, `:221`, `:225`, `:260` evaluate `className()` (an `IOObjectGetClass` kernel call) and `summary()` (a `lowercaseString` plus fifteen `containsString`) **as arguments**, before the call | wrap the argument construction in `if (tracing)`, as `:246` already does for `IORegistryEntryCreateCFProperties` | `--trace-iokit` off/on A/B on a synthetic guest |
| 6 | Every display-mode query allocates a dictionary | `Displays.m:15` `mode()` builds `{width,height,pixelWidth,pixelHeight,refresh}` with five boxed numbers; `:43`, `:44`, and `DisplayModes.m:24–35` all call it | one cached dictionary, invalidated on `UIScreenModeDidChangeNotification` | allocation count in a loop |
| 7 | Guest threads are created at default QoS | zero `pthread_create` interpositions in `translation/` or `runtime/` (§12.5) | interpose `pthread_create`; `USER_INTERACTIVE` for the render thread, `USER_INITIATED` for workers | `pthread_get_qos_class_np` logged from the guest |
| 8 | The guest is told 120 Hz / 8.33 ms while the system presents at 60 | `Screens.m:13,17`; no ProMotion opt-in (§12.4) | answer 60 Hz / 16.7 ms | a log line of what the guest read |
| 9 | A per-frame block and lock in the measurement path | `Presentation.m:49` (atomic), `:54` (`@synchronized`), `:61` (`addPresentedHandler:` block) | keep, but never measure with it on; an A/B run without it | two builds |
| 10 | **The event pump costs ~1.15 ms per poll and polls once per frame** | §5.6: `pump polls=4000 turns=4000 in_runloop_ms=4617 (1.15 ms per poll)`; `turns == polls` proves the 4 ms rate limit never engages at a ~20 ms poll interval | a zero-timeout run-loop pass instead of `.001` | the same log line: `ms per poll` should fall to ~0.15 |

---

## 9. The open questions, each with the measurement that settles it

### 9.1 Is the client CPU-bound, or is the frame serialised? — the decisive question

We know: frame 22.5 ms, GPU 9.1 ms, drawable wait 0.04 ms. Two readings fit:

- **CPU-bound:** the client's CPU work *is* ~22.5 ms and the GPU overlaps underneath.
  ⇒ 60 fps needs a 26 % CPU cut that no layer change can deliver. **UNKNOWN which.**
- **Serialised:** the client waits for the GPU inside its frame, so frame = CPU + GPU.
  ⇒ overlap would reach ~13.5 ms, inside budget.

**Measurement:** timestamp `nextDrawable` return and the last `commit` of each frame on the
client's thread. That window is the CPU submission time. Compare with the presented interval.
Also count `waitUntilCompleted`/`waitUntilScheduled` calls per frame, and log
`maximumDrawableCount` and `presentsWithTransaction` once.

**Note against the serialisation hypothesis:** Apple documents `maximumDrawableCount` as **3 by
default** (§10.5), so the pool already permits three frames in flight unless the client sets 2.
That weakens, but does not eliminate, the buffering explanation.

### 9.2 Does the client use per-resource residency, heaps, or residency sets?

Apple documents that per-resource residency calls "require CPU overhead for each resource or
heap, which scale up with each one you add" and "apply to a single command encoder", while
residency sets aggregate "at little to no cost" and attach with one call (§10.6). If the client
issues `useResource:usage:` per draw, the layer can coalesce them per command buffer and remove
a per-draw CPU cost **that the layer otherwise cannot touch**.

**Measurement:** a `--trace-metal` run (logs heap creation, `MetalTrace.m:124–131`, and every
buffer and texture creation). **UNKNOWN** today; the captured log contains no trace lines.

### 9.3 Does the client pace itself from the refresh interval?

**Measurement:** answer 60 Hz in `Screens.m` and compare the frame-time distribution. If the
distribution tightens (fewer 29.7 ms outliers), the client was over-scheduling. **UNKNOWN.**

### 9.4 What does the measurement path itself cost?

**Measurement:** the same scene with `--measure-native` and without, where "without" uses the
HUD's own display link rather than the presentation hook. **UNKNOWN.**

### 9.5 Is any interposed function hot at all?

**Measurement:** a compiled-in counter and timer per interposed entry point, aggregated and
dumped sorted. This is the only way to convert every "per call" statement in §2's documents into
a per-frame number. **UNKNOWN**, and it is the cheapest way to falsify the central claim in §6.

---

## 10. External sources, quoted

Each URL below was fetched in this session unless marked otherwise. The sentence quoted is the
one the claim depends on.

### 10.1 `CAMetalLayer.framebufferOnly`
<https://developer.apple.com/documentation/quartzcore/cametallayer/framebufferonly>

> "If the value is true (the default), the CAMetalLayer class allocates its MTLTexture objects
> with only the renderTarget usage flag. Core Animation can then optimize the texture for display
> purposes. However, you may not sample, read from, or write to those textures. To support
> sampling and pixel read/write operations (**at a cost to performance**), set this value to
> false."

Used for: §4 limit 3 — sample-mode measurements are not steady-state evidence. **DOCUMENTED.**

### 10.2 `UIView.contentScaleFactor`
<https://developer.apple.com/documentation/uikit/uiview/contentscalefactor>

> "The scale factor determines how content in the view is mapped from the logical coordinate
> space (measured in points) to the device coordinate space (measured in pixels)… if the scale
> factor is 2.0 and the view frame size is 50 x 50 points, the size of the bitmap used to present
> that content is 100 x 100 pixels."

Used for: the half-resolution experiment and patch 0023. **DOCUMENTED.**

### 10.3 `CAMetalLayer.drawableSize`
<https://developer.apple.com/documentation/quartzcore/cametallayer/drawablesize>

> "By default, a layer creates textures sized to match its content—that is, this property's value
> is the layer's bounds size multiplied by its contentsScale factor."

Used for: why changing the scale (not the drawable size) is the correct lever. **DOCUMENTED.**

### 10.4 `MTLDrawable.presentedTime`
<https://developer.apple.com/documentation/metal/mtldrawable/presentedtime>

> "The property value is 0.0 if the drawable hasn't been presented or if its associated frame was
> dropped."

Used for: the `time <= 0` guard at `Presentation.m:28`. **DOCUMENTED.**

### 10.5 `CAMetalLayer.maximumDrawableCount`
<https://developer.apple.com/documentation/quartzcore/cametallayer/maximumdrawablecount>

> "You can set this value to 2 or 3 only; if you pass a different value, Core Animation ignores
> the value and throws an exception. The default value is 3."

Used for: §9.1 — the drawable pool already allows three frames in flight. **DOCUMENTED.**

### 10.6 `MTLResidencySet`
<https://developer.apple.com/documentation/metal/mtlresidencyset>

> Per-resource calls "Support hazard tracking… Require CPU overhead for each resource or heap,
> which scale up with each one you add… Apply to a single command encoder, which means you need
> to call the methods again for the same resources for each command encoder."
> Residency sets "Require minimal CPU overhead by aggregating allocations at little to no cost
> for each resource or heap… Can attach to a command buffer with a single call, which makes
> residency set's allocations available to all of that command buffer's encoders."
> Also: "residency sets don't track hazards, so you need to account for hazards with fences and
> events… their methods aren't thread-safe."

Used for: §9.2. **DOCUMENTED.**

### 10.7 `MTLCommandBuffer.waitUntilCompleted()`
<https://developer.apple.com/documentation/metal/mtlcommandbuffer/waituntilcompleted()>

> "Blocks the current thread until the GPU finishes executing the command buffer and all of its
> completion handlers."

Used for: §9.1 — the mechanism by which a client serialises itself. **DOCUMENTED.**

### 10.8 Sources that could not be retrieved — stated so they cannot be mistaken for evidence

| URL attempted | Result |
| --- | --- |
| `https://www.apple.com/newsroom/2025/06/ipados-26-brings-new-windowing-system-and-more/` | HTTP 404 |
| `https://www.apple.com/ipados/ipados-26/` | HTTP 404 |
| `https://developer.apple.com/documentation/metal/understanding-gpu-family-architecture` | Not Found |

**No claim in this document rests on iPadOS 26 or iPadOS 27 behaviour.** The user asked
specifically about iPadOS 27; I could not read a single page about it, and I will not describe
it from memory. Everything above is version-independent API documentation that did load.

---

## 11. Retractions — claims I made and withdrew

Kept deliberately, because a reviewer should see what was wrong and why.

### 11.1 "60.0 fps at thermal=2" (withdrawn)
I reported a session holding 60.0 fps into thermal state 2 as evidence that half resolution
worked. The screenshot of that session shows the **launcher**, not the game. The frames being
counted were the app's own UI. The number was real, the attribution was false. **RETRACTED.**

### 11.2 "The launcher broke at half resolution" (withdrawn)
I concluded that setting `contentScaleFactor` had broken the launcher's layout. Screenshots with
the change on and off are identical; the two-column layout is simply wide. The judgement was made
from one glance and was wrong. The change was later restored, and the drawable size still did not
follow, because `contentScaleFactor` set in `loadView` does not survive the view joining the
window. **RETRACTED**, with the surviving fact: the drawable stayed 2732×2048.

### 11.3 Drawable-size patch 0022 (removed)
An earlier patch shrank only `CAMetalLayer.drawableSize` while leaving the scale at 2.0. The guest
drew at half size while its own contract said otherwise, and logging in became impossible because
clicks landed in the wrong place. The patch is deleted; the correct lever is the scale, per §10.3.
**RETRACTED.**

### 11.4 "Frame = CPU + GPU, therefore 74 fps once overlapped" (withdrawn the same day)
I subtracted the GPU time from the frame time (22.5 − 9.1 = 13.5 ms CPU) and concluded the
pipeline was serialised, therefore overlapping would reach 74 fps. **The subtraction is only
valid if the pipeline is serialised — which is the claim it was being used to support.** If the
two already overlap, the client's CPU is 22.5 ms and the GPU runs underneath. §9.1 is the
measurement that distinguishes them. **RETRACTED.**

### 11.5 "No suggestions" (withdrawn)
I told the user there was no way to make it faster, when the correct statement was that the
measured bound excludes only the GPU and the layer, and that the CPU-side questions were
unmeasured. §8 and §9 are the correction. **RETRACTED.**

### 11.6 "The event pump is called fewer than 2 000 times and is irrelevant" (withdrawn)
I asserted this in §6 of an earlier draft without counting the lines that produce it. The
session actually contains `pump polls=4000 turns=4000 in_runloop_ms=4617 (1.15 ms per poll)`:
the client polls **once per frame**, the rate limit never engages, and each poll costs **1.15 ms
on the frame thread**. This is the single largest per-frame cost the layer has been shown to own,
and it was in front of me. **RETRACTED**, and promoted to defect 10 in §8.

---

## 12. Commands that reproduce every code claim

Run from the repository root. Each command's output is what the corresponding §8 row cites.

```sh
# 12.1 Every adapter file is named in a document (expects: undocumented: 0)
python3 - <<'PY'
import os, glob
text = ' '.join(open(d).read() for d in glob.glob('docs/ADAPTERS/*.md'))
missing = [os.path.join(r, f) for r, _, fs in os.walk('platform/translation') for f in fs
           if (f.endswith(('.m','.c','.h','.mm')) or f == 'ldflags')
           and f not in text and os.path.join(r, f).split('translation/')[1] not in text]
print('undocumented:', len(missing))
PY

# 12.2 Frame-time distribution over the captured session
grep -oE 'fps=[0-9.]+' build/device-log/native-guest.log | cut -d= -f2 |
  sort -n | awk '{a[NR]=$1} END {print "min",a[1],"median",a[int(NR/2)],"max",a[NR],"n",NR}'

# 12.3 Event-pump polls and their cost (the session quoted in §5.6)
grep 'pump polls=' build/device-log/native-guest.log
# Expect lines of the form: pump polls=4000 turns=4000 in_runloop_ms=4617 (1.15 ms per poll)
# turns == polls proves the 4 ms rate limit never engaged.

# 12.4 No ProMotion opt-in anywhere in the platform (expects: no output)
grep -rc 'CADisableMinimumFrameDuration' platform/ | grep -v ':0'

# 12.5 No pthread_create interposition (expects: no output)
grep -rn 'pthread_create' platform/translation platform/runtime | grep -v '^\s*//'

# 12.6 Defect 1: the installed product is Debug
sed -n '41p' platform/tools/install.sh
# 12.7 Defect 2: adapter optimisation level
sed -n '38p' platform/tools/build_shims.py
# 12.8 Defect 5: IOKit trace built with tracing off
sed -n '51,60p;184p;195p;209p;221p;225p;260p' platform/translation/IOKit/Registry.m
# 12.9 Defect 6: display mode allocation per call
sed -n '15p;43p;44p' platform/translation/CoreGraphics/Displays.m
# 12.10 Defect 7/8: what the guest is told about scale and refresh
sed -n '11p;13p;17p;18p' platform/translation/AppKit/Screens.m
# 12.11 The per-frame gate in Metal presentation
sed -n '115,132p' platform/translation/Metal/Presentation.m
```

---

## 13. The change list, as it stands

Ordered by dependency, not by size. Items 1–3 are prerequisites for trusting any later number.

| # | Change | Status | Proof it is needed | What would show it worked |
| --- | --- | --- | --- | --- |
| 1 | Instrument the CPU submission window, completion waits, drawable count, `presentsWithTransaction` | **not started** | §9.1 — the decisive unknown | a per-frame number for CPU time |
| 2 | Release build for play | not started | §8.1 | product path; and item 1's number falls or does not |
| 3 | `-O2 -flto` adapters | not started | §8.2 | build log |
| 4 | Async logging | not started | §8.3, §8.4 | frame-thread blocking counter reads zero |
| 4a | **Zero-timeout event-pump turn** | not started | §5.6, §8.10 — ~1.15 ms **per frame**, measured | `pump … (X ms per poll)` falls from 1.15 to ~0.15 |
| 5 | IOKit trace behind `if (tracing)` | not started | §8.5 | call count and time per read, before/after |
| 6 | Display-mode cache | not started | §8.6 | allocation count per 1 000 queries |
| 7 | QoS interposition | not started | §8.7 | `pthread_get_qos_class_np` from the guest |
| 8 | 60 Hz answer | not started | §8.8, §9.3 | frame-time distribution tightens or does not |
| 9 | Residency coalescing | **blocked** on §9.2 | §10.6 | per-draw CPU time |

**What I will not claim:** that this list reaches 60 fps. Items 1–8 remove costs that provably
exist; whether the total is enough is decided by item 1, and if the client's CPU is 22.5 ms it
will not be enough, and the remaining levers are the client's own (addons and UI, which no
graphics setting reduces).

---

## 14. Commit history for this work

| Commit | Contents |
| --- | --- |
| `2acc142` | half backing scale (patch 0023), with the measurement that motivated it |
| `72ca0cd` | event-pump cost measured (< 2 000 polls), retraction of the thermal=2 figure |
| `c3f4cb5` | adapter documentation started (AppKit) |
| `427eea0` | all 60 adapter files documented; per-frame inventory |
| `18bf010` | the throttled-60 design |
| `164d3b0` | the (later withdrawn) serialisation addendum, with residency research |
| `2738a8e` | retraction of §11.4 and the measurement that decides |

This file is the eighth; it contains no claim that is not traceable to a file, a log line or a
URL above.
