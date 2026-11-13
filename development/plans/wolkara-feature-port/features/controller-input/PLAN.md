# Controller input plan

## Outcome

A mapped physical-controller button reaches the native Composer through a bounded
command path without the diagnostic log/panel path delaying it. The game keeps
receiving the button by default. Optional claiming ships only if the feasibility
spike proves it can suppress exactly one selected control before guest delivery.

## Why

Current controller handlers enqueue work to the main queue through
`ControllerInspector`, where diagnostics and UI updates can run before
`InputRouter` sees the mapping. The reported lag is plausible but unmeasured.
The reviewed source does not solve this physical-controller problem; this is a
product-owned fix.

## Design

`ControllerInspector` becomes an observer. A new `ControllerCommandIngress`
accepts only mapped/claimed button edges, assigns a sequence number, holds them
in a bounded FIFO, and schedules one main-queue drain. `InputRouter` remains the
single trigger-semantics owner. Diagnostics get an independent, bounded trace.
No axes, d-pad samples, or repeat samples enter the command FIFO.

## Acceptance

Measure callback → Composer-visible and callback → voice-capture-start on both
required simulators; collect physical timing only when the real controller route
is available. Targets are p95 50/150 ms and maxima 100/300 ms respectively.
Zero FIFO overflows and zero unmapped admissions are required. See
`../../07-completion-spec.md` for measurement boundaries and rollback rules.

## Completion gate

The ingress and Composer entry are feature-flagged independently; turning either
off restores current router behavior without losing saved mappings. All new UI is
localized and accessible. Run the focused controller/voice fixture and
`check_layers.sh`, then `test_voice.sh` on both required simulators. Exercise
Duo in automatic/iOS-on-Duo mode and preserve iPad behavior. When available, use
the physical iPad for matching traces; never call those targets physically met
without them. Put source SHA, feature flags, p50/p95/max, overflow counts and
physical status in PR Proof, keep artifacts local, and update documentation only
with observed results.
