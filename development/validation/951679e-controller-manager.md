# Validation: Controller Manager (`controller2`)

- Commit: `951679e44c71a149e29fd1d84aac53fe08a837da` (branch `controller2`)
- Recorded: 2026-11-04 03:31:51Z
- Working tree: clean at the commit under test
- Host: macOS (arm64), Xcode 27.2 (Build 27B52)
- Device: iPad Pro 12.9-inch (5th generation), iPadOS 26 (`Dadpad`, paired over USB)
- Execution mode: `developer-service`
- Guest application used for the import measurement:
  `build/guest-probe/WorldOfWarcraft` (the Classic client binary, universal, arm64)
- The build under test includes `TOLKARA_EXPERIMENTAL_ADAPTERS=GameController`, so the guest
  GameController façade is in the bundle (`Frameworks/akGameController.dylib`)

## Results

| Step | Result |
| --- | --- |
| layer gate (`check_layers.sh`) | PASS |
| documentation gate (`check_docs.sh`) | PASS |
| façade import coverage, measured on the real client binary | PASS — 32 imports, 0 uncovered |
| Controller Manager state machine (simulator fixture) | PASS |
| guest GameController façade (simulator fixture) | PASS |
| the on-screen gamepad, lifecycle and routing (simulator fixture) | PASS |
| routed values through a **real** `GCVirtualController` (simulator) | PASS |
| launcher pages, six cards, the Controller Manager card and page (fixture) | PASS |
| voice triggers, unchanged by the handler move (simulator fixture) | PASS — 307 checks |
| translation adapters, the shared event/render loop (simulator) | PASS |
| on-screen controls and the game text field (simulator fixture) | PASS |
| signed app builds for the device | PASS |
| app installed and launched on the iPad at this commit | PASS |
| the sixth card drawn on the front page | PASS (photographed) |
| the card and the page driven on the iPad (`--selftest=controller-manager`) | PASS — 18/18 checks |
| **the routing chain and the gesture contract on the iPad** (`--selftest=controller-routing`) | **PASS — 18/18 checks** |

## The routing chain, on the device, with no hardware

A hidden `GCVirtualController` is a real `GCController`, so the path a pad takes runs on the iPad
without one. `--selftest=controller-routing` connects one, has the manager install its real
handlers on it, drives its elements, applies the route notifications with the same two framework
calls the adapter makes, and reads the values back off the controller a guest would enumerate:

```
Command: wolkaraforever/tools/pilot.sh selftest controller-routing
21:26:40.795 [selftest] selftest: controller-routing starting
21:26:41.250 [selftest] selftest: controller-routing PASS 18/18 checks
```

The checks:

1. a hidden virtual controller connects on this device;
2. a second one is **refused** while the first is up — measured here, and the reason the product
   owns exactly one;
3. the controller declares the Menu element iPadOS reserves;
4. a routed reserved button has its gesture **released**;
5. an ordinary button's gesture is **left alone**;
6. unrouting that button gives the gesture **back**;
7. a press on a real `GCControllerButtonInput` arrives as the mapped virtual button
   (`virtual.button.a=1.000`);
8. and the two adapter calls move the controller the guest would enumerate (`buttonA.value == 1`);
9. after a reassignment the same press arrives as the **new** virtual button
   (`virtual.button.y=1.000`);
10. and the reassigned button is what moves on the pad;
11. the button it used to drive produces no notification at all;
12. a trigger's analog value is carried (`virtual.button.left.trigger=0.600`);
13. a stick's position is carried (`virtual.stick.left=0.500,-0.250`);
14. the D-pad's is carried (`virtual.dpad=0.000,1.000`);
15. all three reach the controller (`leftTrigger 0.6`, `leftThumbstick.x 0.5`, `dpad.y 1`);
16. switching routing off releases every routed value;
17. and gives the system back every gesture it was holding;
18. and nothing is left held on the controller.

Check 17 is why the fix in this commit exists: routing off had only restored gestures on the
controllers the manager still counted as *hardware*, so a pad that left that list — disconnecting,
or adopted as the virtual pad — kept the release. The restore now walks every connected controller
and gives back every element no reason still wants.

One controller serves as both the input and the routed device, because the device allows only one
hidden controller. What that proves is the whole chain — a real element handler, the gesture, the
remap, the notification, and the two framework calls moving a real controller. Telling two
*different* pads apart is covered by `test_controller_manager.sh`, which has independent pads.

## The front page and the page, on the device

The Controller Manager was first written as a row inside the game-file card, which is cut off at
“Reset to Default Graphical Settings” on the 4:3 front page — measured on the device, so the
feature was only reachable by scrolling. It is now **the sixth card**, third row beside the
game-file card, and the empty cell that used to sit there is gone. The installed build's front
page shows, bottom-right:

```
CONTROLLER MANAGER
Route physical controllers through virtual controller      [ off ]
Off. A physical controller reaches the game directly.
Controller mappings and reassignment
```

`--selftest=controller-manager` drives both the card and the page:

```
Command: wolkaraforever/tools/pilot.sh selftest controller-manager
20:38:34.746 [selftest] selftest: controller-manager starting
20:38:34.760 [selftest] selftest: controller-manager PASS 18/18 checks
```

Eleven page checks: the build carries the guest adapter; the page draws the switch; the switch is
off until asked; the page says the direct path is in use; switching on stores
`WolkaraForeverControllerRouting` and nothing else; the manager follows it; the page says routing
starts with the game session; switching off clears both; the page says the direct path is back; the
disclosure is present; reassigning is inert with no controller connected.

Seven card checks, on the live home page: the card exists; its switch is off until asked; its
sentence says the direct path is in use; the way into the mappings is offered; its switch is **the
same setting** as the page's; its sentence turns to “starts with the game session”; and switching
it back clears the setting.

Both tests put the user's stored value back.

## Install

`wolkaraforever/tools/install.sh --replace-running` built and installed at this commit, with
`GUEST_EXE=build/guest-probe/WorldOfWarcraft` and
`TOLKARA_EXPERIMENTAL_ADAPTERS=GameController`. The façade gate ran first, as part of the build:

```
check_gamecontroller_facade: PASS — 32 GameController import(s) covered by the façade.
App installed:
plain WolkaraForever launcher launched
```

## Simulator evidence

```
CONTROLLER_MANAGER_PASS: profile, routing, lifecycle, learning and gesture ownership.
GAMECONTROLLER_FACADE_PASS: direct path unchanged when off, exactly one virtual controller
  when on, no physical pad or event crossing.
TOUCH_GAMEPAD_ROUTING_PASS: routed values reach the virtual elements, clamping, release,
  mode-change release, and routing with no physical pad.
TOUCH_GAMEPAD_INPUT_PASS: all nine buttons, D-pad diagonals/opposition/cancel, both sticks,
  held modifiers, neutral reset and trackpad passthrough.
VOICE PASS: 307 checks
CONTROLLER_MANAGER_PAGE: placement, off default, persistence, learn/cancel, German, no
  game-file write
```

The launcher fixture asserts the six-card grid and its order (`wow.box.edition`, `addons`,
`voice`, `profile`, `performance`, `controllerManager`), with no spacer cell, the sixth card's
rows, its switch, its status sentence, and that it and the page are one setting.

One flake, recorded rather than hidden: the first launcher-suite run after the gesture fix stopped
at the German step and printed `WoW UIKit TIMEOUT`; an immediate re-run with no code change
printed `WoW UIKit PASS` with every check in it. That is the fixture's own timing, not a failure
of the product, but a single green run should not be read as proof that it never hangs.

## Façade coverage

`wolkaraforever/tools/check_gamecontroller_facade.sh` compares the client's real import list with
what the façade defines and fails by name on anything uncovered. Measured here: **32 imports, 0
uncovered** — four classes (`GCController`, `GCControllerButtonInput`, `GCControllerAxisInput`,
`GCColor`) and the constants. The last three answer `+class` with Apple's own class, found by
`dlsym`, so the guest's `-isKindOfClass:` about the manager's objects stays true; the façade
fixture asserts that equality at runtime.

## What a pad would still add, and what it would not

It would add one thing: **a particular pad's own firmware**. Whether a given controller's reserved
button can be delivered at all is Apple's behaviour plus that pad's, not something this feature can
get wrong or right. If it is not delivered, that one control is not routed; no other control and no
held value is affected.

It would add nothing to the chain. The element handler, the gesture release and restore, the
remap, the notification, the two framework calls and the enumeration the guest sees are all
measured on the device with real framework objects.

A live World of Warcraft session would add one thing too: watching the game bind the controller it
is offered. That is the framework's delivery of a standard `GCController`, and every GameController
symbol the client imports is covered (32/32), so nothing it asks for is stubbed or absent.
