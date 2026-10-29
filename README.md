<p align="center">
  <img src="docs/assets/wolkaraforever-logo.png" width="360" alt="WolkaraForever">
</p>

# WolkaraForever

World of Warcraft Forever on iPad, built on [Tolkara](https://github.com/tolkara/tolkara).
WolkaraForever runs the game locally; it is not streamed from a Mac.

The app lets you download and update WoW Forever on the iPad, use touch or physical
controls, manage add-ons, configure voice dictation, and back up or restore your UI.
Game files and account access are always yours: none are included in this repository.

## Install and play

WolkaraForever is a source install for people with an Apple-silicon Mac, Xcode, a paid
Apple Developer membership, and an iPad in Developer Mode. It is not an App Store,
TestFlight, or public IPA release.

Follow the [installation guide](docs/INSTALLATION.md). It covers requirements, the one
supported build/install command, signing setup, enrollment, first launch, and the first
things to check if installation fails.

Once installed, read [Using WolkaraForever](docs/USING_WOLKARAFOREVER.md) for:

- downloading and updating Forever;
- add-ons and CurseForge;
- touch controls, controllers, and voice input;
- UI backup, restore, graphics reset, and the performance overlay.

## Important limits

- Memory preparation can take several minutes at each launch. Keep the app in the
  foreground until the game appears.
- The supported integrated route uses the iPad Developer service. Other execution modes
  are engineering workflows, not user-install alternatives.
- A listed edition is not a compatibility promise. See [Compatibility](COMPATIBILITY.md)
  for dated, device-specific results.
- WolkaraForever is not affiliated with Blizzard. It does not include anti-cheat,
  license, integrity, or game-automation workarounds.

## Need help?

Use **Settings → Technical details** in the app and include its exact message plus a
redacted log when requesting help. Do not share account credentials, pairing material, or
device identifiers. Do not delete the app as a first troubleshooting step: that removes
downloaded game data and enrollment state.

## Development

Engineering documentation, architecture, tool references, tests, and historical evidence
are under [development/](development/README.md). The vendored Tolkara platform is kept
separate under `platform/`; WolkaraForever's layer is in `wolkaraforever/`.

## Legal

WolkaraForever and Tolkara are released under the [MIT License](LICENSE). Third-party
notices are in [NOTICE.md](NOTICE.md). World of Warcraft and Blizzard are trademarks of
their respective owners.
