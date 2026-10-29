# Historical design hypothesis: a solid 60 on a permanently throttled iPad

> **Not an approved implementation plan.** The 43 fps, GPU-time, and thermal
> premises below lack a retained raw in-world capture. The retained 60 fps log
> is the login screen. [CASE_FILE.md](CASE_FILE.md) is authoritative: measure
> actual gameplay before changing QoS, refresh reporting, or rendering behavior.

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

**Correction (same day).** The reasoning in this section is not sound, and it is left here
struck through in effect rather than deleted, because the mistake is instructive.

I wrote that a 22.5 ms frame with a 9.1 ms GPU implies "client CPU = 13.5 ms", and therefore
that the frame must be CPU + GPU serialised, and therefore that overlapping them would reach
74 fps. **The subtraction is only valid if the two are serialised — which is the thing it was
supposed to prove.** If they already overlap, the frame time *is* the CPU time (22.5 ms, the
bottleneck) and the GPU's 9.1 ms runs underneath it. Both readings are consistent with every
number we have. So there is no evidence yet that the pipeline is serialised, and no basis for
the 74 fps figure.

Apple's documentation also removes one of the three candidate causes: `CAMetalLayer`
`maximumDrawableCount` is **3 by default** ("You can set this value to 2 or 3 only… The default
value is 3", <https://developer.apple.com/documentation/quartzcore/cametallayer/maximumdrawablecount>),
so unless the client sets 2 the pool already allows three frames in flight.

**What would settle it, and it is one measurement.** Timestamp the frame on the thread that
runs the client: `nextDrawable` return → last `commit`. That window is the CPU submission time.
Then compare it with the presented-frame interval:

- window ≈ interval → the CPU is the bottleneck and the GPU is already overlapping; no layer
  change reaches 60, because the client's own CPU needs 22.5 ms.
- window ≈ interval − 9 ms → the submission is waiting on the GPU; then **something is
  serialising**, and the candidates are a client `waitUntilCompleted` (Apple: "Blocks the
  current thread until the GPU finishes executing the command buffer and all of its completion
  handlers"), `maximumDrawableCount = 2`, or `presentsWithTransaction`.

That measurement is the first item in the change list, because every other decision depends on
its result.


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
