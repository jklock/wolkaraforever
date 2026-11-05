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

The dated record for that run is
[development/validation/96133d9.md](development/validation/96133d9.md). It distinguishes
the commands with captured success exits from the observed self-test results in the matrix;
the matrix runner's final terminal exit was not retained by the host capture.

### iPhone, branch `experience-mobile` (2026-11-05)

Human full-game, one device and one session: an **iPhone Duo, iOS 27.2, Developer service**,
WoW Forever 1.60.1.70790 (client executable sha256 `4e262ff6...`), on Wi-Fi, with the build of
`582c597` (it differed from that commit only in comments). The login at 17:14 went through
and the session continued past the login screen: 148 more shader libraries compiled and the
game captured the pointer for its camera. From 11:44 to 16:15 the same login had been refused
at Battle.net's logon form submission (BLZ51914400, BLZ51914500), on mobile data and on Wi-Fi,
while the same client on a Mac was accepted with the same account; the refusal ended on
Blizzard's side. A session started on mobile data alone was not tried again after that.

### Not run, and deliberately not claimed

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

## Before you rely on it

- Use your own eligible account and game files.
- Install through the [current installation guide](docs/INSTALLATION.md), not an older release
  instruction.
- Test sign-in, graphics, controls, voice, add-ons, and the recovery flow yourself for the
  iPad and game build you intend to use.
- Keep a UI backup before changing game settings or add-ons.

Historical engineering and device evidence is preserved under
[development/validation/](development/validation/), where it remains explicitly dated rather
than being presented as current compatibility.
