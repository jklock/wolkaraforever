# Controller output: the plan

Status: **plan, not implemented.** Written 2026-11-04 after the three situations were measured.
Read [`CONTROLLER_MANAGER.md`](CONTROLLER_MANAGER.md) first for the guarantee this has to keep.

## What was researched, and what it changes

**WoW Forever's own scheme is modifier layers.** The controller guide describes LT, RT and LT+RT
as layers over A/B/X/Y *and* the D-pad — 8 inputs × 3 layers = 24 bindings per page — plus three
pages, `LB + RB` for page controls, `LB + D-pad` for party targets, `RB + stick/D-pad` for enemy
cycling, and the right-stick click for pings. Spell binding is done in-game from the spellbook, so
the game owns its own bindings.

That matters because a one-to-one remap can never reach those layers from a button the game has
never heard of. A paddle that becomes `A` is just `A`. A paddle that becomes **LT + A** reaches the
game's LT layer — an ability the game already has a slot for, driven by a button it does not know
exists.

**`GCVirtualController`'s vocabulary is closed.** Apple's API is `elements: Set<String>` of
`GCInput*` constants, `setValue(_:forButtonElement:)`, `setPosition(_:forDirectionPadElement:)`, and
`updateConfiguration(forElement:configuration:)`. There is no way to declare a 13th gamepad button
that a game could bind. So "any net-new button" cannot be a new `GCController` element.

**But the guest accepts more than GameController.** The AppKit adapter already posts real key
events into the guest — `postTextKey:characters:unmodified:modifiers:` is what the on-screen
keyboard uses, and the dictation path uses it too. A key is a first-class output: the game binds
`1`..`0`, F1..F12, whatever it likes, and a controller button that emits `K` is "doing something in
the game" without the game knowing the button exists.

**Conclusion.** The output space is not a list of twelve gamepad targets. It is an **action**, and an
action can drive several outputs of different kinds. That is the whole of step 2.

## Corrected model (2026-11-04, after review)

The first version of this plan proposed chords and sequences - inventing game output to reach the
game's modifier layers. That was wrong, and it is recorded here rather than quietly replaced.

**Tolkara already owns an input layer.** A physical control can be *claimed* by Tolkara instead of
being passed on: the voice trigger system does exactly this today - press the learned button, live
dictation starts, and the game never sees the press. It can do that because the game is only ever
shown the virtual controller, so a button Tolkara keeps is, to the game, a button that does not
exist.

So the second kind of mapping is not "physical -> some exotic game output". It is:

* **pass through** (the default): the control drives the virtual element of the same name, one to
  one, and reaches the game. This is what works today and it must not get slower.
* **claimed by Tolkara**: the control drives a Tolkara action - dictation, an overlay toggle, a
  preset change, anything the app can do - and never reaches the game at all.

The page's job is to let a person choose, per control, which of those it is, per controller model.
That is the whole of step 2, and it reuses the trigger machinery that already exists rather than
inventing an action language.

### The latency rule, and the defect it exposed

A pass-through press must be as fast as it is today. Measured path with capture on, as written
today:

```
framework handler (its own thread)
  -> dispatch_async(main)                     <- a whole main-queue turn, added
  -> reportElement: (main-thread assert, string building, profile lookup, quantiser)
  -> synchronous notification -> adapter -> setValue:
```

The main-queue hop is latency this feature introduced, onto the same queue that services the UI and
the guest's run loop. It is removed: the routing step does its work on the thread the framework
calls it on, under one lock, with no allocation on the hot path, and the adapter writes the value
from there. Everything that is not the hot path - learn, status, the page, replay after a profile
change - stays on main.

It is measured, not asserted: `--selftest=controller-latency` reports the time from the framework
handler being entered to `setValue:` returning, in microseconds, over a run of presses, and the
number is recorded in the validation note. The threshold that matters is that it is the same order
as the touch overlay's own write, which has no such hop.

## The virtual pad, patched

Three concrete changes to the hidden `GCVirtualController`, all inside our adapter:

1. **Declare the largest element set Apple accepts**, not the 12 we use now — the thumbstick
   buttons, Options, Home and the D-pad where the configuration allows them. What is actually
   available must be *measured* on the device first (a self-test that asks the connected controller
   what its profile exposes), because Apple's rules about combining D-pad with a thumbstick are
   undocumented enough that guessing is how the current comment came to be wrong.
2. **Use `updateConfiguration(forElement:configuration:)`** to change an element's image and
   behaviour at runtime, so a configured control can be made visually distinct where the pad is
   displayed.
3. **Stop treating the element table as the vocabulary.** It becomes the *translation* for one
   output kind among several; the key output needs no element at all.

## The bridge for output that is not GameController

A new channel, same shape as the ones that exist:

* App posts `AKControllerKeyNotification` with `{keyCode, characters, unmodified, modifiers,
  pressed}`, synchronously on the main thread.
* The AppKit adapter observes it and calls the host's `postTextKey:characters:unmodified:modifiers:`
  (press) / the matching release, which is the same path the on-screen keyboard already uses.
* The guest sees an ordinary key event. Nothing in the app touches AppKit; nothing in the adapter
  decides policy. Same split as the route channel.

If the adapter is not loaded (no guest session) the notification is dropped, which is correct: there
is nothing to type into.

## The page

`Controller Manager` gains a second section per controller model, replacing the flat
`source -> target` list:

* **Physical control** rows, grouped and named as the pad names them (`Back paddle`, `Share`).
* Each row shows its action as chips: `LT + A`, `Key 1`, `Hold 400 ms`, `→ layer alt`.
* **Learn**: press the physical control (existing flow), then choose:
  * *Gamepad* — the elements the pad can drive (grid);
  * *Chord* — pick modifiers, then a button; the summary reads `LT + A`;
  * *Keyboard* — a key picker, with modifiers;
  * *Tolkara* — layer, toggle, turbo;
  * *Clear*.
* **Test** — press the physical control in the page and see the action's chips light up. Driven by
  the same route/key notifications the adapter consumes, so the test measures the real path.
* The disclosure keeps saying what it says now: identical models share a profile.

## Migration

The stored profile is `WolkaraForeverControllerProfile.<identity>` → `{source: target}`. New store
is `WolkaraForeverControllerActions.<identity>` → `{source: [step...]}`, with a version marker.

* Reading: if the new key is absent, translate the old one — every `source -> target` becomes a
  single-step `virtual(target)` action. A user's mappings survive untouched.
* Writing: only the new key. The old key is left in place, unread, so a downgrade still finds
  something rather than nothing.
* A test asserts both directions: old → new translation is identity on the three situations, and a
  round trip of the new format is stable.

## Phases, each shippable and each tested

| Phase | What it adds | How it is proven |
| --- | --- | --- |
| **0. The hot path** — DONE | routing runs on the framework's thread through a prebuilt table, with no profile lookup or main-queue hop | `--selftest=controller-latency`: **median 1.2 us, worst 59.5 us**, 600 samples, on the iPad. The device gate rejects any sample at or above 1 ms. Three situations 8/8 and routing 22/22 unchanged |
| **1. Claiming** | a control can be claimed by Tolkara instead of passed through, per controller model, reusing the trigger machinery | device: a claimed control starts dictation and produces **no** route notification; an unclaimed one passes through unchanged |
| **2. The page** | per-model list of physical controls, each showing *pass through* or *Tolkara action*, with learn and reset | launcher fixture: rows, learn, reset, the two states, German, no game-file write; device self-test drives it |
| **3. More Tolkara actions** | the claim target is a list rather than dictation alone | each action asserted once on the device |
| **4. Docs, matrix, validator** | plan becomes reference; rows in `validate.sh --device` | `check_controller_targets.sh` compares the claim list as well |

Phase 0 comes first because it is a defect in what is already shipped, not a feature. Everything
after it adds choice, not latency: a claimed control takes the existing trigger path, which does
not touch the virtual controller at all.

## Risks, and what each one costs if it goes wrong

* **Stuck output.** A chord that half-releases leaves a trigger held. Mitigated by the single
  release list every existing path already uses, and by a device check that presses and releases
  every chord in the table.
* **Key auto-repeat.** Holding a key output would repeat into the guest. `mode: hold` must post one
  down and one up, not a stream.
* **Double layers.** If a user maps a physical trigger to nothing and a paddle to `LT + A`, the game
  sees one layer, correctly. If they also leave LT mapped, they get the layer twice — the page must
  show the conflict rather than silently emit both.
* **Migration loss.** A user's existing mappings must not vanish. That is why writing the new key
  never deletes the old one, and why the migration is a test rather than a comment.
* **The profile growing into an automation tool.** The bounds above (≤ 4 steps, once per press, no
  repeat) are the line. Anything beyond them is a different feature and needs a different
  conversation.

## Explicit non-goals

* No coaxing a physical pad into looking exactly like a Xbox pad. That is a layer over something
  that already works, and the point is to be better than the game's default.
* No per-application profiles in this phase: identity stays per controller model, as it is now.
* No writing `GamePadConfig_*.json`, `Config.wtf`, or any game file. Actions are Tolkara's, and the
  game's own bindings stay the player's.
* No touch-input remapping in this phase; the producers are still touch and physical, the vocabulary
  is what grows.

## What must be measured before phase 1 is called done

1. Which elements a connected `GCVirtualController` actually exposes, on the device — not from
   Apple's documentation, which does not say.
2. That a key posted through the new channel reaches a guest and fires its handler — the same shape
   as the routing check that already exists.
3. That the three situations (`--selftest=controller-situations`) are still green with the action
   store underneath them, before any new behaviour is added.
