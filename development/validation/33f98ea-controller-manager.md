# Validation: Controller Manager (`controller2`)

- Commit: `33f98eac6b3048586f9d4239967d90d35804b677` (branch `controller2`)
- Recorded: 2026-11-03 21:47:08Z
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
| launcher pages incl. the Controller Manager page (simulator fixture) | PASS |
| voice triggers, unchanged by the handler move (simulator fixture) | PASS — 307 checks |
| translation adapters, the shared event/render loop (simulator) | PASS |
| on-screen controls and the game text field (simulator fixture) | PASS |
| signed app builds for the device | PASS |
| app installed on the iPad at this commit | PASS |
| app launched on the iPad at this commit | PASS |
| Controller Manager page rendered on the iPad | PASS (photographed) |
| Controller Manager page driven on the iPad (`--selftest=controller-manager`) | PASS — 11/11 checks |
| physical Bluetooth controller, in-world | **NOT RUN — no controller attached** |
| physical USB controller, in-world | **NOT RUN — no controller attached** |

## The device, as measured

`wolkaraforever/tools/install.sh --replace-running` built and installed at this commit, with
`GUEST_EXE=build/guest-probe/WorldOfWarcraft` and
`TOLKARA_EXPERIMENTAL_ADAPTERS=GameController`. The façade gate ran first, as part of the
build, and passed:

```
check_gamecontroller_facade: PASS — 32 GameController import(s) covered by the façade.
App installed:
plain WolkaraForever launcher launched
```

The app was then stopped, launched into the page, and photographed
(`wolkaraforever/tools/pilot.sh preview controller-manager`). The page drew its title; the
ROUTING card with the switch **off** and “Off. A physical controller reaches the game
directly.”; CONTROLLER AND MAPPING with “No controller is connected.”; the reassign and reset
rows greyed; and the shared-mapping disclosure.

The page was then driven by the app itself, because a device matrix cannot tap:

```
Command: wolkaraforever/tools/pilot.sh selftest controller-manager
15:46:36.825 [selftest] selftest: controller-manager starting
15:46:36.836 [selftest] selftest: controller-manager PASS 11/11 checks
```

What those eleven checks are: this build carries the guest adapter; the page draws the
switch; the switch is off until asked; the page says the direct path is in use; switching on
stores `WolkaraForeverControllerRouting` and nothing else; the manager follows it; the page
says routing starts with the game session; switching off clears both; the page says the
direct path is back; the disclosure is present; reassigning is inert with no controller
connected. The user's own value is restored at the end.

**No controller was attached during any of this.** The app's own inventory says so, on this
build: `inspector: 0 controller(s) connected`.

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
```

The `TOUCH_GAMEPAD_INPUT_PASS` run uses Apple's **real** `GCVirtualController` — not a stand-in
— and now also drives it through the routing notifications: a routed B button, left trigger,
left stick and D-pad are read back off the `GCController` a guest would enumerate, a touch is
shown not to overwrite a routed value, and a release is shown to zero every element. That is
the last link the manager fixture cannot cover, because it has no GameController framework.

The page and its localized strings are also covered by the launcher fixture
(`CONTROLLER_MANAGER_PAGE: placement, off default, persistence, learn/cancel, German, no
game-file write`), and the German text is asserted there without reopening the page.

## Façade coverage

`wolkaraforever/tools/check_gamecontroller_facade.sh` compares the client's real import list
with what the façade defines and fails by name on anything uncovered. Measured here: **32
imports, 0 uncovered** — four classes (`GCController`, `GCControllerButtonInput`,
`GCControllerAxisInput`, `GCColor`) and the constants. The last three answer `+class` with
Apple's own class, found by `dlsym`, so the guest's `-isKindOfClass:` about the manager's
objects stays true; the façade fixture asserts that equality at runtime.

The check found real gaps when it was first run (30 reported, 27 of them a parsing bug in the
check itself) and now passes. It refuses to pass with no application to inspect.

## Not run, and why

- **A physical controller.** None was attached (`0 controller(s) connected`), so the direct
  path, the default map, a changed mapping, disable/reconnect and an in-world input check were
  not performed. Simulator results say nothing about whether iPadOS delivers a reserved button
  to this app or whether World of Warcraft binds the virtual controller.
- **Routing in a live game.** It needs the pad above, and a pad is the one thing this session
  did not have.

## What the next session with a pad owes

With one Bluetooth and one USB controller attached to the iPad, on this commit:

1. Direct mode with routing off — the pad reaches the game as before.
2. Routing on with the default map — the same controls move the character.
3. One control reassigned — only that control changes.
4. Routing off — the pad is back on the direct path, with no held value.
5. Disconnect and reconnect with routing on — routing resumes without touching the switch.
6. An in-world input check, and whether physical-controller suppression was observable in the
   guest (what `GCController.controllers` reports from inside the game, or a pad button the
   game does not react to).
7. Record the controller models, iPadOS version, execution mode, client build and this SHA.
