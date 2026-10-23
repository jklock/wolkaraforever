# Design: a solid 60 on a permanently throttled iPad

The premise is stated as a constraint, not a hope: **assume `ProcessInfo.thermalState ==
.serious` for the entire session, with performance cores clocked down and default-QoS work
demoted to efficiency cores.** The game's settings are already at their lowest (graphics
quality 1); the client is the client and will not be changed. Everything below is therefore a
statement about the *layer*: what it must stop doing, and what it must make sure the client
gets.

Two measurements define the target:

- median frame 22.5 ms, of which GPU 9 ms and drawable wait ≈ 0 → **~13.5 ms is the client's
  own CPU**, on throttled clocks.
- **minimum 29.7 fps** across 66 windows, with the median at 43 → the frame time is not merely
  high, it is **unstable**, and stability is what "solid" means.

So the design has two goals, in this order: **remove every stall the layer can cause**, and
**give the client's threads the best cores the scheduler will give**. Raising the average is
the client's business; producing the floor is ours.

## Principle 1 — the frame thread is sacred

Nothing in the layer may perform a syscall, take a lock, allocate, or write a file on the
thread that runs the guest's frame. Today four things can:

| What | Where | Why it is a stall risk under throttling |
| --- | --- | --- |
| `fprintf(stderr, …)` | `AKSupport.m:5–16` | `stderr` is an unbuffered `FILE` with a process-wide lock and a `write(2)`. Under throttling a write that took microseconds can take milliseconds, and it holds a lock the logging thread and the guest's thread share. The audio reporter (`Output.m:25`) writes every 5 s; the pointer counter every 2 s. |
| one UIKit turn per poll | `AppKit.m` (`nextEventMatchingMask:`) | a 1 ms run-loop entry on the frame thread. Measured at < 2 000 calls per session, so small — but it is on the frame thread and it is avoidable. |
| a display-mode dictionary | `Displays.m:15` | five boxed numbers and a dictionary per query, no cache. |
| IOKit trace strings | `Registry.m:184,195,209,221,225,260` | `IOObjectGetClass` (a kernel round trip) plus `lowercaseString` and fifteen `containsString` scans per property read, **built even when `--trace-iokit` is off**. |

**Design:** one lock-free ring buffer for all layer logging, drained by a single writer thread
at utility QoS; every existing `AKLog`/`AKLogC` call site becomes a non-blocking enqueue that
drops on overflow. The event pump's UIKit turn moves off the frame thread (it is only needed
to keep deferred gestures alive, which an idle-time timer can do). The two allocation sites get
caches. After this, no layer code path that the client's frame thread enters can block.

## Principle 2 — the client gets the best cores

Guest threads are created by the real `pthread_create` at **default** QoS. Under thermal
pressure, default-QoS work is what the scheduler demotes first; a Mac's render thread has no
equivalent and always competes at the top class. This is the one lever that directly buys
milliseconds rather than removing overhead.

**Design:** interpose `pthread_create` and set the new thread's QoS class to
`QOS_CLASS_USER_INTERACTIVE` for the thread that identifies itself as the main/render thread
and `QOS_CLASS_USER_INITIATED` for the rest; set the same class on the thread that enters the
guest's `main()`. Keep every layer-owned thread (audio reporter, log writer, diagnostics) at
`UTILITY` or below so nothing of ours outranks the game.

## Principle 3 — tell the truth about time

The guest is told `maximumFramesPerSecond = 120` and `minimumRefreshInterval = 8.3 ms`
(`Screens.m:13,16`), while the app itself does not opt into ProMotion (no
`CADisableMinimumFrameDurationOnPhone` in the project), so the system presents at 60. A client
paced for an 8.3 ms frame will over-schedule — extra simulation substeps, extra polling — for a
frame that actually takes 22.5 ms. **This is the one place where a layer answer changes the
client's per-frame work.**

**Design:** report 60 Hz and a 16.7 ms refresh interval, consistently, everywhere the guest can
read them. Under permanent throttling the honest budget is 16.7 ms; telling the client the
truth is how it stops oversubscribing.

## Principle 4 — the layer is not in the budget

- Build the app **Release** for play (`install.sh` installs `Debug-iphoneos` today).
- Compile adapters at `-O2` with `-flto` (`build_shims.py` uses `-O1`).
- Keep every diagnostic hook off by default (already true: `Presentation.m:118`,
  `MetalTrace.m:292`, `ManagedStorage.m:92`, `BCTextures.m:578`).
- Verify, once, with a shim-level profiler, that no interposed function is hot. If one is, that
  is a design bug, not a tuning problem.

## Principle 5 — measure the floor, and attribute the stall

`solid 60` is a statement about percentiles, not averages: **p99 frame time ≤ 16.7 ms**. The
existing instrumentation reports `gaps_over_50ms`; the design extends it to p50/p95/p99 and —
the part that makes it useful — records **which thread held the frame thread up**, by timestamping
every blocking layer call (log write, run-loop turn, kernel round trip). Without attribution the
percentiles say "it stuttered" and nothing else.

## Acceptance criteria

1. p99 frame time ≤ 16.7 ms with the device at `thermalState == .serious`, on the synthetic
   guest workload that reproduces the client's call shape.
2. Zero blocking layer calls on the frame thread, proven by the attribution counters reading
   zero for that thread.
3. Guest threads report `USER_INTERACTIVE` / `USER_INITIATED` in a device log.
4. The guest reads 60 Hz from every time-related API.

## The honest bound

If, after all of this, the client's own p50 is still above 16.7 ms on throttled clocks, then 60
is not achievable by changing the layer, and the answer is a product decision about the client
(more aggressive settings, or a lower target). What this design guarantees is that the layer
is not the reason — and today we cannot say that, because we have never measured it with the
diagnostics off, and the build you are playing is `-O0` with synchronous logging.

---

# Addendum: the arithmetic says the frame is serialised, not slow

Re-reading the measured numbers as a pipeline rather than as a budget changes the target.

```
frame   22.5 ms   (44.4 fps)
GPU      9.1 ms   of that frame, 35 % busy
wait     0.04 ms  for the next drawable
```

If CPU submission and GPU execution overlapped the way a double- or triple-buffered renderer is
supposed to, the frame would be **max(CPU, GPU) ≈ 13.5 ms**, which is *inside* the 16.7 ms
budget — 74 fps, before any optimisation at all. The measured 22.5 ms is **CPU + GPU**, which is
what a serialised pipeline looks like: the client submits, waits for the frame to finish, and
only then begins the next frame's CPU work.

**That is the only arithmetic in this entire investigation that reaches 60 without the client
doing less work.** Fourteen milliseconds of client CPU and nine of GPU, overlapped, is 60 fps on
a throttled M1. So the first question is no longer "how do we make it faster" but **"why is the
client not overlapping submission with the GPU, and is the layer the reason?"**

Three layer-side causes are possible and each is checkable:

1. **Drawable count.** iPadOS allows `maximumDrawableCount` of 2 or 3. At 2, a client can only
   have one frame in flight and the pipeline must serialise. The layer creates the layer's
   configuration in `AppKit.m` (`setContentLayer`/`makeBackingLayer` path) and can set 3.
2. **A completion wait on the frame thread.** If the guest calls `waitUntilCompleted` (or
   `waitUntilScheduled`) inside its frame, the layer can see every such call — it currently
   passes through unobserved. Instrumenting it costs nothing and tells us immediately whether
   the serialisation is the client's design or the layer's buffering.
3. **`presentsWithTransaction`.** Default NO; if set, presentation couples to the transaction
   commit and removes a buffer from the pipeline.

## iPadOS research, and what could not be verified

The Metal documentation that is live contains the mechanism most relevant to a CPU-bound
renderer, `MTLResidencySet` (iPadOS 18+): per-resource residency calls such as
`useResource(_:usage:)` "require CPU overhead for each resource or heap, which scale up with
each one you add" and "apply to a single command encoder, which means you need to call the
methods again for the same resources for each command encoder", whereas residency sets
"require minimal CPU overhead by aggregating allocations" and "can attach to a command buffer
with a single call, which makes residency set's allocations available to all of that command
buffer's encoders" (<https://developer.apple.com/documentation/metal/mtlresidencyset>).

**That is a layer-side CPU reduction on the client's own submission path**: interpose the
per-resource residency calls, accumulate them per command buffer, attach one residency set at
commit. It is safe only for resources the client marked untracked (residency sets do no hazard
tracking and are not thread-safe); tracked resources keep their hazard handling and are left
alone.

**What I could not verify:** Apple's iPadOS 26 and 27 pages returned 404 to this session, so no
claim here rests on a specific iPadOS 27 behaviour. Everything cited above is from documentation
that served successfully. Anything about iPadOS 27 specifically is unverified and is marked as
such rather than asserted.

