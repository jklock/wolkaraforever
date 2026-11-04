# Controller output: pass through, or claimed by Tolkara

Status: **shipped.** This describes what the Controller Manager does now, not a proposal. Read
[`CONTROLLER_MANAGER.md`](CONTROLLER_MANAGER.md) first: it states the three situations and the
guarantee this serves.

## The two states a physical control can be in

Every control of a connected controller model is in exactly one of these. There is no third state
and no combination.

**Pass through** — the default for every routable control. The control drives the virtual control
of the same name, one to one, and that is what the guest sees. A button is a button; a trigger is a
trigger with its analog value; a stick is a position; the D-pad is a position. The work happens on
the thread GameController called the handler on, with one recursive lock and a prebuilt table, and
is measured at a median of about a microsecond (see `--selftest=controller-latency`). There is no
main-queue hop anywhere on this path.

**Tolkara action** — the control is claimed. It is removed from the guest's route table entirely,
so it produces no route notification and the guest never sees it. Instead it drives a behaviour
this app already has, through the interface that behaviour already uses.

Claiming exists because of the second half of the guarantee: while routing is on, the guest is only
ever shown the virtual controller. A control Tolkara keeps is therefore a control the game does not
have — and that is what makes it useful.

## The action catalogue

There is one action, and it is real:

| Action | What it does | Press | Release |
| --- | --- | --- | --- |
| `tolkara.dictation` | Live dictation, the same one the voice page's trigger drives | `[AKDictation.shared begin]` | `[AKDictation.shared end]` |

It is not a second implementation. `-claimSource:forAction:device:` stores an `AKTrigger` with
`AKTriggerPatternPushToTalk` on that element for that controller model — the same trigger record
the voice page reads and the same object `AKInputRouter` fires — so the press and release semantics
are the ones the product already had, not a parallel set. The voice page and the Controller Manager
are two views of one mapping, and choosing a target for a claimed control puts it back to routing
and forgets the trigger, so one control can never both route and start dictation.

### What is not in the catalogue, and why

The rule is: only behaviours that already exist behind an app-owned interface, and only if making
them an action does not change product behaviour. Everything else is excluded by that rule, not
deferred:

| Behaviour | Why it is not an action |
| --- | --- |
| On-screen keyboard / gamepad visibility | Lives in the AppKit adapter as part of the touch overlay's own layout state. Driving it from a controller would change what the overlay does while the user is using it, and the adapter exposes no app-owned entry point for it. |
| Performance overlay | Same: adapter-side HUD state, changed through the gamepad layout screen, not through an app interface. |
| Voice test, add-on pages, launcher pages | Screen navigation, not an input behaviour. Invoking pages from a pad press is a different feature with its own questions — which page, and what happens to a running session. |
| Screenshots, Spotlight, other system gestures | Not ours: iPadOS owns them, and the product's rule is that a feature never starts because an unrelated system press happened. |
| Anything that types or presses game keys | Not input remapping. The boundary in `AGENTS.md` is that we adapt input, never automate the application. |

A behaviour joins this table when it has an app-owned interface and a test showing the claimed
control produces no route notification — not before.

## Where the model is stored

`WolkaraForeverControllerProfile.<identity>`, version 2:

```json
{ "version": 2,
  "map":     { "controller.button.a": "virtual.button.a" },
  "actions": { "controller.button.x": "tolkara.dictation" } }
```

* **Version 1 migrated**: a bare `source -> target` table becomes version 2 with those targets as
  explicit pass-through and no claims — nothing a v1 user chose is lost, and nothing they never
  had is invented.
* **Unknown versions and malformed values** fall back to the complete default 1:1 layout rather
  than half-applying, so a corrupt table cannot leave a control dead.
* **Reset** restores the default layout *and* removes every claim.
* **One target, one source**: binding a source to a target unmaps whoever else drove it, and
  claiming a source clears its target. Two controls cannot fight over one virtual button.
* Profiles are per *model* (`vendor` + `product category`), so two identical pads share one. The
  page says so.

## Invariants

1. A claimed control produces no `AKControllerRouteValue` or `...Position` notification, ever.
2. A routed control never fires a Tolkara action.
3. Pass-through stays on the framework's callback thread; actions may be dispatched, because they
   are discrete events rather than a stream of positions.
4. Releases are symmetric: releasing, disabling routing, disconnecting, backgrounding, resigning
   active, a profile change and a reset each leave no held virtual value and no dictation session
   running.
5. The hot path never reads a mutable profile object, never touches defaults, never builds a table
   and never hops to main. Tables are built on main and published whole.

## Where each is proven

| Claim | Test |
| --- | --- |
| claimed control routes nothing, is the stored dictation trigger, survives reload, gives the route back | `test_controller_manager.sh` — `CONTROLLER_MANAGER_CLAIM_PASS` |
| a v1 table still loads as pass-through with no claims | same suite |
| reset clears claims | same suite |
| the page's claim and restore handlers, and both languages | `test_wow_launcher_ui.sh` |
| the action list matches what the page offers and what both string tables name | `check_controller_actions.sh` |
| every target the page offers can be written by the adapter | `check_controller_targets.sh` |
| pass-through direct, analog, sticks, D-pad, release, latency | `--selftest=controller-routing`, `--selftest=controller-latency` |
| the three situations, on the device | `--selftest=controller-situations` |
