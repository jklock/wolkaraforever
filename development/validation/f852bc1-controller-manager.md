# Validation: Controller Manager (`controller2`)

- Commit: `f852bc17c0965d1be94bc00c46209f42d1e749be` (branch `controller2`)
- Recorded: 2026-11-03 19:17:42Z
- Working tree: clean
- Host: macOS (arm64), Xcode 27.2 (Build 27B52)
- Device: iPad Pro 12.9-inch (5th generation), iPadOS 26 (`Dadpad`, paired over USB)
- Execution mode: `developer-service`
- Guest application used for the import measurement:
  `build/guest-probe/WorldOfWarcraft` (the Classic client binary, universal, arm64)

## Results

| Step | Result |
| --- | --- |
| layer gate (`check_layers.sh`) | PASS |
| documentation gate (`check_docs.sh`) | PASS |
| Controller Manager state machine (simulator fixture) | PASS |
| guest GameController façade (simulator fixture) | PASS |
| the on-screen gamepad, lifecycle and routing (simulator fixture) | PASS |
| launcher pages incl. the Controller Manager page (simulator fixture) | PASS |
| voice triggers, unchanged by the handler move (simulator fixture) | PASS — 307 checks |
| translation adapters, the shared event/render loop (simulator) | PASS |
| on-screen controls and the game text field (simulator fixture) | PASS |
| façade import coverage, measured on the real client binary | PASS — 32 imports, 0 uncovered |
| signed app builds for the device | PASS |
| app installed on the iPad at this commit | PASS |
| app launched on the iPad at this commit | **NOT RUN — iPad locked** |
| physical Bluetooth controller, in-world | **NOT RUN — no controller to hand** |
| physical USB controller, in-world | **NOT RUN — no controller to hand** |

## What each step printed

### Controller Manager state machine

```
Command: wolkaraforever/tools/test_controller_manager.sh
CONTROLLER_MANAGER_PROFILE_PASS: default layout, remap, one-to-one targets, reload, reset.
CONTROLLER_MANAGER_ROUTING_PASS: analog pass-through, quantisation, releases, multiple
  sources, unmapped inputs, axes, duplicate models.
CONTROLLER_MANAGER_LIFECYCLE_PASS: disconnect, reconnect, virtual-connect failure,
  backgrounding, enable/disable and every held-state release.
CONTROLLER_MANAGER_LEARNING_PASS: arm, wrong-controller rejection, button and stick capture,
  cancel, background cancellation.
CONTROLLER_MANAGER_GESTURE_PASS: released only for routed reserved buttons, independent of
  voice releases, restored on unroute and on disable.
CONTROLLER_MANAGER_PASS: profile, routing, lifecycle, learning and gesture ownership.
```

The suite also asserts the façade interlock: with no guest adapter announced, routing is
`Failed` and nothing is routed.

### Guest façade

```
Command: wolkaraforever/tools/test_gamecontroller_facade.sh
GAMECONTROLLER_FACADE_PASS: direct path unchanged when off, exactly one virtual controller
  when on, no physical pad or event crossing.
```

It also asserts, at runtime, that `+[GCControllerButtonInput class]`,
`+[GCControllerAxisInput class]` and `+[GCColor class]` are Apple's classes (found by
`dlsym` on the real framework), not the adapter's stand-ins — that is what keeps the guest's
`-isKindOfClass:` about the manager's objects true.

### The on-screen gamepad

```
Command: wolkaraforever/tools/test_touch_gamepad_ui.sh
TOUCH_GAMEPAD_LIFECYCLE_PASS: physical priority, own/snapshot filtering, keyboard/focus
  cancellation, late replies, failure, retry and teardown.
TOUCH_GAMEPAD_ROUTING_PASS: routed values reach the virtual elements, clamping, release,
  mode-change release, and routing with no physical pad.
```

### Launcher page

```
Command: wolkaraforever/tools/test_wow_launcher_ui.sh
CONTROLLER_MANAGER_MODELS: 0
CONTROLLER_MANAGER_PAGE: placement, off default, persistence, learn/cancel, German, no
  game-file write
WoW UIKit PASS: …
```

The model count is 0 because the fixture states what is connected through the manager's
documented discovery seam: the simulator reports a controller of its own, and a page test
must not depend on that.

### Voice, translation, touch controls

```
VOICE PASS: 307 checks        (unchanged after moving the GameController handlers out of
                               AKControllerInspector and into AKControllerManager)
translation sim: … PASS
TOUCH_UI_SELF_TEST_PASS: …
```

### Façade import coverage against the real client

```
Command: wolkaraforever/tools/check_gamecontroller_facade.sh build/guest-probe/WorldOfWarcraft
check_gamecontroller_facade: PASS — 32 GameController import(s) covered by the façade.
```

What the client imports from GameController, measured with `dyld_info -arch arm64 -imports`:

- classes: `GCController`, `GCControllerAxisInput`, `GCControllerButtonInput`, `GCColor`
- constants: `GCControllerDidConnectNotification`, `GCControllerDidDisconnectNotification`,
  the `GCHapticsLocality*` set, the `GCInput*` set the façade declares (buttons, shoulders,
  triggers, thumbstick buttons, Menu/Options, the Xbox paddles, the DualShock touchpad
  elements), `GCHapticDurationInfinite`

The first run of the check found 30 uncovered symbols, 27 of them because of an awk
field-index bug that made every constant look undefined; with that fixed the real gap was
the three element classes, which are now answered with Apple's own class identity. The check
fails closed: with no executable to inspect it exits 2 rather than passing.

## Device

`wolkaraforever/tools/install.sh --replace-running` built and installed the app at this
commit (`App installed: local.wolkaraforever.johnklock`). The steps after the install — the
Developer service enrolment and the recovery launch — were refused by SBMainWorkspace:

```
NSLocalizedFailureReason = The request was denied by service delegate (SBMainWorkspace)
  for reason: Locked ("Unable to launch local.wolkaraforever.johnklock because the device
  was not, or could not be, unlocked").
```

`pilot.sh launch` says the same. So the app on the iPad is this build, but it has not been
run, and **nothing on the device has been observed for this feature**.

## Not run, and why

- **A physical controller on the device.** None was attached, and the iPad was locked, so
  neither the direct path, the default map, a changed mapping, disable/reconnect, nor an
  in-world input check could be performed. Simulator results say nothing about whether
  iPadOS delivers a reserved button to this app or whether World of Warcraft binds the
  virtual controller.
- **A build with `TOLKARA_EXPERIMENTAL_ADAPTERS=GameController`.** The coverage gate passes
  for the client binary, but switching the guest's GameController for a shim is a change to
  every application in the build and has not been seen in-world. Enabling it is a deliberate
  step for the next device session, not a default.
- **Routing itself, in any build.** With the adapter absent the manager refuses to route by
  design (otherwise every press would arrive twice), so the device build above shows the
  page, the switch, the persistence and the refusal — not routing.

## What the next device session owes

1. Unlock the iPad and run `wolkaraforever/tools/pilot.sh launch` for this commit.
2. With one Bluetooth and one USB controller attached, and with
   `TOLKARA_EXPERIMENTAL_ADAPTERS=GameController` in the build: direct mode, the default
   map, a changed mapping, disable restoration, reconnect, and an in-world input check.
3. Record whether physical-controller suppression was observable in the guest, with the
   controller models, iPadOS version, execution mode, client build and this SHA.
