# Controller output: what the game gets, and what Tolkara keeps

Status: **shipped.** This describes what the Controller Manager does now, not a
proposal. Read [`CONTROLLER_MANAGER.md`](CONTROLLER_MANAGER.md) first: it states
the three situations and the guarantee this serves.

## Two states, one owner each

While routing is on, every control of a connected model is in exactly one of two
states. Which state it is in is decided by whoever owns the answer, and only by
them:

* **Pass through** — the question *"does the game see this control?"* is answered
  here.
* **Withheld** — the question *"what does this control do instead?"* is answered
  by the feature that uses it. Today that is Voice & Input for dictation. This
  feature never stores an answer to it.

**Pass through** is the default for every control in the standard layout. The
control drives the virtual control of the same name, one to one, and that is what
the guest sees: a button is a button, a trigger is a trigger with its analog
value, a stick is a position, the D-pad is a position. The work happens on the
thread GameController called the handler on, with one recursive lock and a
prebuilt table, and is measured at a median of about a microsecond (see
`--selftest=controller-latency`). There is no main-queue hop anywhere on this
path.

**Withheld** means the control is removed from the guest's route table entirely:
it produces no route notification at all, so the game cannot see it. It exists
because of the second half of the guarantee — while routing is on the guest is
only ever shown the virtual controller, so a control Tolkara keeps is a control
the game does not have. That is what makes it useful.

## Where withholding comes from

Not from this feature. `AKTrigger` already stores, per controller model, which
input starts dictation and how (`saveForDevice:defaults:`,
`savedTriggerForDevice:defaults:`, `forgetTriggerForDevice:defaults:`), and
`AKInputRouter` already fires it. The Controller Manager reads that record and
withholds whatever it covers:

```objc
for (NSString *source in [manager withheldSourcesForIdentity:identity])
    map[source] = AKControllerTargetNone;
```

Consequences that follow from having one record instead of two:

* The voice page and the Controller Manager cannot disagree. There is nothing to
  reconcile because nothing is duplicated.
* The row on the Controller Manager page says *withheld — dictation
  (push-to-talk)*, and names the page that owns the choice. It does not offer to
  make that choice itself.
* Choosing a target for a withheld control is still allowed, and that is how a
  user takes the control back for the game — but it takes effect only once the
  voice page releases the trigger. Both pages then show the same thing.
* A second behaviour arrives as a second trigger-owning feature, not as a second
  table here.

The profile stores no claim, no action name and no list of behaviours. Its record
is the mapping (`version`, `map`) plus what has been discovered about the model
(`observed`).

## Discovering the controls

There is no model list. A pad's controls are whatever iPadOS reports plus
whatever the pad turns out to send, and the target side is fixed by what the
virtual controller offers — twelve targets, checked by
`check_controller_targets.sh`.

* **From the framework.** The manager enumerates each connected `GCController`'s
  `physicalInputProfile` — buttons, axes, D-pad directions — and names each one
  through `AKInputElementForController*`. Anything iOS reports becomes a row,
  whether or not the default table has heard of it.
* **From events.** A control that never appears in the profile but does produce a
  value or a position is discovered the first time it arrives. That is the only
  way some extra buttons can be mapped at all. The first sighting costs one set
  lookup on the hot path; the work behind it — storing it, rebuilding the route
  table, redrawing the page — happens on main exactly once for that model, never
  again per event.
* **Remembered.** Discovered controls are stored per model in `observed`, so the
  row survives a restart and another pad of the same model gets the same table.
  Reset restores the default layout and keeps the observations: a pad has the
  buttons it has.
* **Marked as such.** A discovered row is shown as *discovered* rather than
  *pass through*, so it is clear the row came from the pad and not from the
  default layout.

A discovered control routes like any other: it is in the table the moment it is
seen, so it can be mapped immediately.

## What is deliberately not here

Only behaviours that already exist behind an app-owned interface belong on the
other side of withholding, and only if taking the input does not change product
behaviour. Everything else is excluded by that rule, not deferred:

| Behaviour | Why it is not withheld |
| --- | --- |
| On-screen keyboard / gamepad visibility | Lives in the AppKit adapter as part of the touch overlay's own layout state. Driving it from a controller would change what the overlay does while the user is using it, and the adapter exposes no app-owned entry point for it. |
| Performance overlay | Same: adapter-side HUD state, changed through the gamepad layout screen, not through an app interface. |
| Voice test, add-on pages, launcher pages | Screen navigation, not an input behaviour. Invoking pages from a pad press is a different feature with its own questions — which page, and what happens to a running session. |
| Screenshots, Spotlight, other system gestures | Not ours: iPadOS owns them, and the product's rule is that a feature never starts because an unrelated system press happened. |
| Anything that types or presses game keys | Not input remapping. The boundary in `AGENTS.md` is that we adapt input, never automate the application. |

A behaviour joins this table when it has an app-owned interface and a test
showing the withheld control produces no route notification — not before.

## Where the model is stored

`WolkaraForeverControllerProfile.<identity>`, version 2:

```json
{ "version": 2,
  "map":      { "controller.button.a": "virtual.button.a" },
  "observed": ["controller.button.paddle"] }
```

* **Version 1 migrated**: a bare `source -> target` table becomes version 2 with
  those targets as explicit pass-through and nothing discovered — nothing a v1
  user chose is lost, and nothing they never had is invented.
* **A version 2 table written by the earlier build** may carry an `actions` key.
  It is ignored: withholding now comes from the trigger the voice page owns, so
  no dangling reference to a behaviour this feature no longer stores is left
  behind.
* **Unknown versions and malformed values** fall back to the complete default 1:1
  layout rather than half-applying, so a corrupt table cannot leave a control
  dead.
* **Reset** restores the default layout, clears remaps and keeps observations.
* **One target, one source**: binding a source to a target unmaps whoever else
  drove it, so two controls cannot fight over one virtual button. Binding a
  withheld control is allowed and takes effect when its trigger is released.
* Profiles are per *model* (`vendor` + `product category`), so two identical pads
  share one. The page says so.

## Invariants

1. A withheld control produces no `AKControllerRouteValue` or `...Position`
   notification, ever.
2. Withholding is read from the feature that owns the behaviour, never stored
   here; the profile contains only `version`, `map` and `observed`.
3. Pass-through stays on the framework's callback thread. Discovery may dispatch,
   because it happens once per model, not per event.
4. Releases are symmetric: releasing, disabling routing, disconnecting,
   backgrounding, resigning active, a profile change and a reset each leave no
   held virtual value — and no dictation session this feature started.
5. The hot path never reads a mutable profile object, never touches defaults,
   never builds a table and never hops to main. Tables are built on main and
   published whole; discovery's main-queue work is a first-sighting event.

## Where each is proven

| Claim | Test |
| --- | --- |
| a withheld control routes nothing and the withholding comes from the voice trigger; removing it restores the route; the profile stores no claim | `test_controller_manager.sh` — `CONTROLLER_MANAGER_WITHHOLD_PASS` |
| an extra button the pad produces becomes a stored, discovered row | same suite |
| a v1 table still loads as pass-through with nothing discovered | same suite |
| reset restores the layout and keeps observations | same suite |
| the page's row states, its bind handler and both languages | `test_wow_launcher_ui.sh` |
| every target the page offers can be written by the adapter | `check_controller_targets.sh` |
| pass-through direct, analog, sticks, D-pad, release, latency | `--selftest=controller-routing`, `--selftest=controller-latency` |
| the three situations, on the device | `--selftest=controller-situations` |
