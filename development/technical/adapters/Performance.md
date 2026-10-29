# Performance: historical hypotheses, not an implementation authority

> **Superseded for performance decisions by [CASE_FILE.md](CASE_FILE.md).**
> The numerical in-world samples in this document do not have a retained raw
> gameplay log in this checkout. The retained 60 fps log is the login screen.
> Treat the analysis below as hypotheses only; do not implement its proposed
> changes without the in-world measurement protocol in the case file.

This document assembles the per-frame findings from every adapter document. It states what
is **measured**, what is **known from the source**, and what is still **unmeasured** — the
three categories are kept apart deliberately, because earlier reports in this project mixed
them and were wrong.

## 1. The complete per-frame inventory of the layer

Every place in `platform/translation/` that can execute once per presented frame:

| What | Where | Gate | Measured / known |
| --- | --- | --- | --- |
| `CAMetalLayer.nextDrawable`, `presentDrawable:` ×3, `MTLCommandBuffer.commit` | `Metal/Presentation.m:122–131` | `--sample-native` or `--measure-native`; returns at `:118` otherwise | **Apple's own IMPs when unflagged.** Verified in source: the install function returns before any replacement |
| render-pass / per-draw counters | `Metal/RenderDiagnostics.m` | `--sample-native` only | not on the frame path unflagged; ~3 000 allocations per 1 000-draw pass when on |
| event pump | `AppKit/AppKit.m` (`nextEventMatchingMask:`) | always | **measured: < 2 000 calls in a 330 s session** |
| `postEvent:` / `ak_drain` | `AppKit/AppKit.m` | always | only when an input event exists |
| software cursor positioning | `AppKit/AppKit.m` (`positionCursor`) | always | pointer events only |
| BC texture substitution | `Metal/BCTextures.m` | installed always (`Devices.m:200`), gates internally at `:559`/`578–581` | nothing on a device that samples BC (every M-series iPad) |
| GPU identity overrides | `Metal/Devices.m:203–229` | always | once per device creation |
| audio render callback wrapper | `AudioToolbox/Output.m:30–42` | `--trace-audio-render` only | The wrapper does atomics and scans output buffers on the audio thread, so ordinary gameplay installs the guest callback unchanged. |

That is the whole list. **There is no per-frame code in AppKit input handling, in
CoreGraphics, in IOKit, in Security or in GameController.** Normal gameplay also
does not retain the audio render probe, per-decrypt legacy-crypto logging, or the
passive display-rate link; those are explicit diagnostics.

## 2. What the measurements say

From the layer's own instrumentation on the device (presentation timestamps and Metal
counters), at the user's settings — in-game `graphicsQuality 1`, in-game `renderScale 0.5`:

```
GPU 9.0–9.2 ms      wait 0.04–13.4 ms      fps median 43.0 (min 29.7, max 60.1, n=66)
```

and, across two sessions that differed only in the surface size:

| Surface | In-world fps |
| --- | --- |
| 2732 × 2048 (native) | 44.4 |
| 1366 × 1024 (half) | 43.7 |

**Halving the pixel count changed the frame rate by less than the run-to-run variation.**
The GPU is a third of the frame and the drawable is not the bottleneck, so the remaining
~13.5 ms of a 22.5 ms frame is the client's own CPU work.

Two consequences follow, and they are the reason the earlier attempts — drawable size,
backing scale, present path — could not have worked:

1. Any change that reduces pixels cannot help while the GPU is idle a third of the time.
2. The layer's per-frame contribution is, by the inventory above, **one branch** in the
   common case. It cannot be manufacturing 13.5 ms.

## 3. What is *not* measured — stated plainly

- **IOKit call frequency.** The captured session never passed `--trace-iokit`; the log has
  zero `IOKit ` lines. The cost per call is known from the source (`Core.md`: 4–5 kernel
  round trips plus string formatting per property read, **with the trace string built even
  when tracing is off**), but whether the guest calls it per frame is unknown.
- **Display-query frequency.** `mode()` (`CoreGraphics/Displays.m:15`) allocates a
  five-entry dictionary on every call and is reached by every display query. A renderer that
  asks once at start-up pays nothing; one that asks per frame pays four allocations per two
  calls. Unknown for this client, because the game can no longer be launched.
- **The client's own thread topology and QoS.** Guest threads are created by the real
  `pthread_create` at default QoS. On a throttled iPad, default-QoS work is what the
  scheduler demotes first; a native Mac app's render thread is user-interactive. This is the
  one systemic lever the layer could influence and it has never been measured.

## 4. About throttling

What the logs show is the *effect*: the client's own `thermal` field reaches 2
(`ProcessInfo.ThermalState.serious`, the documented third of four states) within a few
minutes of play, and fps drops with it. What the layer can and cannot do about that is a
fact about iPadOS, not a matter of cleverness:

- **It cannot prevent it.** Thermal state is the system's answer to sustained power draw.
  No API in an app can raise the limit, and nothing the layer does to scheduling changes the
  heat being produced by the same work.
- **It can only reduce the work**, and the inventory says the work is in the client, on the
  CPU, not in the layer and not on the GPU.
- **The one lever that is genuinely ours** is QoS and core placement for guest threads: if
  the client's render thread runs at a class the scheduler demotes under thermal pressure, it
  spends part of its frame on efficiency cores. That is measurable, costs nothing, and is the
  next experiment worth running — but it cannot be run against the game any more, only
  against the adapter's own synthetic guest.

## 5. What I would do next, in order, with the proof each step needs

1. **Instrument the shim boundary once, generically.** A compiled-in counter and timer per
   interposed entry point, aggregated and dumped sorted. This converts every "unknown
   frequency" in §3 into a number in one run, and it is the only way to know whether the
   layer holds any of the 13.5 ms.
2. **Measure the guest's thread QoS and core placement**, and compare against a Mac running
   the same synthetic workload.
3. **Fix only what those two show.** The candidates ranked by expected size are QoS, IOKit
   diagnostic strings, display-mode allocation, and `trace()`'s argument construction.
4. **Re-derive the frame budget** with the instrumentation off, because `--measure-native`
   itself adds a block allocation and two atomics per frame.

**No step here claims a frame-rate improvement yet.** The documentation proves the layer is
small on the frame path; it does not prove the client's 13.5 ms is irreducible, and with the
beta closed only a synthetic guest can be used to find out.
