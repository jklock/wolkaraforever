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

## The model

Today a profile is `source -> target`, one string to one string. It becomes
`source -> action`, where an action is a small, declarative list of steps:

```
Action {
  mode:  hold | tap | toggle | turbo(<hz>)
  steps: [ Step ]
}
Step {
  output:  virtual(element, value | position)   // GCVirtualController
         | key(keyCode, characters, modifiers)  // a real key event in the guest
         | text(string)                         // rare; for completeness
         | layer(name | none)                   // Tolkara's own layer
  when:    onPress | onRelease | after(ms)      // sequences are ordered steps
}
```

Examples, all expressible:

| Physical input | Action | Why it is worth having |
| --- | --- | --- |
| Back paddle | `virtual(LT) + virtual(A)` on press, release in reverse | The game's LT-A ability, from a button WoW never sees |
| Share button | `key(kVK_ANSI_1)` | The player's own action-bar keybind, whatever it is |
| Any face button, while our layer `alt` is held | a different action | Our own layer, independent of the game's |
| Menu, held 400 ms | `tap` semantics: fires once, not on repeat | Long-press without the game seeing a stuck button |
| Stick click | `toggle` a layer | Push-to-talk-style toggles for the pad |

Two rules that keep it honest:

* **Every step is a discrete press a human could make.** No loops, no timing that plays the game.
  `AGENTS.md` forbids automating the application; remapping input is not automating it, and the
  boundary is that a sequence is bounded (≤ 4 steps), fires once per press, and never repeats
  while held. That is written here so a later change has to argue with it.
* **A held action releases in reverse order**, and every output it turned on is turned off when the
  source is released, when the model changes, when capture is turned off, on disconnect, and on
  backgrounding. The existing release machinery already does the last three for single outputs; it
  becomes the same list of outputs.

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
| **1. Model + migration, no behaviour change** | the action store, translated from the existing one, rendered read-only on the page | every existing check stays green; migration test both ways; the three situations unchanged |
| **2. Chords** | `source -> [virtual, virtual]`, press in order, release in reverse | device: paddle → `LT + A` produces both elements in order and releases in reverse; a held chord does not re-fire |
| **3. Keyboard output** | the key channel and the picker | device: paddle → `1` posts exactly one down and one up into the guest, and the guest's own handler sees it |
| **4. Layers, toggle, turbo** | our own modifier state, per-model | device: while the layer is held a mapping resolves differently and reverts on release; toggle survives a re-render and clears on disable |
| **5. Sequences** | bounded steps with `after(ms)` | device: a 2-step action fires once per press, in order, and never while held |
| **6. Docs, matrix, validator** | plan → reference, rows in `validate.sh --device` | `check_controller_targets.sh` grows to compare actions, not just targets |

Phase 2 is the one that answers "a button the game doesn't know does something in the game", and it
should come before the keyboard work: it needs no new channel and it reaches the game's own
existing layers.

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
