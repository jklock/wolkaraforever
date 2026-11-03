# Validation: Controller Manager (`controller2`)

- Commit: `c6d1136a3eb61f9baa61938aa9e722192eff74dc` (branch `controller2`)
- Recorded: 2026-11-03 22:18:12Z
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
| the sixth card and the page driven on the iPad (`--selftest=controller-manager`) | PASS — 18/18 checks |
| physical Bluetooth controller, in-world | **NOT RUN — no controller attached** |
| physical USB controller, in-world | **NOT RUN — no controller attached** |

## The front page, as measured

The Controller Manager was first written as a row inside the game-file card. On the device that
card is cut off at “Reset to Default Graphical Settings” on the 4:3 front page, so the feature
was reachable only by scrolling — photographed and measured on 2026-11-03. It is now **the sixth
card**, the third row beside the game-file card, and the empty cell that used to sit there is
gone.

The installed build's front page shows, bottom-right:

```
CONTROLLER MANAGER
Route physical controllers through virtual controller      [ off ]
Off. A physical controller reaches the game directly.
Controller mappings and reassignment
```

## The device, as measured

`wolkaraforever/tools/install.sh --replace-running` built and installed at this commit, with
`GUEST_EXE=build/guest-probe/WorldOfWarcraft` and
`TOLKARA_EXPERIMENTAL_ADAPTERS=GameController`. The façade gate ran first, as part of the build,
and passed:

```
check_gamecontroller_facade: PASS — 32 GameController import(s) covered by the façade.
App installed:
plain WolkaraForever launcher launched
```

The app was then driven by itself, because a device matrix cannot tap:

```
Command: wolkaraforever/tools/pilot.sh selftest controller-manager
16:14:26.203 [selftest] selftest: controller-manager starting
16:14:26.216 [selftest] selftest: controller-manager PASS 18/18 checks
```

The eleven page checks: this build carries the guest adapter; the page draws the switch; the
switch is off until asked; the page says the direct path is in use; switching on stores
`WolkaraForeverControllerRouting` and nothing else; the manager follows it; the page says
routing starts with the game session; switching off clears both; the page says the direct path
is back; the disclosure is present; reassigning is inert with no controller connected.

The seven card checks, on the live home page: the card exists; its switch is off until asked;
its sentence says the direct path is in use; the way into the mappings is offered; its switch is
**the same setting** as the page's (it stored the key and the manager followed); its sentence
turns to “starts with the game session”; and switching it back clears the setting.

The user's own stored value is restored at the end of both.

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
CONTROLLER_MANAGER_PAGE: placement, off default, persistence, learn/cancel, German, no
  game-file write
```

The `TOUCH_GAMEPAD_INPUT_PASS` run uses Apple's **real** `GCVirtualController` — not a stand-in
— and drives it through the routing notifications: a routed B button, left trigger, left stick
and D-pad are read back off the `GCController` a guest would enumerate, a touch is shown not to
overwrite a routed value, and a release is shown to zero every element.

The launcher fixture asserts the six-card grid and its order: `wow.box.edition`,
`wow.box.addons`, `wow.box.voice`, `wow.box.profile`, `wow.box.performance`,
`wow.box.controllerManager`, with no spacer cell; the sixth card's rows; the card's switch and
status sentence; and that the card's switch and the page's are one setting.

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
2. Routing on from the front-page card — the same controls move the character.
3. One control reassigned — only that control changes.
4. Routing off — the pad is back on the direct path, with no held value.
5. Disconnect and reconnect with routing on — routing resumes without touching the switch.
6. An in-world input check, and whether physical-controller suppression was observable in the
   guest (what `GCController.controllers` reports from inside the game, or a pad button the
   game does not react to).
7. Record the controller models, iPadOS version, execution mode, client build and this SHA.
