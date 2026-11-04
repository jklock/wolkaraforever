# Validation: Controller Manager (`controller2`)

- Commit: `041c39a63cb51998ecf14bc950fe239753b4f6be` (branch `controller2`)
- Recorded: 2026-11-04 02:42:15Z
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
| **the whole routing chain on the iPad** (`--selftest=controller-routing`) | **PASS — 13/13 checks** |
| a physical pad's own hardware, and iPadOS handing a reserved button to this app | **NOT RUN — no pad in a hand** |
| World of Warcraft binding the virtual controller in-world | **NOT RUN — needs a guest session with a pad** |

## The routing chain, on the device, with no hardware

A hidden `GCVirtualController` is a real `GCController`, so the path a physical pad takes runs
on the iPad without one. `--selftest=controller-routing` connects one, has the manager install
its real handlers on it, drives its elements, applies the route notifications with the same two
framework calls the adapter makes, and reads the values back off the controller a guest would
enumerate:

```
Command: wolkaraforever/tools/pilot.sh selftest controller-routing
20:34:49.670 [selftest] selftest: controller-routing starting
20:34:50.238 [selftest] selftest: controller-routing PASS 13/13 checks
```

The thirteen checks:

1. a hidden virtual controller connects on this device;
2. a second one is **refused** while the first is up — measured here, and the reason the
   product owns exactly one;
3. a press on a real `GCControllerButtonInput` arrives as the mapped virtual button
   (`virtual.button.a=1.000`);
4. and the two adapter calls move the controller the guest would enumerate (`buttonA.value == 1`);
5. after a reassignment the same press arrives as the **new** virtual button
   (`virtual.button.y=1.000`);
6. and the reassigned button is what moves on the pad;
7. the button it used to drive produces no notification at all;
8. a trigger's analog value is carried (`virtual.button.left.trigger=0.600`), not just its press;
9. a stick's position is carried (`virtual.stick.left=0.500,-0.250`);
10. the D-pad's is carried (`virtual.dpad=0.000,1.000`);
11. all three reach the controller (`leftTrigger 0.6`, `leftThumbstick.x 0.5`, `dpad.y 1`);
12. switching routing off releases every routed value;
13. and nothing is left held on the controller.

One controller serves as both the input and the routed device, because the device allows only
one hidden controller. What that still proves is the whole chain — a real element handler, the
remap, the notification, and the two framework calls moving a real controller. What it does not
prove is the manager telling two *different* pads apart; that is covered by
`test_controller_manager.sh`, which has independent fake pads.

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

Eleven page checks: the build carries the guest adapter; the page draws the switch; the switch
is off until asked; the page says the direct path is in use; switching on stores
`WolkaraForeverControllerRouting` and nothing else; the manager follows it; the page says
routing starts with the game session; switching off clears both; the page says the direct path
is back; the disclosure is present; reassigning is inert with no controller connected.

Seven card checks, on the live home page: the card exists; its switch is off until asked; its
sentence says the direct path is in use; the way into the mappings is offered; its switch is
**the same setting** as the page's; its sentence turns to “starts with the game session”; and
switching it back clears the setting.

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

## Façade coverage

`wolkaraforever/tools/check_gamecontroller_facade.sh` compares the client's real import list
with what the façade defines and fails by name on anything uncovered. Measured here: **32
imports, 0 uncovered** — four classes (`GCController`, `GCControllerButtonInput`,
`GCControllerAxisInput`, `GCColor`) and the constants. The last three answer `+class` with
Apple's own class, found by `dlsym`, so the guest's `-isKindOfClass:` about the manager's
objects stays true; the façade fixture asserts that equality at runtime.

## Not run, and why

- **A physical pad's own hardware.** No controller is attached (`0 controller(s) connected`), so
  nothing has shown whether iPadOS delivers a reserved button (Menu, Options, Home, Share) to
  this app on real hardware. The path from a handler to the virtual pad is proven; the arrival
  of the press from a real pad is not.
- **World of Warcraft binding the virtual controller.** That needs a guest session with a pad.

## What the next session with a pad owes

With one Bluetooth and one USB controller attached to the iPad, on this commit:

1. Direct mode with routing off — the pad reaches the game as before.
2. Routing on from the front-page card — the same controls move the character.
3. One control reassigned — only that control changes.
4. Routing off — the pad is back on the direct path, with no held value.
5. Disconnect and reconnect with routing on — routing resumes without touching the switch.
6. A reserved button (Menu/Options/Home) — does the press reach the app at all.
7. An in-world check, and whether physical-controller suppression was observable in the guest.
8. Record the controller models, iPadOS version, execution mode, client build and this SHA.
