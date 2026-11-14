# Compatibility

> **Current source review: 2026-11-05 · branch `liveupdates-11042026`.**

Compatibility is specific to a device model, its OS version, the WoW build, the execution
mode, the account state, and the exact source revision. This page deliberately does not turn a past
result into a broad support promise.

## Current product boundary

WolkaraForever currently presents the Forever install and launcher flow. The source includes
download/update verification, add-on management, touch and controller input, voice
configuration, UI backup/restore, graphics-only reset, the gamepad setting, performance
overlay, and background-aware frame pacing. Their presence in source is not the same as a
physical pass on every iPad.

**Both Apple form factors are supported.** iPhone is not a compact fallback for the iPad and
the iPad's two-column page is not traded away for the phone; the layout, input and popup rules
for both are in [the supported-device contract](development/architecture/DEVICE_CONTRACT.md).

The supported integrated installation path is the device's Developer service. The repository
also contains engineering paths for Local signing and External JIT; neither should be read as
a general consumer-install promise.

## Evidence currently available

Every result is at one of four levels (see
[the user guide](docs/README.md#how-much-a-statement-here-proves)): source, simulator,
device script, or human full-game. A result never moves up a level without a new run at that
level.

The devices those levels are measured on are fixed: **iPhone Duo** and **iPad Pro 13-inch (M5)**
in the simulator, and the **iPad Pro 12.9-inch (5th generation)** on hardware. That is the whole
test matrix — see
[the device contract](development/architecture/DEVICE_CONTRACT.md#9-the-test-matrix). A result
from any other device, including the 2026-10-02 iPhone 16 Pro Max session recorded below, is
dated history rather than current coverage.

| Level | What ran | What it proves |
| --- | --- | --- |
| Source | The layer gate, the documentation links, the per-module suites, the platform emulation suite, and the developer-service handoff against a synthetic local peer | That the code and its contracts do what the tests assert on a Mac. Nothing about an iPad. |
| Simulator | The launcher pages, touch controls, the on-screen gamepad, input/voice/config rules, the app language, and the UIKit-backed adapters | That our screens and adapters work against stand-ins. Nothing about physical Metal, the tunnel, or memory preparation. |
| Device script | The on-device validation on an **iPad Pro (12.9-inch, 5th generation), iPadOS 27.0.1, Developer service mode**, at source revision `96133d9` - see note below: a guarded live-session install refusal, an authorized replacement after clean stop, existing game data still current, the app's own input, voice, and render-profile self-tests, and no active update write or current error file | That this build behaved that way on that iPad. Nothing about the game. |

### Add-on Hub (2026-11-12)

**Simulators, against a real installation tree.** `wolkaraforever/tools/test_addon_hub_live.sh`
builds the production page (with the shipped Swift archive half) into a small app, fabricates the
installation a player's own folder is - `World of Warcraft/_forever_` with `Interface/AddOns`,
`WTF/Config.wtf`, `Data`, `Logs`, `Cache`, `Screenshots`, `Errors` and `.flavor.info`, and the
client's own path as a placeholder file - and drives the hub on **iPhone Duo** and **iPad Pro
13-inch (M5)**. It reported **42 passed, 0 failed** on the phone and **41 passed, 0 failed** on the
iPad (the difference is one INFO line).

What that proves, measured:

- the page opens on that installation's `Interface/AddOns`, lists the folder already there as
  found-on-device and unlinked, imports a real ZIP as a Files package with a digest and an install
  time, discovers a folder written to disk, refuses to guess a project for either;
- `Discover` and `Browse` are native tabs, and a package with no project reads as unlinked rather
  than as up to date;
- a real `WKWebView` loads `www.curseforge.com` and the site answers with a ~92-96 KB document, all
  inside the app - the log records `event=handoff outcome=opened`; an archive request to another
  host is refused live (`outcome=rejected reason=untrusted-host`) and installs nothing;
- the launcher's own backup and restore carry `Interface/`, so a folder deleted by hand comes back
  and the store reads its packages again;
- the API key, when one is supplied, never appears in the log, and no `addon-hub` line contains a
  URL.

What is **not** covered here:

- **No physical-iPad run.** The iPad Pro 12.9-inch (5th generation) was not available, and no
  simulator result is presented as a physical one.
- **The API half needs the player's own key.** No Core API key was configured in this environment,
  so the live search, Discover's sections, an API install and an in-app browser download ran as
  NOT RUN. The harness takes the key from `WK_LIVE_API_KEY` and asserts it never reaches the log;
  until it is supplied, those four steps are fixture- and store-tested only.
- **The page's pixels were not photographed.** WebKit renders in another process, so an in-process
  capture shows the app's chrome and not the page, and this simulator's screen capture returned the
  app's window as a blank frame. The page load is proven by the navigation, the document length and
  the log, not by a picture of it.

### iPhone

One physical iPhone has been exercised: an **iPhone 16 Pro Max on iOS 27.0**, Developer service,
on 2026-10-02. It logged in to Forever 1.60.1 (build 70170), entered the world and played for
about two hours without a reported problem; Classic Era 1.15.9 reached its cinematic and login
screen. That is the whole of the iPhone hardware evidence and it is recorded, with its limits,
in [docs/IPHONE.md](docs/IPHONE.md).

Every iPhone record in `wolkaraforever/WoW/DeviceProfile.m` is `measured: NO`. The session above
proves the product ran on one phone, not that a render target was benchmarked. No other iPhone
model, iOS version, execution mode or game build has been exercised on hardware, and **no iPhone
result is inferred from the iPad or the other way round**.

The run distinguished command exits from observed self-test results in the matrix; the matrix
runner's final terminal exit was not retained by the host capture.

### Not run in the `96133d9` validation

- **Human full-game.** No launch, login, in-world session, performance measurement, or
  gameplay check was part of this work. Nothing here says the game works.
- **External JIT.** Not exercised at all. The unsigned generic `.ipa` exists for sideloading;
  that is not a compatibility result.
- **Dictation in the game's own text field.** The app's own voice self-test opened a real
  iPad dictation session, restored it, and measured **-25.8 dBFS**. That demonstrates an
  on-device microphone signal reaching the app, not that speech becomes text in the game.
- **The game's own text field.** `selftest dictation-target` asks a *running* guest whether it
  takes words and keys; with no game launched it correctly reports 0/1 checks. Launching the
  game is outside this work, so it is deferred with that reason.
- **A real controller button in a hand.** The on-device input self-test drives the router with
  a synthetic press, which proves the mapper, both modes and the published key set, not what
  iPadOS reports for a particular pad's buttons.
- **The store and the account.** No install, update or repair was performed against the
  client's own files.

### 2026-11-11: held mouse-button tracking — simulators only

The v1.0.7 held-button change (`0047-pump-native-control-tracking`, and the mouse observer in
`ControllerInspector.m`) was measured on the two matrix simulators and on no other device:

```text
touch-controls fixture --mouse-tracking-test       iPad Pro 13-inch (M5)  PASS 18/18
touch-controls fixture --mouse-tracking-test       iPhone Duo            PASS 18/18
touch-controls fixture --tracking-progress-test    iPad Pro 13-inch (M5)  PASS
touch-controls fixture --tracking-progress-test    iPhone Duo            PASS (10/10 runs)
gamepad fixture --self-test / --self-test-input    both                  PASS
voice/input fixture (MOUSE_CALLBACKS)              both                  PASS
```

Each held-button case is one mouse button (left, right, middle) × one queue condition (empty,
busy, blocking) × one cycle, twice over. The tracking fixture asserts that a default-mode and a
tracking-mode timer both progress while the native keyboard or the gamepad settings surface is
open. This is a bounded input result, not a latency measurement and not a long-session result.

**No physical trackpad result is claimed.** The contributor reported three click-hold-drag-release
cycles on their own iPad at revision `d6fc0bb9b1ba3c683c52c0dbdc853d0c8f74f8ea`; that report is
not a measurement this repository can check, and it is not this head. `git diff` shows the four
production input files byte-identical between that revision and the merged one, but byte-identity
is not device evidence, so neither the report nor the identity is carried as a compatibility
result. The hardware entry for held-button dragging stays absent until it is measured here.

### 2026-11-13: Touch Controller 2 — simulators only

The Full/Simple arrangement, the stick buttons, the ability zones and the direct-camera
lifecycle were measured on the two matrix simulators and on no other device:

```text
touch-gamepad fixture --self-test         iPad Pro 13-inch (M5)  PASS 7/7, both interfaces
touch-gamepad fixture --self-test         iPhone Duo            PASS 7/7, both interfaces
touch-gamepad fixture --self-test-input   iPad Pro 13-inch (M5)  PASS 3/3, both interfaces
touch-gamepad fixture --self-test-input   iPhone Duo            PASS 3/3, both interfaces
touch-controls fixture --self-test        both                  PASS
translation simulation suite              both                  PASS
```

What is proved there: a cancelled touch keeps the platform's suppress-until-lift rule while
every exit the app causes releases once and leaves nothing behind; an old layout dictionary
migrates to Full with every value it carried; a
dictionary a later build wrote is never rewritten; an unknown mode is Full; Simple's positions
are its own and turning it off deletes nothing; a stick button is one press and one release,
never on a drag; every ability-zone press has exactly one release, even when two zones share a
button; the direct camera rebases a jumped centroid and releases a drag on background, resign,
resize, settings, a controller arriving and teardown.

**Stick buttons are not claimable on this build, measured rather than assumed.** Apple's
`GCVirtualController` extended profile carries the face buttons, the shoulders, the triggers,
the menu, the D-pad and the sticks' directions - no stick-button element. Declaring
`GCInputLeftThumbstickButton` in the configuration changes nothing, `-leftThumbstickButton` is
nil, and a value set for it is dropped. The app therefore offers the gesture, refuses it with
`touch-controller event=gesture outcome=refused reason=unsupported`, and says so in the row
that owns the setting. The positive path is proved against a controller that does carry the
element (the fixture's own stand-in), not against the virtual one.

**No physical iPad result is claimed.** The iPad Pro 12.9-inch (5th generation) was not
available for this change.

## Before you rely on it

- Use your own eligible account and game files.
- Install through the [current installation guide](docs/INSTALLATION.md), not an older release
  instruction.
- Test sign-in, graphics, controls, voice, add-ons, and the recovery flow yourself for the
  iPad and game build you intend to use.
- Keep a UI backup before changing game settings or add-ons.

Historical engineering and device observations are not current compatibility promises.
