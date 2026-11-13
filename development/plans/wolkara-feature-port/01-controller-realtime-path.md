# Phase 1 — Realtime controller path

## Outcome

A mapped physical controller press reaches the product command owner with bounded
work, known latency and optional exclusive ownership.  Diagnostics cannot cause
ordinary play to stall.

## What changes for a player

Today a mapped pad button is a listener layered beside the game: the game still
receives the button, and the listener's timing is invisible.  After this phase,
the Voice/Composer page presents a per-controller choice:

- **Listen only** — preserves today’s behavior; the game and Composer both see
  the control.
- **Use for Composer** — the control is claimed before guest delivery while the
  feature is enabled; the page identifies the exact controller/model and offers
  Restore immediately.

The app shows recent command timings and a clear “not measured yet” state rather
than presenting a generic latency number as evidence.  It does not promise an
audio-recognition result at button-down; it makes the routing delay measurable
and bounded.

## Why the architecture must change

The current `AKInputInterest` optimization avoids work for uninteresting input,
but an admitted event still crosses from a GameController callback into the main
queue through `ControllerInspector`.  The inspector also owns diagnostics and a
panel.  Those responsibilities are compatible for a debug tool but not for the
control a player presses while a game renders.  A command must not wait behind
axis logging, string formatting or panel history.  Conversely, UIKit and speech
must remain main-owned, so a background direct call is not a valid optimization.

## Concrete contracts

- An edge is `(controller identity, canonical element, down/up, monotonic time,
  sequence)`.  The ingress never accepts axes, d-pads or repeats as commands.
- The mailbox capacity is a named constant, visible in diagnostics.  Overflow
  drops no release silently: it marks the command path failed, releases any
  claimed control and reports a recoverable error.
- A drain handles edges in sequence order and is the only caller of Composer
  open/finish actions.  Multiple physical samples for a held control produce one
  down and one up.
- Claim configuration is consulted at the point the physical event would become
  a guest event.  It cannot be implemented by suppressing the inspector after
  guest delivery.
- Diagnostic mode is observational.  It cannot alter the claim snapshot or
  change whether a command is delivered.

## Implementation detail

Keep `AKInputInterest` as the lock-free-ish admission vocabulary, but create a
second immutable `AKControllerCommandSnapshot` from `VoiceSettings` and Controller
Manager state.  Handler installation in `ControllerInspector` calls ingress first
for a matching physical button.  The inspector receives a copied observation only
when diagnostics/panel policy requests it.  This deliberately inverts the current
dependency: command routing is primary; inspection is optional.

The main-queue drain uses one scheduled flag guarded by the mailbox lock.  It
removes a batch, clears the flag only after checking for new work, and calls the
existing `InputRouter` compatibility API initially.  This lets phase 1 compare
old/new trigger outcomes before phase 2 substitutes Composer actions.

## Failure and rollback behavior

- Unsupported controller/profile: show unavailable and leave guest input intact.
- Claim application failure: retain listen-only mapping, do not partially claim.
- Disconnect/background/route reset: flush mailbox, synthesize local release
  only for Composer state, restore guest delivery, and never manufacture a game
  press/release.
- Timing instrumentation failure: omit the sample; never block a command to
  collect a number.
- Feature flag off: continue current Inspector → Router behavior unchanged.

## Current path and failure surface

`ControllerInspector.m` installs GameController handlers, performs an
`AKInputInterest` lookup, then dispatches admitted events to the main queue.
On main it records diagnostics and invokes `InputRouter.onInput`; `InputRouter.m`
allocates an `AKInputEvent`, updates press state and invokes voice callbacks.

This is correct but combines three different jobs:

1. GameController callback ingress;
2. command routing for the one mapped control; and
3. inspector logging/panel rendering.

The captured session has 4,205 raw input lines and no trigger record.  It is not
a measurement of the reported mapped press, but it proves that broad diagnostics
can generate a large main-queue workload.  `InputInterest` already provides the
right first gate; it must become a hard hot-path boundary.

## Design

### A. Extract ingress from diagnostics

Add `wolkaraforever/Input/ControllerCommandIngress.{h,m}` and map it to
`launcher/Input/` as an overlay.  It owns:

- an immutable, atomically swapped claim snapshot: device identity, canonical
  element, press/toggle pattern and whether the game receives it;
- a fixed-size command mailbox, carrying only edge events for claimed controls;
- per-device/element sequence numbers, so down/up order survives queue handoff;
- counters for rejected, coalesced, overflowed and delivered events.

`ControllerInspector` remains the diagnostic observer.  It consults the same
snapshot but must not be necessary for delivery.  Its continuous axes retain
their existing display-interval coalescing and are never put in the command
mailbox.

### B. One UI-owner handoff

GameController callbacks may arrive off-main, while UIKit and the Composer are
main-owned.  The ingress records an edge and schedules at most one main-queue
drain.  The drain consumes FIFO press/release edges, with a bounded capacity and
an explicit overflow verdict; it never performs file I/O, logging or view work.

Do not create one `dispatch_async` block per axis or controller sample.  Do not
move UIKit or Dictation onto a background queue.

### C. Explicit controller claim

Extend `VoiceSettings` with a per-device `claimFromGame` choice for controller
elements.  Unlike the current `takeButtonFromGame`, it is meaningful for a pad:
the Controller Manager/adapter boundary must know which physical element to
withhold before it becomes a guest event.  Default is **off**, preserving current
behavior.

Implement the claim through the product's Controller Manager/virtual-controller
route, not by dropping unrelated input.  A claim must release immediately when
voice/chat is disabled, mapping changes, device disconnects, app backgrounds or
the user toggles it off.  Its UI states are: listening only, claimed, unavailable
on this controller, and restored.

### D. Real timing

Add `AKCommandTimingSamples` with timestamps for:

`callback → ingress accepted → main drain → Composer opened → dictation listening
→ final transcript → guest text injected`.

Expose p50/p95/p99/max and sample count in Controller diagnostics.  Keep it
separate from `InputRouter.pointerTiming`, which measures pointer-to-next-frame
rather than command delivery.

## Files to change

| Area | Change |
| --- | --- |
| `wolkaraforever/Controller/ControllerInspector.*` | Make it an observer; remove command-path dependence on its panel/log path. |
| `wolkaraforever/Input/InputInterest.*` | Extend snapshot with claimed-edge admission while retaining diagnostic/learning modes. |
| `wolkaraforever/Input/InputRouter.*` | Consume ingress edges; keep trigger parsing/state semantics as the compatibility layer. |
| `wolkaraforever/Input/Trigger.*`, `Voice/VoiceSettings.*` | Versioned persistence for controller claim preference; migrate no existing setting to claimed. |
| `wolkaraforever/Controller/*` and associated AppKit patch | Carry only user-selected physical controls through the Controller Manager route. |
| `wolkaraforever/Shell/SelfTest.m` | Publish timing/counter self-test results without claiming physical-device proof. |
| `wolkaraforever/Voice/tests/test_voice_app.m` | Synthetic ordered edge, overflow, disconnect and restore coverage. |

## PR sequence

1. Measurement/counters only; no behavior change.  Capture the physical-iPad
   symptom with diagnostics disabled and with a bounded trace enabled.
2. Ingress/mailbox while still mirroring events through the existing router;
   prove identical trigger behavior.
3. Controller claim preference and restore lifecycle.
4. Wire the Composer trigger from phase 2.

## Acceptance

- Unmapped controller and axis events cause no command mailbox work.
- A claimed press/release is ordered exactly once; disconnect/background releases
  ownership and no key remains held.
- Diagnostic panel off: no per-event log or panel block.  Diagnostic trace has a
  stated bounded rate and cannot change command timing beyond its documented cost.
- `test_voice.sh`, Controller Manager suite, `check_layers.sh`, and focused
  simulator tests pass on iPhone Duo and iPad Pro 13-inch (M5).
- Device Hub, when available, reports timing for an actual mapped press, both
  unclaimed and claimed. Never infer that physical result from simulator work;
  leave the device on its normal home screen with the app running.
