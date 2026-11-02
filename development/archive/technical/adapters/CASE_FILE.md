# Tolkara performance case file: the path to stable gameplay

## Decision

The only retained frame-rate log is **the World of Warcraft login screen**.
Its 60 fps samples are not gameplay evidence and must not be used to reject the
reported in-world ~43 fps problem. The operator reports roughly 43 fps in actual
play; the raw in-world capture was not retained, so that number is the current
problem statement, not a verified benchmark.

This file is the performance decision record. A change is allowed only when it
either removes a demonstrable layer cost without changing guest semantics, or a
new in-world capture shows that it is on the limiting path.

## Evidence ledger

| Fact | Scope | Status | Proof |
| --- | --- | --- | --- |
| The retained samples are login-screen samples at 60.0--60.2 fps. | Login UI only | MEASURED | `build/device-log/native-guest.log:14136-14172`; operator identification of the screen |
| The login screen used a 2732x2048 drawable. | Login UI only | MEASURED | `build/device-log/native-guest.log:14103,14117-14118` |
| 4,000 zero-date event polls took 4,617 ms, including 4,000 one-millisecond run-loop turns. | Login UI only | MEASURED | `build/device-log/native-guest.log:14151,14166` |
| In-world gameplay is roughly 43 fps. | Actual gameplay | REPORTED | Operator report; raw capture required |
| CPU submission time, command-buffer wait frequency, IOKit frequency, display-query frequency, thermal progression, and resolution scaling in actual gameplay. | Actual gameplay | UNKNOWN | No retained in-world capture |

The measured AppKit cost is 1.154 ms per zero-date poll in the login capture.
It is real overhead, but neither its in-game call rate nor its share of a 43 fps
frame is known. It cannot honestly be presented as a 43-to-60 fps solution.

## Changes that are justified now

| Change | Why it is safe | What it can prove / improve | Not a claim |
| --- | --- | --- | --- |
| `0024-appkit-event-pump-cost.patch` | A zero-date poll remains nonblocking; it stops deliberately waiting one millisecond. | Removes up to about 1.15 ms for each matching poll, based on the retained login capture. | It does not establish the in-game poll count or guarantee an FPS gain. |
| `0025-release-performance-build.patch` | Uses the normal Release product and raises shim optimisation from `-O1` to `-O2`; no guest behavior changes. | Removes debug-build and intentionally-low-optimisation uncertainty. | It has no measured gameplay delta yet. |
| `0028-apply-guest-backing-scale-to-window.patch` and `0029-report-selected-guest-mode.patch` | The default 1.0 guest scale was already the intended design, but `NSWindow` and CoreGraphics contradicted it by restoring the panel's 2.0 native scale. All three display surfaces now agree. | Corrects the observed 2732x2048 drawable to the intended 1366x1024 guest surface: 1.40 M pixels instead of 5.60 M, a 75% reduction in submitted pixels. | It does not prove that gameplay is GPU-bound or promise a proportional FPS increase; the device log must confirm the candidate's drawable. |
| `0027-iokit-trace-fast-path.patch` | It changes only whether disabled trace strings, summaries, and class-name lookups are built. IOKit calls and GPU identity behavior are unchanged. | Removes deterministic shim allocation/work whenever IOKit is called with tracing off. | Its FPS effect is unknown until frequency is captured. |
| `0037-gate-recurring-diagnostics.patch` | It leaves RemoteIO playback and legacy cryptography unchanged; it bypasses only the optional audio callback wrapper and optional stderr diagnostic. | Removes per-audio-callback atomics/buffer scanning and per-decrypt synchronous logging in ordinary gameplay. | It is a small adapter-cost reduction, not proof of a gameplay FPS delta. |
| `0038-native-memory-fast-path.patch` | It preserves signed executable-page verification and leaves the software-VM route unchanged. | Copies/fills whose destination is outside the guest arena bypass alias and software-VM checks when the software VM is off; signed-image in-arena data writes bypass only the already-unneeded alias work. | Its exact frame-time gain needs an in-scene run. |
| `0039-bypass-inactive-runtime-guards.patch` | It preserves guest-arena, signed-image, software-VM, VM-budget, shader-pause, and explicit trace routes. | Ordinary outside-arena memory mappings use native libc paths; background ulock waits avoid main-thread shader-pump bookkeeping; normal `dlsym` logs are trace-only. | It does not establish the call rate or a gameplay FPS gain. |
| `0026-metal-frame-diagnosis.patch` | It is active only with `--measure-native`; otherwise original Metal method implementations remain in use. | Separates presentation, GPU timing, CPU submission delay, and client-side wait count/duration in an in-world capture. | It is diagnostic, not an optimisation. |
| `0034-metal-anomaly-timeline.patch` | It is active only with `--measure-native`; it records no normal frame and changes no rendering state. | For each actual present gap over 20 ms, attributes elapsed time across drawable acquisition, guest submission, command-buffer scheduling/completion, GPU execution, and presentation. | This is the required causal evidence for a presentation hitch; HUD-only readings remain aggregate evidence. |

## Rejected until evidence changes

| Proposal | Decision | Reason |
| --- | --- | --- |
| Force 60 Hz answers instead of 120 Hz. | DO NOT IMPLEMENT | Current refresh reporting and actual client pacing have not been measured together; lying can make pacing worse. |
| Raise guest-thread QoS or interpose `pthread_create`. | DO NOT IMPLEMENT | The render thread is unidentified; a global QoS change can hurt thermals and responsiveness. |
| Change drawable count, presentation mode, or residency behavior. | DO NOT IMPLEMENT | These alter rendering semantics and have no evidence of a current bottleneck. |
| Cache display dictionaries across a display-mode transition. | IMPLEMENTED | `0031` caches the immutable virtual mode and invalidates it on UIKit's mode-change notification; it cannot change the guest-visible result. |
| Replace layer logging with a new asynchronous subsystem. | DO NOT IMPLEMENT | It is a broad behavior change without a measured logging stall on the gameplay thread. |

## Broad optimization program

Stable gameplay will come from reducing whole classes of work, in this order:

1. **Render fewer pixels consistently.** The repaired 1.0 backing-scale contract
   is the dominant layer-controlled lever: it changes every guest allocation,
   drawable, and display-mode answer from 5.60 M to 1.40 M pixels. Keep this
   default. Do not use a hidden drawable-size override, because it breaks the
   guest's coordinate system.
2. **Keep the normal frame path native.** Production runs must not use
   `--sample-native`, `--measure-native`, `--trace-metal`, `--trace-iokit`, or
   managed-storage diagnostics. Those modes intentionally add hooks, blocks,
   locks, readback, or logging and are for a bounded capture only.
3. **Build and ship as a performance product.** Release plus `-O2` is now the
   baseline. Do not add LTO, QoS interposition, or global thread changes without
   a concrete bottleneck: those are broad changes with stability and thermal
   consequences, not free speed.
4. **Eliminate adapter work only at a semantic boundary.** The event pump no
   longer inserts a deliberate millisecond sleep, and disabled IOKit tracing no
   longer builds strings. Further work belongs here only when it can remove
   allocation, waiting, or a system call while preserving the guest API result.
5. **Treat the remaining budget as client work until the capture says otherwise.**
   If the repaired low-resolution candidate remains near 43 fps with low GPU and
   drawable wait time, the next worthwhile architecture is guest CPU/pipeline
   behavior, not more display tricks. The opt-in Metal timing separates that
   from a serialized command-buffer wait without modifying the game.

### Implemented controls and safeguards

- The launcher offers **Performance** (1024x768, 44% fewer guest-surface pixels
  than Balanced), **Balanced** (1366x1024), and **Quality** (2732x2048). It applies
  only to the next Forever start; it never changes a live session.
- `0032` maps guest shader data for cache lookup and copies it only after a
  cache miss. It cannot change shader bytes or the compiler path.
- Selecting the launcher's **Performance** render profile now applies the
  already-defined Forever performance CVars as part of the same next-launch
  operation: `renderScale 0.75`, foreground cap 60, background cap 30, and
  v-sync. It first creates a complete UI backup; Balanced and Quality restore
  `renderScale 1.0` while retaining the two caps. This is direct GPU/work
  reduction, not a promise that an unmeasured CPU limit disappears.
- `0033` installs Metal diagnostic hooks only for an explicit capture or a HUD
  selected before launch. Ordinary gameplay keeps presentation native.
- `0037` keeps the audio render probe, legacy-crypto decrypt logging, and the
  display-rate link out of ordinary gameplay. Use `--trace-audio-render`,
  `TOLKARA_TRACE_LEGACY_CRYPTO=1`, or `--measure-display-rate` only for a
  bounded capture.
- Background pacing still caps off-screen frames at 5 fps to protect the live
  session. Lifecycle notifications now update an atomic state; foregrounding
  clears its deadline before the first returning frame, so it does not inherit
  a background sleep.

## Required proof: actual gameplay, not login

Use one repeatable in-world location and the same character, graphics settings,
render scale, power state, and thermal starting condition. Do not use a menu,
login, loading screen, or idle city sample.

1. Record a baseline for at least 15 minutes after entering the location. Move
   and fight normally enough to reproduce the problem.
2. Record the candidate with the same protocol. Enable `--measure-native` for
   both runs; it is diagnostic and makes the comparison fair.
3. Retain each raw `native-guest.log`, the exact commit SHA, device model,
   installation mode, and start/end thermal state.
4. Compare five-second windows: median, p1, longest gap, GPU ms, drawable wait,
   CPU submit average/max, and `waitUntilCompleted`/`waitUntilScheduled` count/duration.

A candidate has improved stable gameplay only if the in-world runs support it.
If CPU-submit delay or wait counts are high, investigate guest pipeline stalls.
If GPU time approaches the frame interval, investigate rendering cost. If neither
is high, use the trace counters to identify a hot adapter boundary before making
another change.

## Commands

Run from the repository root after the game has been cleanly quit. The installer
intentionally refuses to replace a live game process.

```sh
# Build and verify that every fork patch applies to the pinned platform.
wolkaraforever/tools/check_layers.sh

# Install the exact candidate, then launch diagnostic gameplay capture.
wolkaraforever/tools/install.sh
wolkaraforever/tools/launch.sh --local-game-startup --measure-native

# After each in-world run, preserve the complete raw log before the next fetch.
wolkaraforever/tools/capture_gameplay_log.sh baseline
wolkaraforever/tools/capture_gameplay_log.sh candidate
```

The next action is not another speculative patch: install this candidate and
collect the first retained **in-world** baseline and candidate logs.
