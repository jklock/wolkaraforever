# Input baseline, measured — 2026-11-04 run, and the 2026-11-05 result

> Source log: `build/device-log/native-guest.log` (ignored, not committed — 12,225,493 bytes).
> Device: iPad Pro 12.9-inch (5th generation), iPadOS 27.0.1, Developer service.
> The log is the one the live-playtest review was based on; it was preserved rather than
> overwritten, and every number below is counted from it, not quoted from the plan.

## What the log contains

| Measure | Value |
| --- | --- |
| Bytes / lines | 12,225,493 / 125,934 |
| Span | 2026-11-04 23:16:35.059 → 2026-11-05 00:02:04.960 = **45.5 minutes** |
| `[ak] input: controller…` lines | **12,658** |
| `[input] input: controller…` lines | **12,658** — exactly the same events, written a second time |
| Input log lines in total | **25,316** |
| Input log lines per minute | **556** |
| Controller events per minute (per sink) | **278** |
| Element mix | 5,164 `controller.axis.*`, 7,494 `controller.button.*` |
| Mappings recorded during the run (`mapped … on …`) | **0** |
| Dictation ever active (`dictation=1` / `listening=1`) | **0** |

The two sinks are the same events. `AKCILog`/`AKIRLog` wrote to `AKLog` *and* `WKLog`, and on a
device both reach `native-guest.log`, so every inspected controller event was recorded twice.

And none of it was input the user had asked for: voice was off for the whole 45 minutes, no
mapping existed, and 5,164 of the 12,658 events were stick axes, which no mapping can name.

That is the defect: **25,316 log lines and 12,658 main-queue hops in 45 minutes, for zero
useful input.**

## What changed

`ControllerInspector` no longer decides for itself what to report. `AKInputRouter` publishes an
immutable `AKInputInterest` snapshot and every GameController callback consults it before it
allocates an event, dispatches a block or writes a line:

| State | What is admitted |
| --- | --- |
| voice off, no mapping — the normal state | nothing |
| dictation armed | exactly the mapped element |
| mapping learner armed | every pressable element |
| input diagnostics on | everything, coalesced per display interval |

Continuous inputs (axes, d-pad positions, touch-pad movement) are not pressable, so they are
admitted only in diagnostic mode. Diagnostics write to **one** sink, and the panel's history is
only maintained while the panel is on screen.

## What the 2026-11-05 build measured

Same device, same mode, over a launch that included three self-tests that deliberately drive the
router:

| Measure | 2026-11-04 (before) | 2026-11-05 (after) |
| --- | --- | --- |
| `[ak] input: controller…` | 12,658 | **0** |
| `[input] input: controller…` | 12,658 | **14**, all lifecycle lines plus the deliberate self-test's events |
| Duplicated pairs | 12,658 | **0** |
| Input log lines per minute | 556 | **~1.7** (and those are lifecycle, not events) |

## What this does and does not prove

**Proven:** the double write is gone; the inspector writes nothing for input nobody asked for;
mapped triggers still fire, once, in order (`--selftest=input`, 28/28).

**Not proven, and the reason:** the 2026-11-05 run had **no controller and no pointer attached**
(`inspector: 0 controller(s) connected`, `keyboard=none mouse=none`). So the gate that says
"connected p95 within 2 ms of the disconnected baseline, p99 below 33 ms" has no samples:

```
latency: controller.callback         n=0 p50=0.00ms p95=0.00ms p99=0.00ms max=0.00ms
latency: controller.handoff          n=0 p50=0.00ms p95=0.00ms p99=0.00ms max=0.00ms
latency: pointer.dispatchToNextFrame n=0 p50=0.00ms p95=0.00ms p99=0.00ms max=0.00ms
```

`--selftest=latency` prints those three lines and clears the counters, so each of the three
sweeps is one line in the log. A sweep with `n=0` is reported as `n=0` rather than passing for a
fast result.
