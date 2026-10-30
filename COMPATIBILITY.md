# Compatibility

> **Current source review: 2026-10-29 · branch `main`.**

Compatibility is specific to an iPad model, iPadOS version, WoW build, execution mode,
account state, and the exact source revision. This page deliberately does not turn a past
result into a broad support promise.

## Current product boundary

WolkaraForever currently presents the Forever install and launcher flow. The source includes
download/update verification, add-on management, touch and controller input, voice
configuration, UI backup/restore, graphics-only reset, the gamepad setting, performance
overlay, and background-aware frame pacing. Their presence in source is not the same as a
physical pass on every iPad.

The supported integrated installation path is the iPad Developer service. The repository
also contains engineering paths for Local signing and External JIT; neither should be read as
a general consumer-install promise.

## Evidence currently available

Every result is at one of four levels (see
[the user guide](docs/README.md#how-much-a-statement-here-proves)): source, simulator,
device script, or human full-game. A result never moves up a level without a new run at that
level.

| Level | What ran | What it proves |
| --- | --- | --- |
| Source | The layer gate, the documentation links, the per-module suites, the platform emulation suite, and the developer-service handoff against a synthetic local peer | That the code and its contracts do what the tests assert on a Mac. Nothing about an iPad. |
| Simulator | The launcher pages, touch controls, the on-screen gamepad, input/voice/config rules, the app language, and the UIKit-backed adapters | That our screens and adapters work against stand-ins. Nothing about physical Metal, the tunnel, or memory preparation. |
| Device script | The on-device matrix on an **iPad Pro (12.9-inch, 5th generation), iPadOS 27.0.1, Developer service mode**, at source revision `b8cebe7`: fresh install with the user's file preserved, config import, malformed config refused and kept, notices, background/foreground, the app's own input and render-profile self-tests, no new crash report, no new game error file | That this build behaved that way on that iPad. Nothing about the game. |

The dated record for that run is
[development/validation/b8cebe7.md](development/validation/b8cebe7.md), which names the
commit, host, Xcode, device and every command with its exit status. Twenty-three steps ran
and every one passed, including the install, the launch and the on-device matrix.

### Not run, and deliberately not claimed

- **Human full-game.** No launch, login, in-world session, performance measurement, or
  gameplay check was part of this work. Nothing here says the game works.
- **External JIT.** Not exercised at all. The unsigned generic `.ipa` exists for sideloading;
  that is not a compatibility result.
- **A spoken word through the microphone.** The app's own voice self-test opens a real
  dictation session and hands it back, and passed everything a script can drive, but measured
  **-120.0 dBFS** — digital silence rather than a quiet room — on every one of three runs.
  Until someone speaks into the iPad, whether the microphone reaches the app is unproven, and
  it is listed as deferred in the matrix rather than counted as a pass.
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
