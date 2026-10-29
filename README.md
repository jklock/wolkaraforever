<p align="center">
  <img src="docs/assets/wolkaraforever-logo.png" width="360" alt="WolkaraForever">
</p>

# WolkaraForever

> **Current as of 2026-10-28 · source revision `fbd69f8`**

WolkaraForever is an iPad launcher and WoW Forever layer built on
[Tolkara](https://github.com/tolkara/tolkara). It runs the client locally on the iPad;
it is not game streaming. You supply the Apple development account, iPad, WoW account,
and game data. None of those are included in this repository.

## What it provides

- Downloads, updates, verifies, and starts the Forever client from the app.
- Supports Europe, Americas, Korea, and Taiwan download regions, with English, Spanish,
  and German launcher choices. For an installed Forever client, changing language updates
  the game's text and audio locale together without changing the login region.
- Provides touch controls, an in-game toolbar, an on-screen keyboard and gamepad,
  physical-controller input, and configurable voice dictation.
- Manages add-ons: view installed packages, import an archive, open the add-on directory,
  and browse CurseForge when an approved Core API key is configured on the device.
- Backs up and restores the Forever UI, resets only graphics/display settings, enables the
  game's `GamePadEnable` setting, and shows an optional in-game performance overlay.
- Uses background-aware frame pacing: when the app leaves the foreground its Metal loop is
  capped at 5 fps, then returns to normal pacing on foregrounding. iPadOS still decides
  whether a backgrounded app remains active.

## Install

This is a source install—not an App Store, TestFlight, or public-IPA product. The
supported route requires an Apple-silicon Mac, current Xcode, XcodeGen, Python 3, a paid
Apple Developer membership, and an iPad in Developer Mode with sufficient free storage
(about 70 GB for Forever).

Start with [Install WolkaraForever](docs/INSTALLATION.md). It covers signing, device
configuration, the supported install command, first launch, and recovery steps. After the
app is installed, [Using WolkaraForever](docs/USING_WOLKARAFOREVER.md) covers game
installation, controls, voice, add-ons, updates, and UI recovery.

## Limits and safety

- Startup memory preparation can take several minutes. Keep the app foregrounded until the
  game appears.
- A listed client or feature is not a promise that it works on every iPad or client build.
  Read [Compatibility](COMPATIBILITY.md) for the evidence boundary and historical results.
- The original executable is imported as verified data; this project does not patch or
  re-sign it, automate gameplay, inspect a running game's memory beyond loading and
  verification, or bypass anti-cheat, licence, or integrity checks.
- Use **Settings → Technical details** and a redacted log when asking for help. Do not
  share credentials, provisioning data, pairing records, or device identifiers. Do not
  delete the app as a first troubleshooting step: that removes its downloaded data and
  enrollment state.

## Project documentation

The user documentation is in [docs/](docs/README.md). Engineering architecture, tool
references, tests, contribution guidance, and historical validation records are under
[development/](development/README.md). `platform/` is the separately maintained,
byte-identical Tolkara vendor tree; WolkaraForever's additions live in `wolkaraforever/`.

## Legal

WolkaraForever and Tolkara are released under the [MIT License](LICENSE). See
[NOTICE.md](NOTICE.md) for third-party notices and [SECURITY.md](SECURITY.md) for
vulnerability reporting. World of Warcraft and Blizzard are trademarks of their respective
owners; WolkaraForever is not affiliated with Blizzard.
