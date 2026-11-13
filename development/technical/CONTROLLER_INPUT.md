# The bounded controller command path

A mapped physical-controller button reaches the Chat Composer through a bounded
command path that nothing diagnostic can stand in front of. The claim the plan
hoped to add - keeping one selected pad button out of the game - is **not
available in this build**, and this note records the measurement behind that
answer rather than the wish.

Related: [input triggers](INPUT_TRIGGERS.md),
[the Chat Composer](CHAT_COMPOSER.md),
[voice](VOICE.md), and the plan this implements at
[`../plans/wolkara-feature-port/features/controller-input/PLAN.md`](../plans/wolkara-feature-port/features/controller-input/PLAN.md).

## What was actually wrong

`AKControllerInspector` observed every element of every connected pad and handed
*each* interested event to the main queue as its own block. That block did
everything at once: the handoff counter, the device mark, the readable line, the
panel redraw, and - last - the call `AKInputRouter` turns into a trigger.

So the diagnostics were in front of the press, and the diagnostics are the part
that can be plentiful. The 2026-11-04 device log held 25,316 controller lines
from one five-minute run. The reported lag was plausible; it was also
unmeasured, and the reviewed source offered no ordering guarantee at all.

## The command path

`wolkaraforever/Input/ControllerCommandIngress.*` accepts **mapped controller
button edges only**:

- it reads the interest snapshot first, exactly as the inspector already did, so
  an unmapped button never becomes a command;
- it assigns a monotonic sequence number and appends to a **sixteen-deep FIFO**;
- it schedules **one** main-queue drain for the whole batch, not one per event;
- the drain delivers to `AKInputRouter`, which remains the single owner of
  trigger semantics - press, push-to-talk, release, learning, duplicate
  suppression all stay where they were.

An axis, a d-pad position, a touch-pad sample, a keyboard key, a mouse click or
a repeated sample **never enters the FIFO**. The ingress refuses them and hands
the edge back, so the caller's ordinary path - which is what those sources have
always used - carries on unchanged.

The inspector's diagnostics still see every event, but only when someone asked
to see them (`diagnosticsEnabled` or the panel is up), and only *after* the
edge has been admitted. A panel redraw can no longer stand between the pad and
the trigger it fires.

### Bounds and counters

| Counter | Meaning | Pass condition |
| --- | --- | --- |
| admitted | a mapped button edge entered the FIFO | - |
| delivered | a command reached the router | equals admitted |
| rejected | repeat or non-press refused | repeats are expected; non-presses are zero for controller sources |
| overflow | the FIFO was full | **zero** |
| drains | main-queue batches | one per batch, not one per edge |

`latency` is a fixed 512-sample ring of *admitted to delivered* milliseconds.
That is the first half of the performance contract's boundary: the pad's
callback to the moment the Composer's own state has been updated - the second
half is reported by the shell, which measures from the admitted stamp to the
adapter's answer.

### Measured on both required simulators

`wolkaraforever/tools/test_controller_input.sh` submits 40 mapped presses and 40
releases through the ingress with `AKInputRouter`'s own delivery wiring, and
prints the two intervals the contract names as far as a simulator can carry
them:

| Interval | Device | p50 | p95 | max | n |
| --- | --- | --- | --- | --- | --- |
| pad callback to delivered (enqueue) | iPad Pro 13-inch (M5) | 0.03 ms | 0.08 ms | 0.16 ms | 80 |
| pad callback to the trigger handler | iPad Pro 13-inch (M5) | 0.12 ms | 0.22 ms | 0.54 ms | 40 |
| pad callback to delivered (enqueue) | iPhone Duo | 0.03 ms | 0.04 ms | 0.11 ms | 80 |
| pad callback to the trigger handler | iPhone Duo | 0.13 ms | 0.16 ms | 0.17 ms | 40 |

Overflows: **0** on both. Admissions: **80** on both, which is exactly the
edges submitted - nothing unmapped entered the FIFO.

Against the contract's targets (p95 <= 50 ms, max <= 100 ms for callback to
Composer visible) the routing half is two orders of magnitude inside them. What
these numbers do **not** include is the Composer's own state update in the
adapter, which only the app can perform; the shell reports that as
`[controller-input] composer open outcome=... ms=...`, measured from the same
admitted stamp. No physical pad exists on a simulator, so these are simulator
numbers and the device targets remain unclaimed until a physical run happens.

### Duo and iPad interface modes

The command path has no layout and no interface-mode branch: it is one queue, fed
by the same canonical element ids in both modes. The mode-sensitive part - the
keyboard card, the Composer card and the toolbar - is exercised in **both**
interface modes by `test_touch_controls_ui.sh --self-test`, which loops the
standard run and `--mobile-interface` (iOS on Duo) on each required simulator,
and the launcher's own Automatic / iPadOS / iOS on Duo card is asserted by
`test_wow_launcher_ui.sh` on both. iPad behaviour is preserved because nothing
on that device's path changed: the same edge reaches the same router with the
same trigger semantics.

## Claim feasibility: no safe hook found

The plan's task 1 asked for a test-only claim for one known pad button, proved
to suppress that button before guest delivery, preserve every other button, and
restore on disconnect and background. **There is no safe seam for that in this
build**, and the answer is a property of the route rather than an opinion:

1. iPadOS hands a physical pad's buttons to **every observer in the process**.
   The guest is an observer this app does not own: it links the real
   GameController framework and reads `GCController.controllers` itself.
2. The three things an app can do to a button are to release the system's
   gesture (`preferredSystemGestureState`), to install a
   `pressedChangedHandler` - one per element, so installing ours would *replace*
   the guest's rather than spare it - and to read its value. None of them
   removes a press from another reader.
3. The one build that could intercept, `translation/GameController`, is a
   standalone adapter that hides **every** pad from every application. It cannot
   claim one button and leave the rest, and it is off by default besides.
4. `AKTouchGamepad` deliberately owns only the virtual device and leaves
   physical pads to GameController and the guest (see `TouchGamepad.h`).

So the switch the completion specification describes is **not offered**, because
a switch that cannot change anything is a promise the app cannot keep. The Voice
page already carries the sentence that says so, in the note under *Keep the game
from seeing it*, and that note is asserted to stay on the page.

What *is* implemented is everything the switch would need except the seam:

- a per-controller, per-element record in `NSUserDefaults` under
  `AKControllerClaims`, in the shape the completion specification fixes:
  `{ "<identity>": { "element": "controller.button.share", "claimed": true } }`;
- default **false** for every migration: a missing record reads as not claimed,
  and asking never writes one;
- `+[AKVoiceSettings controllerClaimIsAvailable]` is `NO`, so
  `-claimElement:device:` refuses with `claim refused reason=no-route element=…`
  and stores nothing;
- every restore path - `disable`, `disconnect`, `background`, `route-failure`,
  `exit` - gives a held element back with its own reason in the log, and keeps
  the saved record for a later re-enable;
- a stored record from a build that *can* claim is read by this one (so a
  preference made elsewhere is not dropped) and reported as
  `claim restore … reason=route-failure`, because this build cannot honour it.

The seam is a single property today: when a route exists,
`setControllerClaimSeamAvailableForTesting:` becomes a real feature flag and the
restore paths are already exercised.

## Log contract

One channel, `controller-input`, written through
`+[AKControllerCommandIngress trace:]` and `traceSequence:`. It is **bounded**:
400 lines per run, then a single `trace budget spent` note and silence, so a long
session cannot turn this channel into the flood the 2026-11-04 log was.

| Event | When | Fields |
| --- | --- | --- |
| `admit seq=… element=… edge=down\|up q=…` | a mapped edge entered the FIFO | sequence, element id, edge, queue depth |
| `drain seq=a..b n=… wait_ms=… drain_ms=… drains=…` | one main-queue batch | range, count, worst wait, block time, drain ordinal |
| `reject reason=repeat\|not-a-press element=…` | refused before admission | reason, element id |
| `drop reason=overflow element=… overflows=…` | the FIFO was full | element id, running count |
| `claim take element=…` / `claim refused reason=… element=…` | a claim was taken or refused | element id, reason |
| `claim restore element=… reason=disable\|disconnect\|background\|route-failure\|exit` | a held button was given back | element id, reason |
| `composer open outcome=opened\|refused\|classic-direct\|unknown ms=…` | the Composer answered a mapped press | outcome, milliseconds from the pad's callback |

`admit`, `drain` and `reject` are the per-edge trail and follow the existing
diagnostics switch; the rest are written whether or not diagnostics are on,
because "was it dropped", "was it given back" and "did the Composer open" have
to be answerable from a support log taken after the fact.

**Never written:** the draft, the words, a transcript, a controller serial or
manufacturer identity, a device identifier, a pairing record. Element ids,
sequence numbers, counts, reasons and milliseconds only. The fixture asserts
that no `controller-input` line contains the device identity it passes in.

## Flags and rollback

| Switch | Default | Off means |
| --- | --- | --- |
| `AKControllerIngressEnabled` | on | the inspector delivers controller edges to the router itself, on the main queue, exactly as before this feature |
| `AKChatComposerEnabled` | on (Composer's own flag) | the Composer is off; a mapped press takes the dictation path it took before |
| Controller claim | unavailable | nothing is held back; records persist but nothing applies them |

No switch removes a saved mapping. Turning the ingress off while a pad is held
still delivers the release, because the ordinary path never stopped being the
fallback.

## Tests

- `wolkaraforever/tools/test_controller_input.sh` - the bounded path, the
  claim record, the restore paths and the log contract, on the matrix iPad and,
  with `SIMULATOR=iphone`, the matrix iPhone.
- `wolkaraforever/tools/test_voice.sh` - the routing and voice rules the ingress
  sits in front of.
- `wolkaraforever/tools/test_touch_controls_ui.sh --self-test` - the adapter the
  Composer lives in, both interface modes.
- `wolkaraforever/tools/test_translation_sim.sh` - the translated adapters,
  including the gamepad and touch controls that share this code path.

## What this does not prove

There is no physical pad on a required simulator, so the timings reported from
this branch are the simulator's: they prove the ordering and the bounds, not a
particular controller. A physical iPad run is the only way to meet the
performance contract's device targets, and it is recorded in
[COMPATIBILITY.md](../../COMPATIBILITY.md) when it happens.
