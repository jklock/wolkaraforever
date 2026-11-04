# Controller Manager: routing a physical pad through one virtual controller

Engineering note, 2026-11-03. Written with the implementation, so every claim here names
the file that makes it true. Physical results are recorded in
[`development/validation/`](../validation/) under the revision that ran.

## What it is for

World of Warcraft on an iPad sees whatever GameController reports. That is fine until a
pad's buttons need to mean something different from what they say — or until a spare pad
should not reach the game at all. The Controller Manager is the launcher's answer, and it is
**the sixth card on the home screen**, not a row inside someone else's card:

* a switch, **Route physical controllers through virtual controller**, off by default;
* one remap profile per controller *model*, starting as a one-to-one extended-gamepad
  layout;
* a “press or move the source, then choose the virtual target” reassignment flow;
* a status line that says which of the four states routing is in.

The card and the page it opens drive the same setting, owned by the manager; both follow
`AKControllerManagerDidChangeNotification`, so whichever one is used, the other is right. The
card exists because the row it replaced was below the fold on the 4:3 front page — measured
on the device, where that card was cut off at “Reset to Default Graphical Settings”.

Nothing here changes World of Warcraft's own bindings, `GamePadConfig_*.json` or
`Config.wtf`. The game's `GamePadEnable` row stays a separate setting with a separate
owner (`wowkaraforever/WoW/ForeverUI.m`), and the profile store only writes WolkaraForever's
own `NSUserDefaults` key.

## The constraint that shapes it

The host and the guest are one process with one GameController. `GCController.controllers`
is a class method on a class both of them use, so anything the framework reports it
reports to both, and there is no public API that hides a physical pad from one consumer and
not the other. That was measured and written down in
[`CONTROLLER_PROFILES.md`](CONTROLLER_PROFILES.md) before this feature existed; this note
does not contradict it.

So the feature is built from two levers only:

1. **A hidden `GCVirtualController`** that the host drives. Apple's public setters inject
   values into it, and the guest sees a normal controller.
2. **A guest-facing GameController façade** that decides what the guest may enumerate. The
   host keeps physical access to the pad — it has to, or there would be nothing to
   intercept — and the guest is shown only the virtual controller.

## The three halves, and how they talk

```
launcher/Controller/ControllerManager.m      the owner (in the app)
        │  NSNotificationCenter, by name
        ├──► translation/AppKit/TouchGamepad.m      the one hidden GCVirtualController
        └──► translation/GameController/GameController.m   what the guest may see
```

They are separate binaries: the adapters are dylibs the app never links, which is why the
channel is notifications with the names spelled out on both sides — the same arrangement
`AKTouchOwnedKeyUsagesDidChange` already used.

### `AKControllerManager` — the owner

One owner, because three of them is how a button is left held. It owns:

* **discovery** of physical pads and **every GameController handler** installed on their
  elements. `AKControllerInspector` no longer installs any: it subscribes to the manager's
  normalized stream and keeps doing what it always did with it (name the event, log it,
  hand it to the voice router). That is what stops two consumers competing for one element.
* **normalized state** per model: what is down, where the sticks are.
* **profiles** (`ControllerProfile.m`) and the learn flow.
* **gesture release, tagged by reason.** A gesture is released while *any* reason wants it
  and given back when the last one lets go. The voice feature's releases and routing's
  releases are separate on purpose: `-[AKInputRouter applyMappings]` begins with
  `-restoreAllSystemGestures`, and if that also undid routing's release, a routed button
  would silently stop reaching the manager every time a voice mapping changed.
* **the routing lifecycle** — enable, disable, model change, pad disconnect, backgrounding
  — and releasing every virtual value on each of them.
* **one published view of the guest's controller list.**

Element ids are the canonical ones from `InputElement.h`; the model identity is
`AKControllerIdentity` (`ControllerIdentity.h`), `slug(vendorName).slug(productCategory)`.
GameController has no serial number, so two identical pads are indistinguishable and share
one profile. The page says so in as many words rather than pretending otherwise.

### `AKTouchGamepad` — the one hidden virtual controller

The existing hidden `GCVirtualController` gained a second producer rather than a second
implementation. Two producers drive one device, with defined ownership:

* while routing is on, the physical producer owns every element and the overlay's touches
  are ignored (the overlay is reset as routing starts and stops);
* releasing touches only what that producer set, so nothing is left held.

The producer speaks WolkaraForever virtual ids (`virtual.button.a`, `virtual.stick.left`,
`virtual.dpad`), not `GCInput*` constants: a stored profile must not depend on the
framework's spelling. `AKElementForTarget()` is the single translation point.

`-wantsController` answers “the pad is the input” when routing is on, so it does not care
whether the on-screen controls or the keyboard are up; `-hasPhysicalController` answers NO,
because with routing on the physical pad is the *source*, not a competitor for the device.

### The guest façade — what WoW may enumerate

`translation/GameController/GameController.m` is ours (a `replace` of the platform's stub,
whose `standalone` marker still makes `classify.py` plan every GameController import for
this adapter rather than re-exporting Apple's). Two modes:

* **routing off** — `+[GCController controllers]` returns the host's published list, which
  *is* the real pads: same objects, same order, and their connect/disconnect events are
  re-posted under the names the guest bound. The direct path WoW always used is unchanged.
* **routing on** — the list holds the one virtual controller and nothing else. A physical
  pad produces no enumeration entry and no connect or disconnect event.

The guest asks once (`AKControllerGuestViewRequest`) and is answered synchronously, so a
session started while routing was already on is not left without input.
**The interlock.** Without the façade the guest would see the physical pad *and* its virtual
replacement, and every press would arrive twice. So the manager will not ask for a virtual
pad until the adapter has announced itself, and it tells two situations apart: whether the
*build* carries the adapter (the bundle has `Frameworks/akGameController.dylib`) and whether
it is *loaded* now (the adapter posts when it loads, and answers when asked). In the launcher
the adapter is never loaded, so the page says “it starts when the game starts” rather than
claiming the build cannot do it; a build without the adapter says exactly that and routes
nothing.
## The state machine

| State | When | What is routed |
| --- | --- | --- |
| Disabled | the switch is off | nothing; physical pads reach the guest directly |
| Waiting | on, but no pad, or the virtual controller is still connecting | nothing yet |
| Routing | on, a pad is connected, the virtual controller is up | every mapped source |
| Failed | the virtual controller refused to connect | **nothing** — values aimed at a pad that is not there are not sent |

Backgrounding and the app resigning active release every virtual value and keep the switch
on; coming back re-routes from the pad's current state. A pad disconnect releases, and a
reconnect resumes without the user touching the switch. Switching off releases, gives back
every gesture routing asked for, and hands the device back to the touch producer.

## Virtual targets, and the ones that do not exist

`virtual.button.{a,b,x,y,left,shoulder,right,shoulder,left,trigger,right,trigger,menu}`,
`virtual.stick.{left,right}`, `virtual.dpad` — that is the whole set, because it is what the
hidden controller can be driven with. `GCVirtualControllerConfiguration` throws when it is
asked for the D-pad together with a thumbstick (or for Menu/Options), so the declaration
stays a subset and the connected extended profile supplies the D-pad and Menu.

Options, Home, Share, the stick clicks and the paddles therefore have **no** target. They
are mapped to `virtual.none` explicitly and the page shows them as not available, which is
how a choice that cannot work is reported instead of offered.

## Failing closed on the façade

A standalone adapter's uncovered import becomes a generated stub that shadows Apple's class
or constant for the guest. That is not a visible failure — it is a game whose controller
reads return nothing. So `wolkaraforever/tools/check_gamecontroller_facade.sh` reads the
application's real import list with `dyld_info`, compares it with what the façade defines,
and **fails** naming every symbol it does not cover. `install.sh` runs it whenever
`TOLKARA_EXPERIMENTAL_ADAPTERS` names `GameController`, so a WoW build cannot silently ship
an uncovered import.

The check refuses to pass with no application to inspect: an unproven façade is a leaked
pad waiting to happen. It is also the first thing to run when a new client build is tried.

Measured against `build/guest-probe/WorldOfWarcraft` on 2026-11-03: **32 GameController
imports, 0 uncovered**. The client imports four classes — `GCController`,
`GCControllerButtonInput`, `GCControllerAxisInput`, `GCColor` — and the last three need
special care: a standalone adapter shadows Apple's class of the same name, so a plain stub
would answer NO to the guest's `-isKindOfClass:` about objects that *are* Apple's, and the
game would stop recognising its own buttons. Each of the three answers `+class` with the
real framework's class, found by `dlsym` rather than by name, because a name lookup returns
whichever image registered first. The façade fixture asserts that equality at runtime.

## What is verified, and what is not

Verified in the simulator, by the suite that owns each claim:

* `wolkaraforever/tools/test_controller_manager.sh` — default layout, remap and the
  one-to-one rule, reload, reset, analog pass-through and quantisation, releases, multiple
  sources, unmapped and unavailable inputs, sticks and D-pad, duplicate models, disconnect
  and reconnect, virtual-connect failure, backgrounding, enable/disable, and every
  held-state release; learning captures a button and a stick, ignores another controller,
  cancels, and disarms on background; gesture ownership by reason.
* `wolkaraforever/tools/test_gamecontroller_facade.sh` — the guest's view: the direct path
  when routing is off, exactly one virtual controller when it is on, and no physical pad or
  its events crossing.
* `wolkaraforever/tools/test_touch_gamepad_ui.sh` — routed values reaching the virtual
  controller's own elements, clamping, release on mode change, and routing with no physical
  pad present. Its `--self-test-input` run uses Apple's **real** `GCVirtualController` and reads
  the routed values back off the `GCController` a guest would enumerate, so the last link in the
  chain is proven against the framework and not against a stand-in.
* `wolkaraforever/tools/test_wow_launcher_ui.sh` — the page's row, off default,
  persistence, learn/cancel, German without reopening, and no game file written.
* `--selftest=controller-manager`, run on the installed build with
  `wolkaraforever/tools/pilot.sh selftest controller-manager` — the same page driven by the app
  itself on the iPad, because a device matrix cannot tap: 18/18 checks across the page and the
  front-page card, and it restores the user's own value.
* `--selftest=controller-routing` — the whole chain on the iPad with no hardware: a hidden
  `GCVirtualController` on which the manager installs its **real** handlers, driven through a
  button, a trigger, a stick and the D-pad, with the route notifications applied by the same two
  framework calls the adapter makes and the values read back off the controller a guest would
  enumerate. It also reassigns a control, checks the old target produces nothing, and switches
  routing off to check nothing is left held. 13/13.
* `wolkaraforever/tools/pilot.sh preview controller-manager` — the page opened directly and
  photographed on the iPad, for a row that is below the fold on the home screen.
* `test_voice.sh`, `test_translation_sim.sh`, `check_layers.sh`, `check_docs.sh` — that
  moving the handlers out of the inspector did not change the voice trigger, and that the
  shared event/render loop is untouched.

**What this app is responsible for, measured:** the release is applied to exactly the sources a
profile routes and iPadOS reserves, an ordinary button's gesture is never touched, and every
release is given back when the source is unrouted or routing stops. All four are checked against
the framework's own element objects on the device, in `--selftest=controller-routing`. If a
particular pad's reserved button still failed to arrive, that one control would simply not be
routed; no other control, and no held value, is affected.

**The guest side is a contract, not a hope.** While routing is on the guest enumerates exactly
one `GCController` — the hidden virtual controller — carrying the standard extended profile, and
the framework delivers it as it delivers any pad. Every GameController symbol the client imports
is covered (32/32 measured), so nothing it asks for is a stub or absent.

A pad's firmware is the one thing outside this app, and it is outside any app: whether a given
controller's reserved button can be delivered at all is Apple's behaviour plus that pad's, not
something this feature can get wrong or right.

## Known limits

* **One hidden virtual controller at a time.** A second `GCVirtualController` is refused while
  one is connected — measured on the device, 2026-11-03, which is why the manager owns exactly
  one and waits for the adapter's reply rather than creating another.
* Routing needs the AppKit adapter's touch host to exist, because that is what owns the
  hidden virtual controller. It is created for every guest session, so this is a property
  of the design rather than a setting; a build that installs no on-screen controls has no
  routing.
* While routing, the on-screen gamepad is still drawn if the user has it on, and its
  touches are ignored. That is deliberate — two producers, one owner — but it is visible.
* Identical model controllers share one profile. That is the platform's granularity, not a
  choice.
